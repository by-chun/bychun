import 'dart:convert';

import 'tool.dart';
import 'tool_registry.dart';
import '../native/native_bridge.dart';

/// 把内容（base64）写入用户可见工作区文件，返回是否成功。
Future<bool> _writeWorkspaceFile(String path, String content) async {
  final b64 = base64Encode(utf8.encode(content));
  final dir = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '/storage/emulated/0/Rowan';
  final r = await NativeBridge.exec(
      "mkdir -p '$dir' && printf %s '$b64' | base64 -d > '$path' && echo OK");
  return r.stdout.contains('OK');
}

/// 抓包相关工具：开始 / 停止 / 列出已抓到的域名。
/// 列出结果带 view=list，聊天里会渲染成卡片。
class CaptureStartTool extends AgentTool {
  @override
  String get name => 'capture_start';
  @override
  String get description => '开始抓包（VPN 只拦截 DNS，不影响上网）。首次会弹系统 VPN 授权。';
  @override
  Map<String, String> get parameters => const {};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final r = await NativeBridge.vpnStart();
    final dns = (r['dns'] ?? '').toString();
    final ok = r['ok'] == true && r['running'] == true;
    if (ok) {
      return ToolResult(true, '抓包已开始，上游 DNS：$dns',
          view: 'capture', title: '抓包');
    }
    if (r['needDns'] == true) {
      return const ToolResult(
          false, '系统 DNS 自动获取失败：直接问用户要一个上游 DNS（或调 askForm 收），再用 vpnSetDns 写入');
    }
    return const ToolResult(false, '抓包启动失败：需要授予 VPN 权限');
  }
}

class CaptureStopTool extends AgentTool {
  @override
  String get name => 'capture_stop';
  @override
  String get description => '停止抓包。';
  @override
  Map<String, String> get parameters => const {};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    await NativeBridge.vpnStop();
    return const ToolResult(true, '抓包已停止');
  }
}

class CaptureRecordClearTool extends AgentTool {
  @override
  String get name => 'capture_clear';
  @override
  String get description => '清空已抓到的记录。';
  @override
  Map<String, String> get parameters => const {};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    await NativeBridge.vpnClear();
    return const ToolResult(true, '已清空抓包记录');
  }
}

class CaptureListTool extends AgentTool {
  @override
  String get name => 'capture_list';
  @override
  String get description =>
      '列出已抓到的域名（DNS 级：域名、时间、解析 IP）。数据不大，可放心调用；不含请求头/响应体。';
  @override
  Map<String, String> get parameters => {'filter': '可选：按域名/IP 过滤'};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final filter = (args['filter'] ?? '').trim();
    final raw = await NativeBridge.vpnLog();
    if (raw.trim().isEmpty) {
      return const ToolResult(true, '还没有抓到记录。先用 capture_start 开始抓包。');
    }
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    // 每行格式：<毫秒时间戳> <域名> -> <ip,ip>
    final items = <Map<String, String>>[];
    final seen = <String>{};
    for (final line in lines.reversed) {
      final idx = line.indexOf(' ');
      if (idx <= 0) continue;
      final ts = int.tryParse(line.substring(0, idx));
      final rest = line.substring(idx + 1);
      final arrow = rest.indexOf(' -> ');
      if (arrow <= 0) continue;
      final host = rest.substring(0, arrow).trim();
      final ips = rest.substring(arrow + 4).trim();
      if (host.isEmpty || host == '?') continue;
      if (filter.isNotEmpty && !host.contains(filter) && !ips.contains(filter)) continue;
      if (!seen.add(host)) continue; // 同一域名只列一次（最新的那条）
      items.add({
        'title': host,
        'subtitle': '${_fmt(ts)} · ${ips == '?' ? '无解析' : ips}',
        'badge': 'DNS',
      });
      if (items.length >= 80) break;
    }
    if (items.isEmpty) return const ToolResult(true, '没有匹配的记录');
    final sb = StringBuffer();
    for (final it in items) {
      sb.writeln('${it['title']}  ${it['subtitle']}');
    }
    return ToolResult(
      true,
      '抓到 ${lines.length} 条查询，去重后 ${items.length} 个域名',
      view: 'list',
      title: '抓包 · 域名',
      viewData: {'items': items},
    );
  }

  String _fmt(int? ms) {
    if (ms == null) return '--:--:--';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}

