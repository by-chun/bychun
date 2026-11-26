import 'dart:convert';
import 'dart:typed_data';

import 'tool.dart';
import 'tool_registry.dart';
import '../native/native_bridge.dart';
import '../native/gmem.dart';

/// 让 AI 能调用 App 的更多能力（应用/APK/内存/悬浮窗）。

class ListAppsTool extends AgentTool {
  @override
  String get name => 'listApps';
  @override
  String get description => '列出已安装应用（label | package | apk 路径）。';
  @override
  Map<String, String> get parameters => {};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final l = await NativeBridge.listApps();
    if (l.isEmpty) return const ToolResult(false, '没有读到应用（需存储/查询权限）');
    return ToolResult(
      true,
      '共 ${l.length} 个应用，已列在窗口里',
      view: 'list',
      title: '已安装应用',
      viewData: {
        'items': [
          for (final a in l)
            {
              'title': (a['label'] ?? '').toString(),
              'subtitle': (a['package'] ?? '').toString(),
              'badge': a['system'] == true ? '系统' : '用户',
            },
        ],
      },
    );
  }
}



class MemScanTool extends AgentTool {
  static const _aliases = {
    'a': 'auto', 'auto': 'auto',
    'b': 'i32', 'byte': 'i32', 'i8': 'i32',
    'w': 'i32', 'word': 'i32', 'i16': 'i32',
    'd': 'i32', 'dword': 'i32', 'i32': 'i32',
    'q': 'i64', 'qword': 'i64', 'i64': 'i64',
    'f': 'f32', 'float': 'f32', 'f32': 'f32',
    'e': 'f64', 'double': 'f64', 'f64': 'f64',
    'h': 'bytes', 'hex': 'bytes', 'bytes': 'bytes',
  };
  static const _types = {'i32', 'i64', 'f32', 'f64', 'bytes'};
  static const _regions = {'all', 'ca', 'jh', 'cd', 's'};

  @override
  String get name => 'memScan';
  @override
  String get description =>
      '在目标进程里搜值（需 root）。type 可用 GG 简称 A(自动)/B/W/D/Q/F/E/H 或 i32/i64/f32/f64/bytes，默认 i32；'
      'region 可选 all(全部)/ca(匿名)/jh(Java堆)/cd(文件数据)/s(栈)，默认 all。';
  @override
  Map<String, String> get parameters => {
        'pid': '进程 PID',
        'value': '要搜的值（整数/浮点/hex 字符串）',
        'type': '可选：A(自动)/i32/i64/f32/f64/bytes，默认 i32',
        'region': '可选：all/ca/jh/cd/s，默认 all',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final pid = int.tryParse(args['pid'] ?? '');
    final raw = (args['value'] ?? '').trim();
    var type = _aliases[(args['type'] ?? 'i32').trim().toLowerCase()] ??
        (args['type'] ?? 'i32').trim().toLowerCase();
    var region = (args['region'] ?? 'all').trim().toLowerCase();
    if (region.isEmpty || !_regions.contains(region)) region = 'all';
    if (pid == null || raw.isEmpty) return const ToolResult(false, 'pid/value 不能为空');
    if (type == 'auto') type = _inferType(raw);
    if (!_types.contains(type)) {
      return const ToolResult(false, 'type 只支持 A/i32/i64/f32/f64/bytes');
    }
    final hits = await Gmem.scan(pid, raw, type: type, region: region, max: 200000) ?? const <String>[];
    if (hits.isEmpty) return const ToolResult(false, '未命中（root 未授权、pid 不存在，或该区域无此值）');
    return ToolResult(
      true,
      '命中 ${hits.length} 处（$type · $region），已列在窗口里',
      view: 'list',
      title: 'memScan · $raw',
      viewData: {
        'items': [for (final a in hits) {'title': a, 'subtitle': 'pid $pid', 'badge': type}],
      },
    );
  }

  static String _inferType(String raw) {
    final s = raw.trim();
    if (s.startsWith('0x') || s.startsWith('0X')) return 'bytes';
    if (s.contains('.')) return 'f32';
    final b = BigInt.tryParse(s);
    if (b == null) return 'f32';
    return (b > BigInt.from(0x7FFFFFFF) || b < BigInt.from(-0x80000000)) ? 'i64' : 'i32';
  }
}

