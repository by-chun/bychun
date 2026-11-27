import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../native/native_bridge.dart';
import 'settings_page.dart' show embedShell;

/// 容器管理：APK 不内置任何镜像，容器全部通过 URL 下载或本地导入。
class ContainerPage extends StatefulWidget {
  final bool embedded;
  const ContainerPage({super.key, this.embedded = false});
  @override
  State<ContainerPage> createState() => _ContainerPageState();
}

class _ContainerPageState extends State<ContainerPage> {
  List<Map<String, dynamic>> _envs = [];
  String _current = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final envs = await NativeBridge.envList();
    final cur = await NativeBridge.envCurrent();
    if (!mounted) return;
    setState(() {
      _envs = envs;
      _current = cur;
    });
  }

  String _size(dynamic bytes) {
    final b = (bytes as num?)?.toDouble() ?? 0;
    if (b >= 1024 * 1024 * 1024) return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)}GB';
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(0)}MB';
    return '${(b / 1024).toStringAsFixed(0)}KB';
  }

  Future<void> _installFromUrl() async {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('从 URL 安装容器'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: 'rootfs 直链'),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '容器名'),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            const Text(
              '下载后自动解压到应用私有目录，同名容器会被覆盖。',
              style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('安装')),
        ],
      ),
    );
    if (ok != true) return;
    final url = urlCtrl.text.trim();
    final name = nameCtrl.text.trim();
    if (url.isEmpty || name.isEmpty) return;
    setState(() => _busy = true);
    final r = await NativeBridge.envInstallUrl(url, name);
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    _showResult(r);
  }

  Future<void> _import() async {
    final pathCtrl = TextEditingController(text: '/sdcard/Download/');
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('导入 rootfs'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pathCtrl,
              decoration: const InputDecoration(labelText: 'tar / tar.gz / tar.xz 路径'),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '容器名'),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;
    if (nameCtrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final r = await NativeBridge.envImport(pathCtrl.text.trim(), nameCtrl.text.trim());
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    _showResult(r);
  }

  Future<void> _remove(String env) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('删除 $env'),
        content: const Text('会删掉该容器的所有文件，里面的数据不会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (go != true) return;
    await NativeBridge.envRemove(env);
    await _load();
  }

  void _showResult(Map<String, dynamic> r) {
    final ok = r['ok'] == true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(ok ? '完成' : '失败'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: Text(
              '${r['log'] ?? ''}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.5),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('好'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_envs.isEmpty)
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('还没有容器', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      SizedBox(height: 6),
                      Text(
                        'APK 不内置镜像。终端本身不装容器也能用（系统 shell），需要 apk/apt 时再装一个发行版。',
                        style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              for (final e in _envs) _envCard(e),
              const SizedBox(height: 18),
              GlassCard(
                onTap: _installFromUrl,
                child: Row(
                  children: const [
                    Icon(Icons.cloud_download_outlined, size: 18, color: AppColors.brand),
                    SizedBox(width: 10),
                    Expanded(child: Text('从 URL 安装容器', style: TextStyle(fontSize: 13))),
                    Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              GlassCard(
                onTap: _import,
                child: Row(
                  children: const [
                    Icon(Icons.file_upload_outlined, size: 18, color: AppColors.brand),
                    SizedBox(width: 10),
                    Expanded(child: Text('从本地文件导入', style: TextStyle(fontSize: 13))),
                    Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '支持 tar / tar.gz / tar.xz（按文件头自动识别）。需要什么发行版就贴哪个的 arm64 rootfs 直链。',
                style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.6),
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFF141B2E), borderRadius: BorderRadius.circular(16)),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                        SizedBox(height: 12),
                        Text('处理中…', style: TextStyle(fontSize: 12)),
                        Text('下载、安装可能需要一会儿', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    if (widget.embedded) {
      return embedShell(title: '容器', body: body);
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('容器', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: body,
    );
  }

  Widget _envCard(Map<String, dynamic> e) {
    final name = '${e['name']}';
    final ready = e['ready'] == true;
    final isCurrent = name == _current;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: ready
          ? () async {
              await NativeBridge.envSet(name);
              await _load();
            }
          : null,
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 18,
            color: ready ? AppColors.brand : const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    if (isCurrent) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brandSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('当前', style: TextStyle(fontSize: 9.5, color: AppColors.brand)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  ready ? _size(e['size']) : '未完成，建议删除后重装',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Switch(
            value: isCurrent,
            activeColor: AppColors.brand,
            onChanged: ready
                ? (v) async {
                    if (!v) return; // 必须保留一个默认环境
                    await NativeBridge.envSet(name);
                    await _load();
                  }
                : null,
          ),
          IconButton(
            onPressed: () => _remove(name),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: const Color(0xFF7886A0),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
