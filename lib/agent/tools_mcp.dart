import 'dart:convert';
import 'tool.dart';
import 'tool_registry.dart';
import 'mcp.dart';
import '../native/native_bridge.dart';

class McpListTool extends AgentTool {
  @override
  String get name => 'mcpList';
  @override
  String get description => '列出某个 MCP 服务器提供的工具（先配置 MCP Server）。';
  @override
  Map<String, String> get parameters => {'server': '服务器名称'};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final allServers = await McpStore.load();
    final servers = allServers.where((e) => e.enabled).toList();
    if (servers.isEmpty) {
      final off = allServers.length;
      return ToolResult(true, off > 0 ? '（没有启用的 MCP 服务器，有 $off 个已关闭）' : '（还没有 MCP 服务器）');
    }
    final ms = servers.where((e) => e.enabled && e.name == (args['server'] ?? '')).toList();
    if (ms.isEmpty) return ToolResult(false, '未找到服务器 ${args['server']}（先在 设置→MCP 配置）');
    final s = ms.first;
    try {
      final tools = await McpClient.listTools(s);
      if (tools.isEmpty) return const ToolResult(true, '（该服务器没有工具）');
      return ToolResult(
        true,
        '共 ${tools.length} 个工具，已列在窗口里',
        view: 'list',
        title: 'MCP · ${s.name}',
        viewData: {
          'items': [
            for (final t in tools)
              {
                'title': '${t['name']}',
                'subtitle': '${t['description'] ?? ''}',
              },
          ],
        },
      );
    } catch (e) {
      return ToolResult(false, '调用失败: $e');
    }
  }
}

class McpCallTool extends AgentTool {
  @override
  String get name => 'mcpCall';
  @override
  String get description => '调用某个 MCP 服务器上的工具。';
  @override
  Map<String, String> get parameters => {'server': '服务器名称', 'tool': '工具名', 'argsJson': '参数 JSON'};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final servers = await McpStore.load();
    final ms = servers.where((e) => e.enabled && e.name == (args['server'] ?? '')).toList();
    if (ms.isEmpty) return ToolResult(false, '未找到服务器 ${args['server']}');
    final s = ms.first;
    Map<String, dynamic> a = {};
    try {
      final raw = args['argsJson'] ?? '{}';
      a = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    try {
      final r = await McpClient.callTool(s, args['tool'] ?? '', a);
      return ToolResult(true, r);
    } catch (e) {
      return ToolResult(false, '调用失败: $e');
    }
  }
}

class ContainerShellTool extends AgentTool {
  final LiveShellSink? sink;
  ContainerShellTool([this.sink]);
  @override
  String get name => 'containerShell';
  @override
  String get description => '在 Alpine(PRoot) 容器里执行命令（apk/git/python 等）。';
  @override
  Map<String, String> get parameters => {'cmd': '命令'};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final cmd = args['cmd'] ?? '';
    if (cmd.isEmpty) return const ToolResult(false, 'cmd 为空');
    // 有 sink 就走流式：对话里能实时看到输出与耗时
    if (sink != null) {
      final tag = 'cs${DateTime.now().microsecondsSinceEpoch}';
      sink!.startLive(cmd);
      final sub = NativeBridge.outputStream.listen((e) {
        if (e['tag'] == tag && e['line'] != null) sink!.pushLive('${e['line']}');
      });
      var code = -1;
      try {
        code = await NativeBridge.streamExec(cmd, tag: tag)
            .timeout(const Duration(seconds: 180), onTimeout: () => -1);
      } catch (_) {
      } finally {
        await sub.cancel();
      }
      sink!.endLive(code);
      return ToolResult(code == 0, '命令结束，exit $code（输出见上方终端卡片）');
    }
    final r = await NativeBridge.prootExec(cmd);
    final out = '${r.stdout}${r.stderr}'.trim();
    return ToolResult(
      r.ok,
      out.isEmpty ? '（无输出，exit ${r.code}）' : out,
      view: 'stream',
      title: '容器 · ${cmd.length > 28 ? '${cmd.substring(0, 28)}…' : cmd}',
      viewData: {
        'lines': terminalLines(cmd, stdout: r.stdout, stderr: r.stderr, code: r.code),
        'running': false,
      },
    );
  }
}

void registerMcpTools(ToolRegistry reg, {LiveShellSink? live}) {
  reg.register(McpListTool());
  reg.register(McpCallTool());
  reg.register(ContainerShellTool(live));
}
