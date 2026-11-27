import 'package:flutter/material.dart';
import '../theme/toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/xposed_store.dart';
import '../native/native_bridge.dart';
import '../state/chat_refs.dart';
import '../theme/app_theme.dart';
import 'settings_page.dart' show embedShell;

/// 文件详情：按扩展名决定能做什么。全部在展开区里操作，不弹页。
class PluginViewPage extends ConsumerStatefulWidget {
  final String path;
  final String name;
  final bool embedded;
  const PluginViewPage({super.key, required this.path, required this.name, this.embedded = false});

  @override
  ConsumerState<PluginViewPage> createState() => _PluginViewPageState();
}

class _PluginViewPageState extends ConsumerState<PluginViewPage> {
  String? _content;
  bool _loading = true;

  String? _out;
  bool _editing = false;
  final _editCtrl = TextEditingController();

  bool _xposed = false;
  List<String> _xpTargets = const [];
  bool _xpPicking = false;
  String _xpQ = '';
  final Set<String> _xpSel = {};
  List<Map<String, dynamic>>? _apps;

  String get _ext {
    final n = widget.name;
    final i = n.lastIndexOf('.');
    return i < 0 ? '' : n.substring(i + 1).toLowerCase();
  }

  String? get _interp => switch (_ext) {
        'sh' || 'bash' => 'sh',
        'py' => 'python3',
        'js' => 'node',
        'lua' => 'lua',
        _ => null,
      };

  bool get _runnable => _interp != null;

  String get _q => widget.path;

  @override
  void initState() {
    super.initState();
    _load();
    _loadXp();
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await NativeBridge.exec("head -c 200000 '${_q.replaceAll("'", "'\\''")}'");
    if (!mounted) return;
    setState(() {
      _content = r.ok ? r.stdout : (r.stderr.isEmpty ? '（无法读取）' : r.stderr);
      _loading = false;
    });
  }

  Future<void> _loadXp() async {
    final list = await XposedStore.load();
    final hit = list.where((s) => s.name == widget.name).toList();
    if (!mounted) return;
    setState(() {
      _xposed = hit.isNotEmpty;
      _xpTargets = hit.isEmpty ? const [] : hit.first.targets;
    });
  }

  Future<void> _run() async {
    final interp = _interp;
    if (interp == null) return;
    setState(() => _out = '运行中…');
    final r = await NativeBridge.exec("$interp '${_q.replaceAll("'", "'\\''")}'", timeout: 60);
    if (!mounted) return;
    final text = '${r.stdout}${r.stderr}'.trim();
    setState(() => _out = '[exit ${r.code}]\n${text.isEmpty ? '（无输出）' : text}');
  }

  void _startEdit() {
    _editCtrl.text = _content ?? '';
    setState(() {
      _editing = true;
      _xpPicking = false;
    });
  }

  Future<void> _saveEdit() async {
    final text = _editCtrl.text;
    await NativeBridge.exec("cat > '${_q.replaceAll("'", "'\\''")}' << 'GEOF'\n$text\nGEOF");
    if (!mounted) return;
    setState(() => _editing = false);
    await _load();
  }

  Future<void> _startXp() async {
    if (_xposed) {
      await _removeXposed();
      return;
    }
    final apps = _apps ?? await NativeBridge.listApps();
    if (!mounted) return;
    if (apps.isEmpty) {
      setState(() => _out = '读不到应用列表（需存储权限）');
      return;
    }
    setState(() {
      _apps = apps;
      _xpPicking = true;
      _editing = false;
      _xpQ = '';
      _xpSel
        ..clear()
        ..addAll(_xpTargets);
    });
  }

  Future<void> _confirmXp() async {
    if (_xpSel.isEmpty) {
      setState(() => _out = '先勾选目标应用');
      return;
    }
    final list = await XposedStore.load();
    final item = XposedScript(name: widget.name, targets: _xpSel.toList(), code: _content ?? '');
    final i = list.indexWhere((s) => s.name == widget.name);
    if (i >= 0) {
      list[i] = item;
    } else {
      list.add(item);
    }
    await XposedStore.save(list);
    await _loadXp();
    if (!mounted) return;
    setState(() {
      _xpPicking = false;
      _out = '已登记为 Xposed 模块，重启目标应用生效';
    });
  }

