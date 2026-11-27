import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';
import '../theme/glass_kit.dart';
import '../theme/toast.dart';
import '../state/drawer_ctrl.dart';
import '../state/theme_controller.dart';
import '../agent/appearance_store.dart';
import '../native/native_bridge.dart';
import '../state/chat_refs.dart';
import '../state/active_session.dart';
import '../state/agent_controller.dart';
import '../state/ui_state.dart';
import '../data/db_provider.dart';
import '../data/app_db.dart';
import '../widgets/app_icon.dart';
import '../pages/plugins_page.dart';
import '../pages/settings_page.dart';
import '../pages/personas_page.dart';
import '../pages/group_members_page.dart';
import '../pages/container_page.dart';
import '../pages/compact_page.dart';
import '../pages/backup_page.dart';
import '../pages/mcp_page.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// 抽屉里的树状工作区：应用 / 文件 / 插件 / 设置，逐级向下展开。
class TreeDrawer extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  const TreeDrawer({super.key, this.onClose});

  @override
  ConsumerState<TreeDrawer> createState() => _TreeDrawerState();
}

class _TreeDrawerState extends ConsumerState<TreeDrawer> {
  final Set<String> _open = {};
  String _q = '';
  List<Map<String, dynamic>>? _apps;
  final Map<String, List<(String, bool)>> _dirs = {};
  double _dragDist = 0;
  bool _dragClosed = false;
  double _dragP = 0;

  @override
  void initState() {
    super.initState();
    DrawerCtrl.openNode.addListener(_onOpenNode);
    // 恢复上次展开的节点，重启后抽屉不会全部折回去
    UiStateStore.drawerOpen().then((list) {
      if (!mounted || list.isEmpty) return;
      setState(() => _open.addAll(list));
    });
  }

  @override
  void dispose() {
    DrawerCtrl.openNode.removeListener(_onOpenNode);
    super.dispose();
  }