class MemReadTool extends AgentTool {
  @override
  String get name => 'memRead';
  @override
  String get description => '读取进程内存（十六进制）。';
  @override
  Map<String, String> get parameters => {'pid': 'PID', 'addr': '地址(0x..)', 'size': '字节数'};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final pid = int.tryParse(args['pid'] ?? '');
    final addr = int.tryParse(args['addr'] ?? '', radix: 16) ?? int.tryParse(args['addr'] ?? '');
    final size = int.tryParse(args['size'] ?? '64') ?? 64;
    if (pid == null || addr == null) return const ToolResult(false, 'pid/addr 无效');
    final hex = await Gmem.readHex(pid, '0x${addr.toRadixString(16)}', size: size);
    if (hex != null) return ToolResult(true, hex);
    final b = await NativeBridge.memoryRead(pid, addr, size: size);
    if (b == null) return const ToolResult(false, '读取失败（需 root）');
    return ToolResult(true, b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' '));
  }
}

class MemWriteTool extends AgentTool {
  @override
  String get name => 'memWrite';
  @override
  String get description =>
      '写进程内存（需 root）。type 支持 i8/i16/i32/i64/f32/f64/bytes，默认 i32；'
      '64 位应用写 long 用 i64，写浮点用 f32/f64，写任意字节用 bytes（hex 字符串，可带空格）。';
  @override
  Map<String, String> get parameters => {
        'pid': 'PID',
        'addr': '地址',
        'value': '要写入的值',
        'type': '可选：i8/i16/i32/i64/f32/f64/bytes，默认 i32',
      };
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final pid = int.tryParse(args['pid'] ?? '');
    final addr = int.tryParse(args['addr'] ?? '', radix: 16) ?? int.tryParse(args['addr'] ?? '');
    final type = (args['type'] ?? 'i32').trim().toLowerCase();
    if (pid == null || addr == null) return const ToolResult(false, 'pid/addr 无效');
    final bytes = _encodeValue(type, args['value'] ?? '');
    if (bytes == null) return ToolResult(false, 'value 与 type=$type 不匹配');

    final hex = bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    final okG = await Gmem.writeHex(pid, '0x${addr.toRadixString(16)}', hex);
    if (okG) return ToolResult(true, '已写入 ${bytes.length} 字节');
    final ok = await NativeBridge.memoryPatch(pid, addr, bytes);
    return ToolResult(ok, ok ? '已写入 ${bytes.length} 字节' : '写入失败（需 root）');
  }

  static List<int>? _encodeValue(String type, String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      switch (type) {
        case 'i8':
        case 'i16':
        case 'i32':
          final v = _parseInt(s);
          if (v == null) return null;
          final n = type == 'i8' ? 1 : (type == 'i16' ? 2 : 4);
          return [for (var i = 0; i < n; i++) (v >> (8 * i)) & 0xFF];
        case 'i64':
          final v = _parseBigInt(s);
          if (v == null) return null;
          return [for (var i = 0; i < 8; i++) ((v >> (8 * i)) & BigInt.from(0xFF)).toInt()];
        case 'f32':
          final d = double.parse(s);
          return (ByteData(4)..setFloat32(0, d, Endian.little)).buffer.asUint8List();
        case 'f64':
          final d = double.parse(s);
          return (ByteData(8)..setFloat64(0, d, Endian.little)).buffer.asUint8List();
        case 'bytes':
        case 'hex':
          final clean = s.replaceAll(RegExp(r'0x|0X|[\s,:-]'), '');
          if (clean.isEmpty || clean.length.isOdd) return null;
          return [for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16)];
      }
    } catch (_) {}
    return null;
  }

  static int? _parseInt(String s) => s.startsWith('0x') || s.startsWith('0X')
      ? int.tryParse(s.substring(2), radix: 16)
      : int.tryParse(s);

  static BigInt? _parseBigInt(String s) => s.startsWith('0x') || s.startsWith('0X')
      ? BigInt.tryParse(s.substring(2), radix: 16)
      : BigInt.tryParse(s);
}

class OverlayTool extends AgentTool {
  @override
  String get name => 'overlay';
  @override
  String get description => '打开或关闭内存搜索悬浮窗。';
  @override
  Map<String, String> get parameters => {'action': 'show 或 hide'};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final a = (args['action'] ?? 'show').toLowerCase();
    final ok = a == 'hide' ? await NativeBridge.hideOverlay() : await NativeBridge.showOverlay();
    return ToolResult(ok, ok ? '已${a == 'hide' ? '关闭' : '打开'}悬浮窗' : '操作失败（需悬浮窗权限）');
  }
}