/// 手动设置抓包的上游 DNS（自动获取失败或用户指定时用），设完会重启 VPN。
class VpnSetDnsTool extends AgentTool {
  @override
  String get name => 'vpnSetDns';
  @override
  String get description => '设置抓包上游 DNS 并重启 VPN。系统自动获取不到 DNS、或用户指定了 DNS 时用。';
  @override
  Map<String, String> get parameters => {'dns': 'DNS 服务器地址，如 192.168.1.1' };
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final dns = (args['dns'] ?? '').trim();
    if (dns.isEmpty) return const ToolResult(false, 'dns 不能为空');
    final ok = await NativeBridge.vpnSetDns(dns);
    if (!ok) return const ToolResult(false, '设置失败（可能没有 VPN 权限）');
    await Future.delayed(const Duration(milliseconds: 900));
    final st = await NativeBridge.vpnStatus();
    final running = st['running'] == true;
    return ToolResult(
      running,
      running ? '上游 DNS 已设为 $dns，抓包在跑' : '已保存 $dns，但 VPN 还没起来（检查 VPN 权限）',
      view: 'capture',
      title: '抓包',
    );
  }
}

/// 停止容器里所有后台命令（对话里的停止只管 AI 生成，后台任务要靠这个关）。
class StopTasksTool extends AgentTool {
  @override
  String get name => 'stop_tasks';
  @override
  String get description => '停止容器里所有正在后台运行的命令与进程（不影响当前对话）。';
  @override
  Map<String, String> get parameters => const {};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    await NativeBridge.killAllProcs();
    return const ToolResult(true, '已停止所有后台命令');
  }
}

/// 读取抓包明文记录（HTTP 请求/响应，来自抓包代理上报），返回 detail 视图。
/// 明文可能含 Token/Cookie，交给 AI 前必须弹确认（在权限层处理，属高危）。
class CaptureReadTool extends AgentTool {
  @override
  String get name => 'capture_read';

  @override
  String get description =>
      '读取抓包明文记录（方法/URL/状态码/请求体/响应体）。'
      '内容是抓包代理上报的 HTTP 明文，可能含 Token/Cookie，返回前会让你确认。'
      '若还没有明文记录（没跑代理），用 capture_list 看 DNS 域名列表。';

  @override
  Map<String, String> get parameters => {'limit': '可选：条数，默认 20'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final limit = int.tryParse((args['limit'] ?? '20').trim()) ?? 20;
    final raw = await NativeBridge.captureLog(limit.clamp(1, 100));
    if (raw == null || raw.trim().isEmpty) {
      return const ToolResult(true, '还没有抓包明文记录。先让代理（mitmproxy/PCAPd）跑起来并上报。');
    }
    Map<String, dynamic> obj;
    try {
      obj = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return ToolResult(false, '抓包明文数据格式异常');
    }
    final items = (obj['items'] as List?) ?? const [];
    final total = (obj['total'] as num?)?.toInt() ?? items.length;
    if (items.isEmpty) {
      return const ToolResult(true, '还没有抓包明文记录。');
    }
    final tabs = <Map<String, dynamic>>[
      {
        'name': '概览',
        'rows': [
          {'k': '明文条数', 'v': '$total'},
          {'k': '返回条数', 'v': '${items.length}'},
          {'k': '提示', 'v': '内容可能含 Token/Cookie，请勿外发'},
        ],
      },
    ];
    var n = 0;
    for (final rawItem in items) {
      if (n++ >= 20) break;
      final h = Map<String, dynamic>.from(rawItem as Map);
      final method = (h['method'] ?? '?').toString();
      final url = (h['url'] ?? '').toString();
      final status = (h['status'] ?? 0).toString();
      String clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}\n…（截断）';
      tabs.add({
        'name': '$method $status',
        'rows': [
          {'k': 'URL', 'v': url.isEmpty ? '—' : url},
          {'k': '状态', 'v': status},
          {'k': '请求', 'v': clip((h['req'] ?? '').toString(), 800)},
          {'k': '响应', 'v': clip((h['res'] ?? '').toString(), 800)},
        ],
      });
    }
    return ToolResult(
      true,
      '共 $total 条抓包明文（已列明细）',
      view: 'detail',
      title: '抓包 · 明文',
      viewData: {'tabs': tabs},
    );
  }
}