  Future<void> _removeXposed() async {
    final list = await XposedStore.load();
    list.removeWhere((s) => s.name == widget.name);
    await XposedStore.save(list);
    await _loadXp();
    if (!mounted) return;
    setState(() => _out = '已取消 Xposed 模块');
  }

  void _sendToChat() {
    ref.read(chatRefsProvider.notifier).add(ChatRef(
          type: 'file',
          name: widget.name,
          detail: widget.path,
        ));
    if (!widget.embedded) Navigator.of(context).pop();
    showToast(context, '已发到对话');
  }

  Widget _chip(String label, IconData icon, bool on, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF2563EB) : const Color(0xFF1A2338),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: on ? Colors.white : const Color(0xFFAEB9CC)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 11, color: on ? Colors.white : const Color(0xFFAEB9CC))),
          ]),
        ),
      ),
    );
  }

  Widget get _preview => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFF0B1220), borderRadius: BorderRadius.circular(10)),
        child: Text(
          _content ?? '',
          style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Color(0xFFCBD5E1), height: 1.7),
        ),
      );

  Widget get _xpList {
    final all = _apps ?? const <Map<String, dynamic>>[];
    final q = _xpQ.toLowerCase();
    final apps = all.where((a) {
      if (a['system'] == true) return false;
      if (q.isEmpty) return true;
      final l = (a['label'] ?? '').toString().toLowerCase();
      final p = (a['package'] ?? '').toString().toLowerCase();
      return l.contains(q) || p.contains(q);
    }).toList();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141B2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1A2338)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 2),
          child: Row(children: [
            const Text('勾选目标应用', style: TextStyle(fontSize: 11, color: AppColors.muted)),
            const Spacer(),
            TextButton(
              onPressed: _confirmXp,
              child: Text('确定 ${_xpSel.length}', style: const TextStyle(fontSize: 11.5)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            onChanged: (v) => setState(() => _xpQ = v),
            style: const TextStyle(fontSize: 11.5),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 16),
              hintText: '搜索应用名 / 包名',
              hintStyle: TextStyle(fontSize: 11.5),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: apps.length,
            itemBuilder: (_, i) {
              final a = apps[i];
              final pkg = (a['package'] ?? '').toString();
              final on = _xpSel.contains(pkg);
              return InkWell(
                onTap: () => setState(() {
                  if (on) {
                    _xpSel.remove(pkg);
                  } else {
                    _xpSel.add(pkg);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(children: [
                    Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined,
                        size: 15, color: on ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text((a['label'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5)),
                    ),
                    Text(pkg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: Color(0xFF7886A0), fontFamily: 'monospace')),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final panel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
          child: Row(children: [
            Expanded(
              child: Text(widget.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: AppColors.muted, fontFamily: 'monospace')),
            ),
            InkWell(
              onTap: _sendToChat,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.arrow_outward_rounded, size: 15, color: Color(0xFF2563EB)),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            if (_runnable) _chip('运行', Icons.play_arrow_rounded, false, _run),
            _chip(_editing ? '编辑中' : '编辑', Icons.edit_outlined, _editing, _editing ? null : _startEdit),
            _chip('复制', Icons.copy_rounded, false, () {
              Clipboard.setData(ClipboardData(text: _content ?? ''));
              showToast(context, '已复制');
            }),
            if (_ext == 'js')
              _chip(_xposed ? '已作为 XP 模块' : '设为 XP 模块', Icons.extension_outlined, _xpPicking,
                  _startXp),
          ]),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: _xpPicking
                      ? _xpList
                      : _editing
                          ? Column(children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141B2E),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF1A2338)),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: TextField(
                                    controller: _editCtrl,
                                    maxLines: null,
                                    expands: true,
                                    textAlignVertical: TextAlignVertical.top,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.5),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => setState(() => _editing = false),
                                    child: const Text('取消', style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _saveEdit,
                                    child: const Text('保存', style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ]),
                            ])
                          : ListView(children: [
                              _preview,
                              if (_out != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B1220),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(_out!,
                                      style: const TextStyle(
                                          fontSize: 10, fontFamily: 'monospace', color: Color(0xFF7DD3FC), height: 1.6)),
                                ),
                              ],
                              if (_xposed) ...[
                                const SizedBox(height: 8),
                                Text('已作用于：${_xpTargets.join(', ')}',
                                    style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                              ],
                            ]),
                ),
        ),
      ],
    );
    if (widget.embedded) return panel;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
      ),
      body: panel,
    );
  }
}