  void _onOpenNode() {
    final k = DrawerCtrl.openNode.value;
    if (k == null || !mounted) return;
    setState(() {
      _open.add('settings');
      _open.add(k);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => DrawerCtrl.openNode.value = null);
  }

  void _setDragProgress(double d) {
    _dragDist = d;
    final p = (d / 140).clamp(0.0, 1.0);
    if ((p - _dragP).abs() > 0.01 && mounted) setState(() => _dragP = p);
  }

  bool _isOpen(String k) => _open.contains(k);

  void _toggle(String k) async {
    setState(() {
      if (_open.contains(k)) {
        _open.remove(k);
      } else {
        _open.add(k);
      }
    });
    UiStateStore.saveDrawerOpen(_open);
    if (_open.contains(k)) await _ensure(k);
  }

  Future<void> _ensure(String key) async {
    if (key == 'apps' && _apps == null) {
      final l = await NativeBridge.listApps();
      if (mounted) setState(() => _apps = l);
    }
  }

  Future<List<(String, bool)>> _ls(String path) async {
    if (_dirs.containsKey(path)) return _dirs[path]!;
    await NativeBridge.requestStorage();
    final r = await NativeBridge.exec("ls -1ap '${path.replaceAll("'", "'\\''")}'");
    final items = <(String, bool)>[];
    if (r.ok) {
      for (final line in r.stdout.split('\n')) {
        final t = line.trim();
        if (t.isEmpty || t == './' || t == '../') continue;
        items.add((t.endsWith('/') ? t.substring(0, t.length - 1) : t, t.endsWith('/')));
      }
    }
    items.sort((a, b) {
      if (a.$2 != b.$2) return a.$2 ? -1 : 1;
      return a.$1.toLowerCase().compareTo(b.$1.toLowerCase());
    });
    _dirs[path] = items;
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      // 往外拖时抽屉跟着变淡 + 位移，拖出去一点就关
      opacity: 1 - _dragP * 0.55,
      duration: Duration(milliseconds: _dragP == 0 ? 160 : 0),
      child: Transform.translate(
        offset: Offset(-_dragP * 48, 0),
        child: Container(
          decoration: glassBackground(image: ref.watch(appearanceProvider).value?.path),
          child: SafeArea(
            // 整张抽屉可向左拖关闭（不只是单个条目）
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) {
                _dragDist = 0;
                _dragClosed = false;
              },
              onHorizontalDragUpdate: (d) {
                if (widget.onClose == null || _dragClosed) return;
                _dragDist += d.delta.dx.abs();
                _setDragProgress(_dragDist);
                if (_dragDist > 70) {
                  _dragClosed = true;
                  widget.onClose!.call();
                  if (mounted) setState(() => _dragP = 0);
                }
              },
              onHorizontalDragEnd: (_) {
                if (mounted) setState(() => _dragP = 0);
              },
              onHorizontalDragCancel: () {
                if (mounted) setState(() => _dragP = 0);
              },
              child: _treeBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _treeBody() {
    return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Row(
                children: [
                  const Text('Rowan',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
                  const Spacer(),
                  if (widget.onClose != null)
                    InkWell(
                      onTap: widget.onClose,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded, size: 18, color: Color(0xFF7886A0)),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                children: [
                  // 每组一个稳定 Key（相当于 view-transition-name）：
                  // 同组内切换 = 180ms 滑动；跨组切换 = 只淡入淡出，不做长距离位移。
                  KeyedSubtree(
                    key: const ValueKey('group:sessions'),
                    child: _card([
                      _section('sessions', '会话', _typeIcon(Icons.forum_outlined, AppColors.brand)),
                      _groupBody('sessions', _sessionChildren()),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  KeyedSubtree(
                    key: const ValueKey('group:apps'),
                    child: Column(children: [
                      _card([_section('apps', '应用', _typeIcon(Icons.grid_view_rounded, AppColors.brand))]),
                      ..._appChildren(),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  KeyedSubtree(
                    key: const ValueKey('group:files'),
                    child: _card([
                      _section('files', '文件', _typeIcon(Icons.folder_outlined, AppColors.muted)),
                      _groupBody('files', Column(children: [
                        _searchAdd('files', onAdd: () => _newSheet('/storage/emulated/0')),
                        _dirChildren('files', '/storage/emulated/0', 1),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  KeyedSubtree(
                    key: const ValueKey('group:plugins'),
                    child: _card([
                      _section('plugins', '插件', _typeIcon(Icons.extension_outlined, AppColors.muted)),
                      _groupBody('plugins', Column(children: [
                        _searchAdd('plugins', onAdd: () => _newSheet('/storage/emulated/0/Rowan/plugins')),
                        _dirChildren('plugins', '/storage/emulated/0/Rowan/plugins', 1),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  KeyedSubtree(
                    key: const ValueKey('group:settings'),
                    child: _card(_settingRows()),
                  ),
                ],
              ),
            ),
          ],
        );
  }

  /// 分组展开区：收起时高度归零 + 淡出；展开时高度撑开 + 淡入。
  /// 同组内条目切换由子组件自身的 AnimatedSlide 处理（180ms），
  /// 这里不做任何位移动画，所以不会跨组长距离滑动。
  Widget _groupBody(String key, Widget child) {
    final open = _isOpen(key);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        // 用 key 区分开/关两态：只做淡入淡出，不做位移
        child: open
            ? KeyedSubtree(key: ValueKey('$key:open'), child: child)
            : const SizedBox.shrink(key: ValueKey('closed')),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return LiquidPanel(
      radius: 15,
      margin: const EdgeInsets.only(bottom: 9),
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }

  Widget _typeIcon(IconData ic, Color color) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(ic, size: 15, color: AppColors.text),
      );

  Widget _section(String key, String title, Widget icon) {
    final open = _isOpen(key);
    final row = InkWell(
      onTap: () => _toggle(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 10,
              child: Icon(open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                  size: 14, color: AppColors.muted),
            ),
            const SizedBox(width: 6),
            icon,
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
            const Spacer(),
            if (key == 'apps' && _apps != null)
              Text('${_apps!.length}',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted, fontFamily: 'monospace')),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
    return row;
  }

  /// ＋ 号：新建文件夹 / 新建文件（自由命名）/ 导入 / 安装内置插件。
  Future<void> _newSheet(String dir) async {
    await NativeBridge.exec("mkdir -p '$dir'");
    final isPluginDir = dir.contains('/G/plugins');
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141B2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('新建', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined, size: 20, color: AppColors.brand),
            title: const Text('新建文件夹', style: TextStyle(fontSize: 13.5)),
            onTap: () => Navigator.pop(ctx, 'dir'),
          ),
          ListTile(
            leading: const Icon(Icons.note_add_outlined, size: 20, color: AppColors.brand),
            title: const Text('新建文件', style: TextStyle(fontSize: 13.5)),
            subtitle: const Text('自己写文件名和后缀，不限格式', style: TextStyle(fontSize: 10.5)),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined, size: 20, color: AppColors.brand),
            title: const Text('从本地导入', style: TextStyle(fontSize: 13.5)),
            subtitle: const Text('任意文件都行', style: TextStyle(fontSize: 10.5)),
            onTap: () => Navigator.pop(ctx, 'import'),
          ),
          if (isPluginDir)
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined, size: 20, color: AppColors.brand),
              title: const Text('安装内置插件', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text('请求模板、示例脚本', style: TextStyle(fontSize: 10.5)),
              onTap: () => Navigator.pop(ctx, 'seed'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (act == null) return;
    if (act == 'seed') {
      await NativeBridge.exec(
        "cd '$dir' && printf '%s\\n' '{\"method\":\"POST\",\"url\":\"https://example.com/api\"}' > '请求模板.json' "
        "&& printf '%s\\n' '#!/bin/sh' 'echo hello from plugin' > '示例.sh' && chmod 755 '示例.sh'",
      );
      _dirs.clear();
      if (mounted) setState(() {});
      return;
    }
    if (act == 'import') {
      // 选一个文本文件，写入当前目录（名字可改）
      final content = await NativeBridge.pickTextFile();
      if (content == null || content.isEmpty || !mounted) return;
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF141B2E),
          title: const Text('导入文件名', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('存到 $dir',
                style: const TextStyle(fontSize: 10, color: Color(0xFF7886A0), fontFamily: 'monospace')),
            const SizedBox(height: 8),
            TextField(controller: c, autofocus: true),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('导入')),
          ],
        ),
      );
      final name = c.text.trim();
      c.dispose();
      if (ok != true || name.isEmpty) return;
      final safeName = name.replaceAll("'", "'\\''");
      final safeBody = content.replaceAll("'", "'\\''");
      await NativeBridge.exec("printf '%s' '$safeBody' > '$dir/$safeName'");
      _dirs.clear();
      if (mounted) setState(() {});
      return;
    }
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141B2E),
        title: Text(act == 'dir' ? '新建文件夹' : '新建文件',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('在 $dir 下创建',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF7886A0), fontFamily: 'monospace')),
          const SizedBox(height: 8),
          TextField(controller: c, autofocus: true),
          if (act == 'file')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('后缀随意：.sh .py .js .json .yaml .cmd .conf …',
                  style: TextStyle(fontSize: 9.5, color: Color(0xFFB6C0CD))),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    final name = c.text.trim();
    c.dispose();
    if (ok != true || name.isEmpty) return;
    final target = '$dir/${name.replaceAll("'", "'\\''")}';
    if (act == 'dir') {
      await NativeBridge.exec("mkdir -p '$target'");
    } else {
      await NativeBridge.exec("touch '$target'");
    }
    _dirs.remove(dir);
    // 新建文件后直接在树里展开编辑区，方便写代码
    if (act == 'file' && mounted) {
      setState(() => _open.add('fs:$target'));
      return;
    }
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    showToast(context, msg);
  }

  Widget _searchAdd(String key, {VoidCallback? onAdd}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF141B2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1A2338)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 13, color: Color(0xFF7886A0)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _q = v),
                      style: const TextStyle(fontSize: 11.5),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '搜索',
                        hintStyle: TextStyle(fontSize: 11.5, color: Color(0xFF7886A0)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onAdd != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                child: const Icon(Icons.add_rounded, size: 17, color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------- 会话 ----------------
  Widget _sessionChildren() {
    final db = ref.read(appDbProvider);
    final active = ref.watch(activeSessionProvider);
    return StreamBuilder<List<Session>>(
      stream: db.watchSessions(),
      builder: (context, snap) {
        final list = snap.data ?? const <Session>[];
        // 会话分类：单会话 / 群聊 各一组，互不混在一起
        final singles = list.where((s) => s.kind != 'group').toList();
        final groups = list.where((s) => s.kind == 'group').toList();
        // 组内切换会话：列表做 180ms 轻微滑动（active 作 key，切换时触发）
        return AnimatedSlide(
          key: ValueKey('session-list-$active'),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          offset: Offset.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _groupLabel('群聊'),
              if (groups.isEmpty) _emptyHint('（还没有群聊）'),
              for (final s in groups.take(30)) _sessionTile(db, s, active, isGroup: true),
              Padding(
                padding: const EdgeInsets.fromLTRB(34, 2, 10, 8),
                child: Row(children: [
                  InkWell(
                    onTap: () => _newGroup(db),
                    child: Text('＋ 新群聊', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
                  ),
                ]),
              ),
              _groupLabel('单会话'),
              if (singles.isEmpty) _emptyHint('（还没有会话）'),
              for (final s in singles.take(30)) _sessionTile(db, s, active, isGroup: false),
              Padding(
                padding: const EdgeInsets.fromLTRB(34, 2, 10, 8),
                child: Row(children: [
                  InkWell(
                    onTap: () {
                      ref.read(agentEngineProvider).newConversation();
                      ref.read(activeSessionProvider.notifier).reset();
                      widget.onClose?.call();
                    },
                    child: Text('＋ 新对话', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _clearSessions,
                    child: const Text('全部删除', style: TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _groupLabel(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(34, 8, 10, 4),
        child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.muted)),
      );

  Widget _emptyHint(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(34, 4, 10, 6),
        child: Text(t, style: const TextStyle(fontSize: 10.5, color: Color(0xFF7886A0))),
      );

  /// 会话条目：带选中高亮、左滑删除；群聊条目带一个小标记。
  Widget _sessionTile(AppDb db, Session s, int? active, {required bool isGroup}) {
    return Dismissible(
      key: ValueKey('session-${s.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: const Color(0xFF2A1A1A),
        child: const Text('删除', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
      ),
      onDismissed: (_) async {
        await db.deleteSession(s.id);
        if (ref.read(activeSessionProvider) == s.id) {
          ref.read(agentEngineProvider).newConversation();
          ref.read(activeSessionProvider.notifier).reset();
        }
      },
      child: _DrawerRow(
        active: s.id == active,
        onTap: () {
          ref.read(activeSessionProvider.notifier).open(s.id);
          widget.onClose?.call();
        },
        icon: isGroup ? Icons.groups_rounded : (s.id == active ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded),
        label: s.title.isEmpty ? (isGroup ? '新群聊' : '新对话') : s.title,
      ),
    );
  }

  /// 新建群聊：建会话、打开、关抽屉。
  Future<void> _newGroup(AppDb db) async {
    final engine = ref.read(agentEngineProvider);
    final id = await engine.newGroup(db, '新群聊');
    ref.read(activeSessionProvider.notifier).open(id);
    widget.onClose?.call();
  }

  Future<void> _clearSessions() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141B2E),
        title: const Text('删除全部会话？', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text('所有对话记录会被删除，无法恢复。', style: TextStyle(fontSize: 12, height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(appDbProvider);
    final list = await db.watchSessions().first;
    for (final s in list) {
      await db.deleteSession(s.id);
    }
    ref.read(activeSessionProvider.notifier).reset();
    ref.read(agentEngineProvider).newConversation();
    _toast('已删除全部会话');
  }

  // ---------------- 应用 ----------------
  List<Widget> _appChildren() {
    if (!_isOpen('apps')) return const [];
    final apps = _apps;
    if (apps == null) {
      return const [
        Padding(padding: EdgeInsets.all(14), child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))),
      ];
    }
    final q = _q.toLowerCase();
    final userApps = apps.where((a) => a['system'] != true).toList();
    final list = q.isEmpty
        ? userApps
        : userApps.where((a) {
            final l = (a['label'] ?? '').toString().toLowerCase();
            final p = (a['package'] ?? '').toString().toLowerCase();
            return l.contains(q) || p.contains(q);
          }).toList();
    return [
      _searchAdd('apps'),
      ...list.take(80).map(_appRow),
    ];
  }

  Widget _appRow(Map<String, dynamic> a) {
    final label = (a['label'] ?? '?').toString();
    final pkg = (a['package'] ?? '').toString();
    final key = 'app:$pkg';
    final open = _isOpen(key);
    return _draggableRow(
      ref: ChatRef(type: 'app', name: label, detail: pkg),
      onTap: () => _toggle(key),
      onLongPress: () => _rowMenu(
        title: label,
        onRename: null,
        onDelete: null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 10,
                child: Icon(open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                    size: 14, color: const Color(0xFFC3CCD8)),
              ),
              const SizedBox(width: 6),
              AppIcon(app: a, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
              ),
              const Icon(Icons.drag_handle_rounded, size: 14, color: Color(0xFF2A3550)),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(42, 4, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kvLine('APK', _size((a['size'] as num?)?.toInt() ?? 0)),
                        _kvLine('路径', (a['apk'] ?? '—').toString()),
                        _kvLine('类型', a['system'] == true ? '系统应用' : '用户应用'),
                        _apkFiles((a['apk'] ?? '').toString(), pkg),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  Widget _kvLine(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 34, child: Text(k, style: const TextStyle(fontSize: 9.5, color: Color(0xFFB6C0CD)))),
            Expanded(
              child: Text(v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF9AA7C0), fontFamily: 'monospace')),
            ),
          ],
        ),
      );

  // ---------------- APK 内部文件树 ----------------
  /// apk 路径 → 父目录 → 该层条目（{name, path, dir}）
  final Map<String, Map<String, List<Map<String, dynamic>>>> _zipIndex = {};

  Future<void> _loadZip(String apk) async {
    if (_zipIndex.containsKey(apk)) return;
    final list = await NativeBridge.zipList(apk);
    final idx = <String, List<Map<String, dynamic>>>{};
    for (final e in list) {
      final raw = (e['name'] ?? '').toString();
      final isDir = e['dir'] == true || raw.endsWith('/');
      final clean = isDir ? raw.replaceAll(RegExp(r'/+$'), '') : raw;
      if (clean.isEmpty) continue;
      final i = clean.lastIndexOf('/');
      final parent = i < 0 ? '' : clean.substring(0, i);
      idx.putIfAbsent(parent, () => []).add({
        'name': i < 0 ? clean : clean.substring(i + 1),
        'path': clean,
        'dir': isDir,
      });
    }
    for (final l in idx.values) {
      l.sort((a, b) {
        if (a['dir'] != b['dir']) return a['dir'] == true ? -1 : 1;
        return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
      });
    }
    if (mounted) setState(() => _zipIndex[apk] = idx);
  }

  Widget _apkFiles(String apk, String pkg) {
    if (apk.isEmpty) return const SizedBox(width: double.infinity);
    final rootKey = 'ziproot:$pkg';
    final open = _isOpen(rootKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            if (!_zipIndex.containsKey(apk)) _loadZip(apk);
            _toggle(rootKey);
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(children: [
              Icon(open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                  size: 13, color: const Color(0xFFC3CCD8)),
              const SizedBox(width: 6),
              const Icon(Icons.folder_zip_outlined, size: 14, color: Color(0xFF9AA7C0)),
              const SizedBox(width: 6),
              const Text('APK', style: TextStyle(fontSize: 11, color: Color(0xFFD4DBE8))),
            ]),
          ),
        ),
        if (open)
          Container(
            height: 240,
            margin: const EdgeInsets.only(top: 2, bottom: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF141B2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1A2338)),
            ),
            child: !_zipIndex.containsKey(apk)
                ? const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                : (_zipIndex[apk]!.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: Text('（读不到 APK 内容）', style: TextStyle(fontSize: 10.5, color: Color(0xFF7886A0))),
                      )
                    : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: _zipLevel(apk, ''))),
          ),
      ],
    );
  }

  List<Widget> _zipLevel(String apk, String dir) {
    final items = _zipIndex[apk]?[dir] ?? const <Map<String, dynamic>>[];
    return [for (final it in items) _zipRow(apk, it)];
  }

  Widget _zipRow(String apk, Map<String, dynamic> it) {
    final isDir = it['dir'] == true;
    final path = it['path'] as String;
    final name = it['name'] as String;
    final key = 'zip:$apk:$path';
    final open = _isOpen(key);
    final row = InkWell(
      onTap: isDir ? () => _toggle(key) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        child: Row(children: [
          Icon(
            isDir
                ? (open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded)
                : Icons.insert_drive_file_outlined,
            size: 12,
            color: isDir ? const Color(0xFF7886A0) : const Color(0xFFCBD5E1),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: isDir ? const Color(0xFFD4DBE8) : const Color(0xFF9AA7C0))),
          ),
        ]),
      ),
    );
    if (!isDir) {
      // APK 里的文件也能长按拖进对话当引用
      return _draggableRow(
        ref: ChatRef(type: 'file', name: name, detail: '$apk!/$path'),
        child: row,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        if (open) Padding(padding: const EdgeInsets.only(left: 9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _zipLevel(apk, path))),
      ],
    );
  }

  // ---------------- 目录（文件 / 插件） ----------------
  Widget _dirChildren(String rootKey, String path, int depth) {
    return FutureBuilder<List<(String, bool)>>(
      future: _ls(path),
      builder: (context, snap) {
        final items = snap.data;
        if (items == null) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final q = _q.toLowerCase();
        final list = q.isEmpty ? items : items.where((e) => e.$1.toLowerCase().contains(q)).toList();
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(34, 6, 10, 12),
            child: Text('（空）', style: TextStyle(fontSize: 10.5, color: Color(0xFF7886A0))),
          );
        }
        return Column(children: [
          for (final e in list.take(depth == 1 ? 40 : 60)) _fsRow(rootKey, path, e.$1, e.$2, depth),
        ]);
      },
    );
  }

  Widget _fsRow(String rootKey, String parent, String name, bool isDir, int depth) {
    final full = '$parent/$name';
    final key = 'fs:$full';
    final open = _isOpen(key);
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return Column(
      children: [
        Dismissible(
          key: ValueKey('fs:$full'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF2A1A1A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('删除',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
          ),
          confirmDismiss: (_) async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF141B2E),
                title: Text(isDir ? '删除「$name」文件夹？' : '删除「$name」？',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                content: Text(isDir ? '里面的文件会一起删掉，无法恢复。' : '文件将被删除，无法恢复。',
                    style: const TextStyle(fontSize: 12, height: 1.6)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('删除'),
                  ),
                ],
              ),
            );
            return ok == true;
          },
          onDismissed: (_) async {
            await NativeBridge.exec("rm -rf '${full.replaceAll("'", "'\\''")}'");
            _dirs.clear();
            if (mounted) setState(() {});
          },
          child: _draggableRow(
            ref: ChatRef(type: 'file', name: name, detail: full),
            onTap: () => _toggle(key),
            onLongPress: () => _rowMenu(
              title: name,
              onRename: () => _rename(full),
              onDelete: () => _delete(full),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 10,
                  child: Icon(open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                      size: 14, color: const Color(0xFFC3CCD8)),
                ),
                const SizedBox(width: 6),
                Icon(
                  isDir ? Icons.folder_outlined : Icons.description_outlined,
                  size: 17,
                  color: isDir ? const Color(0xFF9AA7C0) : const Color(0xFF7886A0),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: isDir ? 12.5 : 12,
                          fontFamily: isDir ? null : 'monospace',
                          fontWeight: isDir ? FontWeight.w600 : FontWeight.w500)),
                ),
                if (ext == 'sh' || ext == 'py' || ext == 'js' || ext == 'json' || ext == 'yaml')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFF12251C), borderRadius: BorderRadius.circular(3)),
                    child: Text(ext, style: const TextStyle(fontSize: 8, color: Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.drag_handle_rounded, size: 14, color: Color(0xFF2A3550)),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? (isDir
                  ? Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: _dirChildren(rootKey, full, depth + 1),
                    )
                  : Container(
                      height: 420,
                      margin: const EdgeInsets.fromLTRB(16, 2, 8, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1A2338)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: PluginViewPage(path: full, name: name, embedded: true),
                      ),
                    ))
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  Widget _draggableRow({
    required ChatRef ref,
    required Widget child,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return LongPressDraggable<ChatRef>(
      data: ref,
      delay: const Duration(milliseconds: 220),
      onDragStarted: () {
        _dragDist = 0;
        _dragClosed = false;
        if (_dragP != 0 && mounted) setState(() => _dragP = 0);
      },
      onDragUpdate: (d) {
        // 拖离抽屉一定距离就关闭抽屉，手指能接着拖到输入区
        if (_dragClosed || widget.onClose == null) return;
        _setDragProgress(_dragDist + d.delta.distance);
        if (_dragDist > 70) {
          _dragClosed = true;
          widget.onClose!.call();
          if (mounted) setState(() => _dragP = 0);
        }
      },
      onDraggableCanceled: (_, __) {
        if (mounted) setState(() => _dragP = 0);
      },
      onDragCompleted: () {
        if (mounted) setState(() => _dragP = 0);
      },
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(10)),
          child: Text(ref.name, style: const TextStyle(color: Colors.white, fontSize: 11.5)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: child),
      ),
    );
  }

  Future<void> _rowMenu({
    required String title,
    VoidCallback? onRename,
    VoidCallback? onDelete,
  }) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141B2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(children: [
              Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7886A0), fontFamily: 'monospace'))),
            ]),
          ),
          if (onRename != null)
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
              title: const Text('重命名', style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
          ListTile(
            leading: const Icon(Icons.arrow_outward_rounded, size: 20),
            title: const Text('发到对话', style: TextStyle(fontSize: 13.5)),
            onTap: () => Navigator.pop(ctx, 'chat'),
          ),
          if (onDelete != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFDC2626)),
              title: const Text('删除', style: TextStyle(fontSize: 13.5, color: Color(0xFFDC2626))),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
        ]),
      ),
    );
    if (act == 'rename') onRename?.call();
    if (act == 'delete') onDelete?.call();
  }

  Future<void> _rename(String full) async {
    final name = full.split('/').last;
    final c = TextEditingController(text: name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141B2E),
        title: const Text('重命名', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    final newName = c.text.trim();
    c.dispose();
    if (ok != true || newName.isEmpty || newName == name) return;
    final dir = full.substring(0, full.lastIndexOf('/'));
    await NativeBridge.exec("mv '${full.replaceAll("'", "'\\''")}' '${dir.replaceAll("'", "'\\''")}/$newName'");
    _dirs.remove(dir);
    if (mounted) setState(() {});
  }

  Future<void> _delete(String full) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141B2E),
        title: const Text('删除', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(full, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await NativeBridge.exec("rm -rf '${full.replaceAll("'", "'\\''")}'");
    _dirs.clear();
    if (mounted) setState(() {});
  }

  // ---------------- 设置 ----------------
  /// 抽屉里的「设置」：一张卡片行，点开弹底部玻璃抽屉（原型：设置从下往上）。
  List<Widget> _settingRows() {
    return [
      _card([
        InkWell(
          onTap: () => _openSettingsSheet(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
            child: Row(children: [
              _typeIcon(Icons.settings_outlined, AppColors.brand),
              const SizedBox(width: 9),
              const Expanded(
                child: Text('设置', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
            ]),
          ),
        ),
      ]),
    ];
  }

  /// 设置项：图标 + 标题 + 副标题，对应一个 embedded 页面。
  static const _settingsEntries = <(IconData, String, String, String)>[
    (Icons.memory_outlined, 'AI 供应商', '模型 / Key / 地址', 'provider'),
    (Icons.person_outline_rounded, '人物', '角色设定', 'persona'),
    (Icons.groups_outlined, '子代理', '多角色协作', 'subagent'),
    (Icons.diversity_3_outlined, '群成员', '群聊里各模型各干各的', 'members'),
    (Icons.description_outlined, '提示词', '内置规则', 'prompt'),
    (Icons.inventory_2_outlined, '容器', 'PRoot 环境', 'container'),
    (Icons.shield_outlined, '权限', 'root / 悬浮窗 / VPN', 'perm'),
    (Icons.hub_outlined, 'MCP 服务器', '外部工具接入', 'mcp'),
    (Icons.compress_outlined, '上下文压缩', '超出时自动压缩', 'compact'),
    (Icons.settings_backup_restore_outlined, '备份与恢复', '导出 / 导入配置', 'backup'),
  ];

  Widget _settingsPage(String key) {
    switch (key) {
      case 'provider': return const ProvidersPage(embedded: true);
      case 'persona': return const PersonasPage(embedded: true);
      case 'subagent': return const SkillsSubPage(embedded: true);
      case 'members': return const GroupMembersPage(embedded: true);
      case 'prompt': return const PromptPage(embedded: true);
      case 'container': return const ContainerPage(embedded: true);
      case 'perm': return const PowerPage(embedded: true);
      case 'mcp': return const McpPage(embedded: true);
      case 'compact': return const CompactPage(embedded: true);
      case 'backup': return const BackupPage(embedded: true);
    }
    return const SizedBox.shrink();
  }

  /// 7 套主题色板 + 自定义背景图按钮（原型：主题行）。用 Consumer 取 ref，放进 sheet 也能用。
  Widget _themeRow() {
    return Consumer(
      builder: (context, ref, _) {
        final cur = ref.watch(themeColorProvider);
        return Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          child: Row(
            children: [
              const Text('主题', style: TextStyle(fontSize: 12.5, color: AppColors.text)),
              const SizedBox(width: 10),
              for (var i = 0; i < rowanThemes.length; i++)
                GestureDetector(
                  onTap: () => ref.read(themeColorProvider.notifier).set(i),
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(right: 7),
                    decoration: BoxDecoration(
                      gradient: rowanThemes[i].gradient,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: cur.accent == rowanThemes[i].accent ? Colors.white : AppColors.border,
                        width: cur.accent == rowanThemes[i].accent ? 2 : 1.5,
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () async {
                  final x = await ImagePicker().pickImage(source: ImageSource.gallery);
                  if (x == null) return;
                  await ref.read(appearanceProvider.notifier).setImage(x.path);
                },
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A2338),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_photo_alternate_outlined, size: 13, color: AppColors.muted),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 底部玻璃设置抽屉：主题色板 + 设置项列表；点项进入二级页。
  void _openSettingsSheet() {
    widget.onClose?.call();
    showGlassSheet<void>(
      context,
      title: '设置',
      maxHeight: 0.86,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _themeRow(),
          for (final e in _settingsEntries)
            GlassOptionRow(
              icon: e.$1,
              title: e.$2,
              subtitle: e.$3,
              onTap: () => _openSettingDetail(e.$4, e.$2),
            ),
        ],
      ),
    );
  }

  /// 设置二级页：同样是底部玻璃抽屉，带返回。
  void _openSettingDetail(String key, String title) {
    Navigator.of(context).pop();
    showGlassSheet<void>(
      context,
      title: title,
      maxHeight: 0.90,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LiquidPanel(
          radius: 14,
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          child: _settingsPage(key),
        ),
      ),
    );
  }

  static String _size(int b) {
    if (b >= 1024 * 1024 * 1024) return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)}GB';
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(0)}MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)}KB';
    return '${b}B';
  }
}

/// 抽屉里的一行（原型 .drow）：选中时浅底 + 左侧 3px 渐变竖条，200ms 过渡。
class _DrawerRow extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  const _DrawerRow({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
    this.padding = const EdgeInsets.fromLTRB(34, 9, 12, 9),
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        color: active ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
        padding: padding,
        child: Stack(children: [
          if (active)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [accent, Color.lerp(accent, const Color(0xFF8A6BFF), 0.5)!],
                  ),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                ),
              ),
            ),
          Row(children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(icon,
                  key: ValueKey('$icon-$active'), size: 13, color: active ? accent : AppColors.muted),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? accent : AppColors.text,
                ),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (trailing != null) trailing!,
          ]),
        ]),
      ),
    );
  }
}
