import 'tool.dart';
import 'tool_registry.dart';
import '../native/native_bridge.dart';

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

void registerCaptureTools(ToolRegistry reg) {
  reg.register(CaptureStartTool());
  reg.register(VpnSetDnsTool());
  reg.register(CaptureStopTool());
  reg.register(CaptureRecordClearTool());
  reg.register(CaptureListTool());
  reg.register(StopTasksTool());
}
