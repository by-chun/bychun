import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../native/native_bridge.dart';
import '../pages/video_page.dart';
import 'agent_engine.dart';
import 'audio_service.dart';
import 'tool.dart';
import 'tool_registry.dart';
import 'tools_web.dart';

/// 让 AI 自己造悬浮窗界面（HTML），并保证功能按钮能真正调到工具。
class CreateOverlayTool extends AgentTool {
  @override
  String get name => 'createOverlay';

  @override
  String get description =>
      '创建/更新悬浮窗界面（HTML，点悬浮球打开）。窗体尺寸随内容自适应，样式自由发挥。'
      '按钮里调用：Rowan.call("工具名", JSON.stringify(参数), "回调id")，'
      '结果回到 window.__rowanResult(cbId, json)。支持的工具：memScan/memRead/memWrite/'
      'playAudio/playVideo/httpRequest/webSearch/shell/containerShell。';

  @override
  Map<String, String> get parameters => {'html': '完整 HTML 字符串'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final html = args['html'] ?? '';
    if (html.trim().isEmpty) return const ToolResult(false, 'html 不能为空');
    // 先确保服务起来（否则 HTML 会被丢掉），再写入
    await NativeBridge.showOverlay();
    await Future.delayed(const Duration(milliseconds: 250));
    final ok = await NativeBridge.setOverlayHtml(html);
    if (!ok) return const ToolResult(false, '设置失败（悬浮窗权限可能被拒）');
    return const ToolResult(true, '悬浮窗已显示');
  }
}

/// 运行 Java 插件（容器里编译出的 dex），可创建原生悬浮窗。
class RunJavaOverlayTool extends AgentTool {
  @override
  String get name => 'runJavaOverlay';

  @override
  String get description =>
      '加载容器里编译好的 dex 并执行 Java 插件（入口 public static void run(Context)）。'
      '典型流程：Alpine 里 apk add openjdk17，用 javac + d8(--lib android.jar) 把 .java 编成 classes.dex，'
      '再把 dex 路径和类名传进来，即可创建原生悬浮窗/自定义 View。';

  @override
  Map<String, String> get parameters => {
        'dex': 'dex 文件绝对路径',
        'className': '完整类名，如 com.rowan.MyOverlay',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final dex = (args['dex'] ?? '').trim();
    final cls = (args['className'] ?? '').trim();
    if (dex.isEmpty || cls.isEmpty) return const ToolResult(false, 'dex 和 className 都要填');
    final r = await NativeBridge.runJavaPlugin(dex, cls);
    return ToolResult(r == 'OK', r);
  }
}

/// 关闭悬浮窗（保留悬浮球）。
class CloseOverlayTool extends AgentTool {
  @override
  String get name => 'closeOverlay';

  @override
  String get description => '关闭悬浮窗，保留悬浮球。';

  @override
  Map<String, String> get parameters => {};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final ok = await NativeBridge.hideOverlay();
    return ToolResult(ok, ok ? '已关闭' : '关闭失败');
  }
}

/// 悬浮窗 JS 桥：把 Rowan.call(...) 变成真正的工具调用；Rowan.chatSend 走主会话。
class OverlayBridge {
  static const _ch = MethodChannel('rowan/overlayHost');
  static bool _inited = false;
  static bool _visible = false;
  static String _lastPushed = '';
  static Timer? _ticker;