/// 把抓到的域名转成可复用脚本：写到工作区 plugins 目录，下次拖进来或用 shell 跑。
class CaptureToScriptTool extends AgentTool {
  @override
  String get name => 'capture_to_script';

  @override
  String get description =>
      '把已抓到的域名（去重）存成脚本：生成 capture-domains.json（域名清单）与 capture-block.sh（屏蔽脚本，需 root）。'
      '文件写到 /storage/emulated/0/Rowan/plugins/，可复用或交给注入模块。';

  @override
  Map<String, String> get parameters => {'filter': '可选：只导出匹配此域名/IP 的记录'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final filter = (args['filter'] ?? '').trim();
    final raw = await NativeBridge.vpnLog();
    if (raw.trim().isEmpty) {
      return const ToolResult(true, '还没有抓到记录，没有可导出的域名。');
    }
    final domains = <String>{};
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final idx = t.indexOf(' ');
      if (idx <= 0) continue;
      final rest = t.substring(idx + 1);
      final arrow = rest.indexOf(' -> ');
      if (arrow <= 0) continue;
      final host = rest.substring(0, arrow).trim();
      if (host.isEmpty || host == '?') continue;
      if (filter.isNotEmpty && !host.contains(filter)) continue;
      domains.add(host);
    }
    if (domains.isEmpty) return const ToolResult(true, '没有匹配的域名可导出。');
    final list = domains.toList()..sort();

    final jsonBody = jsonEncode({
      'generated': DateTime.now().millisecondsSinceEpoch,
      'count': list.length,
      'domains': list,
    });
    final sh = StringBuffer('#!/bin/sh\n# Rowan 抓包 -> 屏蔽脚本（生成自 capture_to_script）\n'
        '# 用法：sh 本文件  （需 root，会往 /etc/hosts 追加条目）\n'
        '# 撤销：手动编辑 /etc/hosts 删除 0.0.0.0 开头对应行\n'
        'cp /etc/hosts /etc/hosts.rowan.bak 2>/dev/null\n');
    for (final d in list) {
      sh.writeln('grep -q "0.0.0.0 $d" /etc/hosts || echo "0.0.0.0 $d" >> /etc/hosts');
    }

    const dir = '/storage/emulated/0/Rowan/plugins';
    final okJson = await _writeWorkspaceFile('$dir/capture-domains.json', jsonBody);
    final okSh = await _writeWorkspaceFile('$dir/capture-block.sh', sh.toString());
    final paths = <String>[
      if (okJson) '$dir/capture-domains.json',
      if (okSh) '$dir/capture-block.sh',
    ];
    if (paths.isEmpty) return const ToolResult(false, '写入失败（检查存储权限）');
    return ToolResult(
      true,
      '已导出 ${list.length} 个域名到：\n${paths.join('\n')}',
      view: 'list',
      title: '抓包 · 导出脚本',
      viewData: {
        'items': [
          for (final p in paths) {'title': p, 'subtitle': '可复用脚本', 'badge': 'file'},
        ],
      },
    );
  }
}

void registerCaptureTools(ToolRegistry reg) {
  reg.register(CaptureStartTool());
  reg.register(VpnSetDnsTool());
  reg.register(CaptureStopTool());
  reg.register(CaptureRecordClearTool());
  reg.register(CaptureListTool());
  reg.register(CaptureReadTool());
  reg.register(CaptureToScriptTool());
  reg.register(StopTasksTool());
}
