import 'tool.dart';
import 'tool_registry.dart';
import '../native/native_bridge.dart';

/// 配置类 + 搜索联动工具：让 AI 能改配置、把搜索结果推到悬浮窗。

class SearchToOverlayTool extends AgentTool {
  @override
  String get name => 'searchToOverlay';
  @override
  String get description => '在进程内搜索整数并把结果推到悬浮窗显示（需 root + 悬浮窗权限）。';
  @override
  Map<String, String> get parameters => {'pid': '进程 PID', 'value': '整数数值'};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final pid = int.tryParse(args['pid'] ?? '');
    final v = int.tryParse(args['value'] ?? '');
    if (pid == null || v == null) return const ToolResult(false, 'pid/value 需为整数');
    final r = await NativeBridge.memoryScan(pid, v);
    if (r.isEmpty) return const ToolResult(false, '未命中（需 root + libmemory.so）');
    await NativeBridge.overlayResults(r.take(100).map((a) => '0x${a.toRadixString(16)}').toList());
    await NativeBridge.showOverlay();
    return ToolResult(true, '找到 ${r.length} 个地址，已推送到悬浮窗');
  }
}




/// 容器：从 URL 安装任意发行版 rootfs，以及列出已装容器。
class InstallContainerTool extends AgentTool {
  @override
  String get name => 'install_container';
  @override
  String get description =>
      '下载并安装 Linux 容器。给该发行版 arm64 rootfs 的直链（支持 tar.gz / tar.xz）与容器名，装完可在终端里开对应标签。';
  @override
  Map<String, String> get parameters => {
        'url': 'rootfs 直链',
        'name': '容器名（字母数字 . _ -）',
      };
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final url = (args['url'] ?? '').trim();
    final name = (args['name'] ?? '').trim();
    if (url.isEmpty || name.isEmpty) return const ToolResult(false, 'url 和 name 不能为空');
    final r = await NativeBridge.envInstallUrl(url, name);
    final ok = r['ok'] == true;
    return ToolResult(ok, ok ? '已安装容器 $name' : '安装失败：${r['log'] ?? ''}');
  }
}

class ListContainersTool extends AgentTool {
  @override
  String get name => 'list_containers';
  @override
  String get description => '列出已安装的 Linux 容器及其是否可用。';
  @override
  Map<String, String> get parameters => const {};
  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final list = await NativeBridge.envList();
    if (list.isEmpty) return const ToolResult(true, '还没有安装任何容器');
    final cur = await NativeBridge.envCurrent();
    return ToolResult(
      true,
      '共 ${list.length} 个容器，已列在窗口里',
      view: 'list',
      title: '容器',
      viewData: {
        'items': [
          for (final e in list)
            {
              'title': '${e['name']}',
              'subtitle': '${(((e['size'] as num?) ?? 0) / 1024 / 1024).toStringAsFixed(0)}MB · ${e['ready'] == true ? '可用' : '不完整'}',
              'badge': e['name'] == cur ? '当前' : '',
            },
        ],
      },
    );
  }
}

void registerConfigTools(ToolRegistry reg) {
  reg.register(SearchToOverlayTool());
  reg.register(InstallContainerTool());
  reg.register(ListContainersTool());
}