  static void init() {
    if (_inited) return;
    _inited = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'chatSend') {
        final m = (call.arguments as Map?) ?? const {};
        final text = (m['text'] ?? '').toString().trim();
        final engine = AgentEngine.current;
        if (text.isEmpty || engine == null) {
          return jsonEncode({'ok': false, 'msg': '会话未就绪'});
        }
        engine.send(text);
        return jsonEncode({'ok': true});
      }
      if (call.method == 'overlayShown') {
        _visible = true;
        // 重新打开时不要回放上一条旧回复，只等新的输出
        _lastPushed = _sig();
        return true;
      }
      if (call.method == 'overlayHidden') {
        _visible = false;
        return true;
      }
      if (call.method != 'callTool') return jsonEncode({'ok': false, 'msg': 'unknown'});
      final m = (call.arguments as Map?) ?? const {};
      final tool = m['tool']?.toString() ?? '';
      final raw = m['args']?.toString() ?? '{}';
      Map<String, String> args = {};
      try {
        (jsonDecode(raw) as Map).forEach((k, v) => args[k.toString()] = v.toString());
      } catch (_) {}
      return jsonEncode(await run(tool, args));
    });
    // 主会话无论从哪里发起，输出都同步到悬浮窗（页面没实现 __rowanChat 时由原生兜底显示）。
    _ticker ??= Timer.periodic(const Duration(milliseconds: 400), (_) => _push());
  }

  /// 只取「最后一条用户消息之后」的 AI 输出，避免新一轮提问时把上一条回复重发。
  static String _textOf(AgentEngine e) {
    if (e.streaming && e.streamingText.isNotEmpty) return e.streamingText;
    var lastUser = -1;
    for (var i = e.messages.length - 1; i >= 0; i--) {
      if (e.messages[i].role == 'user') {
        lastUser = i;
        break;
      }
    }
    for (var i = e.messages.length - 1; i > lastUser; i--) {
      final msg = e.messages[i];
      if (msg.role == 'assistant' && msg.text.trim().isNotEmpty) return msg.text;
    }
    return '';
  }

  static String _sig() {
    final e = AgentEngine.current;
    if (e == null) return '';
    return '${e.running}|${_textOf(e)}';
  }

  static void _push() {
    if (!_visible) return;
    final e = AgentEngine.current;
    if (e == null) return;
    final text = _textOf(e);
    final sig = '${e.running}|$text';
    if (sig == _lastPushed) return;
    _lastPushed = sig;
    _eval('window.__rowanChat && window.__rowanChat.update(${jsonEncode(text)}, ${e.running})');
  }

  static Future<void> _eval(String js) async {
    try {
      await _ch.invokeMethod('eval', {'js': js});
    } catch (_) {}
  }

  static String _hex(Object? v) {
    final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return n.toRadixString(16);
  }

  /// 悬浮窗可用工具（全部原生能力，不依赖 Alpine 环境）。
  static Future<Map<String, dynamic>> run(String tool, Map<String, String> a) async {
    try {
      switch (tool) {
        case 'memScan':
          final pid = int.tryParse(a['pid'] ?? '') ?? 0;
          final value = a['value'] ?? '';
          final type = a['type'] ?? 'i32';
          if (pid <= 0 || value.isEmpty) return {'ok': false, 'msg': 'PID 或值无效'};
          final region = a['region'] ?? 'all';
          final hits = await Gmem.scan(pid, value, type: type, region: region, max: 50000) ?? const <String>[];
          return {'ok': true, 'items': hits.take(50).map((e) => '${e.replaceFirst('0x', '')}  $value').toList()};
        case 'memRead':
          final pid2 = int.tryParse(a['pid'] ?? '') ?? 0;
          final hex = await Gmem.readHex(pid2, a['address'] ?? '0', size: int.tryParse(a['length'] ?? '4') ?? 4);
          return {'ok': hex != null, 'value': hex ?? ''};
        case 'memWrite':
          final pid3 = int.tryParse(a['pid'] ?? '') ?? 0;
          final ok = await Gmem.writeHex(pid3, a['address'] ?? '0', a['value'] ?? '');
          return {'ok': ok};
        case 'playAudio':
          final r = await AudioService.instance.play(a['url'] ?? '', title: a['title']);
          return {'ok': r.startsWith('开始播放'), 'msg': r};
        case 'playVideo':
          final url = a['url'] ?? '';
          final nav = appNavigatorKey.currentState;
          if (url.isEmpty || nav == null) return {'ok': false, 'msg': 'url 为空或界面未就绪'};
          nav.push(MaterialPageRoute(builder: (_) => VideoPlayerPage(url: url, title: a['title'])));
          return {'ok': true, 'msg': '已打开播放'};
        case 'httpRequest':
          final url = a['url'] ?? '';
          if (!url.startsWith('http')) return {'ok': false, 'msg': 'url 必须是 http(s)'};
          final headers = <String, String>{
            'User-Agent': 'Mozilla/5.0 (Android 14) AppleWebKit/537.36 Chrome/120 Safari/537.36',
          };
          final rh = (a['headers'] ?? '').trim();
          if (rh.isNotEmpty) {
            try {
              (jsonDecode(rh) as Map).forEach((k, v) => headers[k.toString()] = v.toString());
            } catch (_) {}
          }
          final resp = (a['method'] ?? 'GET').toUpperCase() == 'POST'
              ? await http.post(Uri.parse(url), headers: headers, body: a['body'] ?? '')
              : await http.get(Uri.parse(url), headers: headers);
          return {'ok': resp.statusCode < 400, 'body': resp.body};
        case 'webSearch':
          final r = await WebSearchTool().execute({'query': a['query'] ?? ''});
          return {'ok': r.ok, 'body': r.content};
        case 'shell':
          final r = await NativeBridge.exec(a['cmd'] ?? '');
          return {'ok': r.ok, 'stdout': r.stdout, 'stderr': r.stderr};
        case 'containerShell':
          final r = await NativeBridge.prootExec(a['cmd'] ?? '');
          return {'ok': r.ok, 'stdout': r.stdout, 'stderr': r.stderr};
        default:
          return {'ok': false, 'msg': '悬浮窗不支持工具 $tool'};
      }
    } catch (e) {
      return {'ok': false, 'msg': e.toString()};
    }
  }

  /// 订阅容器流式输出，自动推给日志窗。
  static void subscribeOutput() {
    NativeBridge.outputStream.listen((e) {
      final line = e['line']?.toString();
      if (line == null) return;
      NativeBridge.pushLogLine(line);
    });
  }
}

void registerOverlayTools(ToolRegistry reg) {
  reg.register(CreateOverlayTool());
  reg.register(CloseOverlayTool());
  reg.register(RunJavaOverlayTool());
}
