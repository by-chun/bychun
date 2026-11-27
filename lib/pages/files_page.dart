import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../theme/ref_draggable.dart';
import '../state/chat_refs.dart';
import '../native/native_bridge.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  String _path = '/storage/emulated/0';
  List<(String, bool)> _entries = [];
  bool _loading = true;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _load(_path);
  }

  Future<void> _load(String path) async {
    await NativeBridge.requestStorage();
    setState(() {
      _loading = true;
      _err = '';
      _path = path;
    });
    final r = await NativeBridge.exec("ls -1ap '${path.replaceAll("'", "'\\''")}'");
    final items = <(String, bool)>[];
    if (r.ok) {
      for (final line in r.stdout.split('\n')) {
        final t = line.trim();
        if (t.isEmpty || t == './' || t == '../') continue;
        items.add((t.endsWith('/') ? t.substring(0, t.length - 1) : t, t.endsWith('/')));
      }
      items.sort((a, b) {
        if (a.$2 != b.$2) return a.$2 ? -1 : 1;
        return a.$1.toLowerCase().compareTo(b.$1.toLowerCase());
      });
    }
    if (!mounted) return;
    setState(() {
      _entries = items;
      _loading = false;
      _err = r.ok ? '' : '${r.stderr}'.trim();
    });
  }

  String _parent(String p) {
    if (p == '/' || p.isEmpty) return '/';
    final i = p.lastIndexOf('/');
    return i <= 0 ? '/' : p.substring(0, i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: const Text('文件', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            onPressed: () => _load(_parent(_path)),
            icon: const Icon(Icons.arrow_upward_rounded, size: 20, color: Color(0xFFD4DBE8)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(_path, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: AppColors.muted)),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _entries.isEmpty
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: EmptyState(
                          icon: Icons.folder_off_outlined,
                          text: _err.isEmpty
                              ? '此目录为空'
                              : '读不到目录\n$_err\n\n去 设置 → 工具授权/软件权限 授予“所有文件访问”',
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: _entries.length,
                        itemBuilder: (ctx, i) {
                          final (name, isDir) = _entries[i];
                          return GlassCard(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            onTap: () {
                              if (isDir) _load('$_path/$name');
                            },
                            child: RefDraggable(
                              ref: ChatRef(
                                type: isDir ? 'workspace' : 'file',
                                name: name,
                                detail: '$_path/$name',
                              ),
                              child: Row(children: [
                              Icon(isDir ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                                  size: 18, color: isDir ? AppColors.brand : const Color(0xFF7886A0)),
                              const SizedBox(width: 10),
                              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5))),
                              if (isDir) const Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFCBD5E1)),
                            ]),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