class ShizukuExecTool extends AgentTool {
  @override
  String get name => 'shizukuExec';
  @override
  String get description => '通过 Shizuku 以 shell 权限执行命令（免 root）。需已装 Shizuku 并授权。';
  @override
  Map<String, String> get parameters => {'cmd': '要执行的命令'};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final cmd = args['cmd'] ?? '';
    if (cmd.isEmpty) return const ToolResult(false, 'cmd 为空');
    if (!await NativeBridge.shizukuAvailable()) {
      return const ToolResult(false, 'Shizuku 未就绪：先安装并启动 Shizuku');
    }
    if (!await NativeBridge.shizukuPermission()) await NativeBridge.shizukuRequest();
    final r = await NativeBridge.shizukuExec(cmd);
    final out = '${r.stdout}${r.stderr}'.trim();
    return ToolResult(r.ok, out.isEmpty ? '（无输出，exit ${r.code}）' : out);
  }
}



class ShowTextTool extends AgentTool {
  @override
  String get name => 'showText';

  @override
  String get description =>
      '在对话里打开小说/长文阅读窗口。单篇传 content；有目录时传 chapters（JSON 数组，每项 {title,url?/content?}），'
      '卡片会显示目录、搜索与跳章，切章时按 url 现抓正文。';

  @override
  Map<String, String> get parameters => {
        'title': '标题（书名）',
        'content': '正文（单篇时必填，有 chapters 时可空）',
        'chapters': '可选：JSON 数组，如 [{"title":"第1章 雨夜","url":"https://..."}]',
        'index': '可选：从第几章开始，默认 1',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final title = (args['title'] ?? '').trim().isEmpty ? '阅读' : args['title']!.trim();
    final raw = (args['chapters'] ?? '').trim();
    final chapters = <Map<String, String>>[];
    if (raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          final m = Map<String, dynamic>.from(e as Map);
          chapters.add({
            'title': (m['title'] ?? '').toString(),
            'url': (m['url'] ?? '').toString(),
            'content': (m['content'] ?? '').toString(),
          });
        }
      } catch (_) {
        return const ToolResult(false, 'chapters 不是合法的 JSON 数组');
      }
    }
    var index = int.tryParse((args['index'] ?? '1').trim()) ?? 1;
    var content = args['content'] ?? '';
    if (chapters.isNotEmpty) {
      index = index.clamp(1, chapters.length).toInt();
      if (content.trim().isEmpty) content = chapters[index - 1]['content'] ?? '';
    }
    if (content.trim().isEmpty && chapters.isEmpty) {
      return const ToolResult(false, 'content 和 chapters 至少传一个');
    }
    return ToolResult(
      true,
      chapters.isEmpty ? '已打开阅读窗口：$title（${content.length} 字）' : '已打开阅读窗口：$title（共 ${chapters.length} 章）',
      view: 'reader',
      title: title,
      viewData: {
        'content': content,
        'title': title,
        'chapters': chapters,
        'index': index,
      },
    );
  }
}

/// 漫画阅读：章节 + 每章图片列表。
class ShowComicTool extends AgentTool {
  @override
  String get name => 'showComic';

  @override
  String get description =>
      '打开漫画阅读窗口。chapters 传 JSON 数组，每项 {title, pages:[图片直链或本地路径...]}；'
      '卡片会列目录、左右翻页、双击缩放，切话时加载对应图片。';

  @override
  Map<String, String> get parameters => {
        'title': '标题（书名）',
        'chapters': 'JSON 数组，如 [{"title":"第1话","pages":["https://...jpg"]}]',
        'index': '可选：从第几话开始，默认 1',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final title = (args['title'] ?? '').trim().isEmpty ? '漫画' : args['title']!.trim();
    final raw = (args['chapters'] ?? '').trim();
    if (raw.isEmpty) return const ToolResult(false, 'chapters 不能为空');
    final chapters = <Map<String, dynamic>>[];
    try {
      final list = jsonDecode(raw) as List;
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        final pages = ((m['pages'] as List?) ?? const []).map((p) => p.toString()).where((p) => p.isNotEmpty).toList();
        if (pages.isEmpty) continue;
        chapters.add({'title': (m['title'] ?? '').toString(), 'pages': pages});
      }
    } catch (_) {
      return const ToolResult(false, 'chapters 不是合法的 JSON 数组');
    }
    if (chapters.isEmpty) return const ToolResult(false, '没有有效的图片页');
    final index = (int.tryParse((args['index'] ?? '1').trim()) ?? 1).clamp(1, chapters.length).toInt();
    return ToolResult(
      true,
      '已打开漫画：$title（共 ${chapters.length} 话）',
      view: 'comic',
      title: title,
      viewData: {'title': title, 'chapters': chapters, 'index': index},
    );
  }
}

void registerExtraTools(ToolRegistry reg) {
  reg.register(ListAppsTool());
  reg.register(MemScanTool());
  reg.register(MemReadTool());
  reg.register(MemWriteTool());
  reg.register(OverlayTool());
  reg.register(ShizukuExecTool());
  reg.register(ShowTextTool());
  reg.register(ShowComicTool());
}
