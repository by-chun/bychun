import '../native/native_bridge.dart';
import 'provider_store.dart';
import 'tool.dart';
import 'tool_registry.dart';

/// 让 AI 安装 APK（root 下 pm install -r）。
class InstallApkTool extends AgentTool {
  @override
  String get name => 'installApk';

  @override
  String get description => '安装 APK 文件（需 root）。path 为 APK 的绝对路径。';

  @override
  Map<String, String> get parameters => {'path': 'APK 绝对路径'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final path = (args['path'] ?? '').trim();
    if (path.isEmpty) return const ToolResult(false, 'path 不能为空');
    if (!path.endsWith('.apk')) return const ToolResult(false, '只支持 .apk 文件');
    final r = await NativeBridge.installApk(path);
    final msg = (r['msg'] ?? '').toString();
    return ToolResult(r['ok'] == true, r['ok'] == true ? '已安装：$path' : '安装失败：$msg');
  }
}

/// 让 AI 帮用户设置「余额查询脚本」（界面上没有入口，AI 仍可配置）。
class SetBalanceScriptTool extends AgentTool {
  @override
  String get name => 'setBalanceScript';

  @override
  String get description =>
      '为某个供应商设置余额查询脚本（在容器里执行的 shell，输出即余额）。不传 provider 则用当前供应商。';

  @override
  Map<String, String> get parameters => {
        'script': 'shell 脚本',
        'provider': '可选：供应商名称，默认当前',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final script = (args['script'] ?? '').trim();
    if (script.isEmpty) return const ToolResult(false, 'script 不能为空');
    final (list, active) = await ProviderStore.loadAllWithActive();
    if (list.isEmpty) return const ToolResult(false, '还没有供应商，先在设置里添加');
    final name = (args['provider'] ?? '').trim();
    final p = ProviderStore.activeOf(list, name.isEmpty ? active : name);
    if (p == null) return ToolResult(false, '找不到供应商 $name');
    p.balanceScript = script;
    await ProviderStore.saveAll(list, active);
    return ToolResult(true, '已为「${p.name}」设置余额脚本');
  }
}


/// 让 AI 设置当前工作区。
class SetWorkspaceTool extends AgentTool {
  @override
  String get name => 'setWorkspace';

  @override
  String get description => '设置当前工作区目录（AI 默认在这个目录里操作文件/执行命令）。';

  @override
  Map<String, String> get parameters => {'path': '目录路径'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final path = (args['path'] ?? '').trim();
    if (path.isEmpty) return const ToolResult(false, 'path 不能为空');
    final r = await NativeBridge.exec('ls -d "$path" >/dev/null 2>&1 && echo OK');
    if (!r.stdout.contains('OK')) {
      return ToolResult(false, '目录不存在或无法访问：$path');
    }
    final dir = await NativeBridge.appDataDir();
    if (dir.isNotEmpty) {
      await NativeBridge.exec('mkdir -p "$dir" && printf %s \'{"path":"$path"}\' > "$dir/workspace.json"');
    }
    return ToolResult(true, '工作区已设为 $path（新会话即生效）');
  }
}

void registerWorkspaceTools(ToolRegistry reg) {
  reg.register(SetWorkspaceTool());
  reg.register(InstallApkTool());
  reg.register(SetBalanceScriptTool());
}
