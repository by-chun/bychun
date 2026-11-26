import 'dart:convert';

import 'tool.dart';
import 'tool_registry.dart';
import '../native/native_bridge.dart';

/// 跑容器里的 JS 插件，返回 JSON 组件树给 App 渲染。
/// 插件往 stdout 输出 JSON（可先打日志，取最后一行合法 JSON）。
class PluginViewTool extends AgentTool {
  @override
  String get name => 'pluginView';

  @override
  String get description =>
      '跑容器里的 JS 插件（nodejs），插件往 stdout 输出 JSON 组件树'
      '（stack/text/metric/list/keyValue/table/actions/options/confirm/progress/callout/chart），'
      'App 渲染成原生界面。arg 会作为参数传给插件（如点按后的 action）。需先 apk add nodejs。';

  @override
  Map<String, String> get parameters => {
        'path': '插件 .js 路径（容器内，如 /root/panel.js）',
        'arg': '可选参数，传给插件（JSON 字符串）',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final path = (args['path'] ?? '').trim();
    if (path.isEmpty) return const ToolResult(false, 'path 不能为空');
    final arg = (args['arg'] ?? '').trim();
    final cmd = arg.isEmpty ? 'node "$path"' : 'node "$path" ${_shellQuote(arg)}';
    final r = await NativeBridge.prootExec(cmd);
    if (!r.ok || r.stdout.trim().isEmpty) {
      return ToolResult(false, '插件运行失败：${r.stderr.isNotEmpty ? r.stderr : r.stdout}');
    }
    dynamic json;
    for (final line in r.stdout.split('\n').reversed) {
      final t = line.trim();
      if (t.isEmpty) continue;
      try {
        json = jsonDecode(t);
        break;
      } catch (_) {}
    }
    if (json == null) {
      return ToolResult(false, '插件输出不是 JSON：${r.stdout.trim().substring(0, r.stdout.trim().length.clamp(0, 300))}');
    }
    return ToolResult(true, '已渲染插件界面', view: 'json', viewData: {'json': json});
  }

  static String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";
}

void registerPluginTools(ToolRegistry reg) {
  reg.register(PluginViewTool());
}
