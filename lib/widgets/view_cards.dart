import 'package:flutter/material.dart';
import '../theme/toast.dart';
import 'package:flutter/services.dart';

import '../native/native_bridge.dart';
import '../theme/app_theme.dart';
import 'media_cards.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'json_view.dart';

/// 通用视图渲染器：把工具返回的数据按 view 类型画成卡片。
///
/// 约定（与 AI 工具返回一致）：
/// - list    { items: [ {title, subtitle, badge, action} ] }
/// - detail  { tabs: [ {name, rows: [ {k, v} ]} ] }
/// - stream  { lines: [String], running: bool }
/// - form    { fields: [ {key, label, value} ], submit: String }
/// - confirm { message: String, danger: bool }
class ViewCard extends StatelessWidget {
  final String view;
  final String title;
  final Map<String, dynamic> data;
  /// 表单提交/按钮点击后，把文本当作一条用户消息发回给 AI。
  final void Function(String text)? onAction;
  final bool expandable;
  final bool fullscreen;
  const ViewCard({
    super.key,
    required this.view,
    required this.title,
    required this.data,
    this.onAction,
    this.expandable = true,
    this.fullscreen = false,
  });

  void _openFull(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _CardFullscreen(
        view: view,
        title: title,
        data: data,
        onAction: onAction,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final Widget card = switch (view) {
      'list' => _ListViewCard(title: title, data: data, fullscreen: fullscreen),
      'memsearch' => _MemSearchCard(title: title, data: data, onAction: onAction),
      'detail' => _DetailViewCard(title: title, data: data),
      'stream' => _StreamViewCard(title: title, data: data),
      'form' => _FormViewCard(title: title, data: data, onAction: onAction),
      'confirm' => _ConfirmViewCard(title: title, data: data),
      'choose' => _ChooseSummaryCard(title: title, data: data),
      'json' => _JsonViewCard(title: title, data: data, onAction: onAction),
      'video' => VideoViewCard(title: title, data: data, onAction: onAction),
      'audio' => AudioViewCard(title: title, data: data),
      'reader' => ReaderViewCard(title: title, data: data),
      'comic' => ComicViewCard(title: title, data: data, fullscreen: fullscreen),
      _ => _FallbackCard(title: title, data: data),
    };
    final selfFullscreen = view == 'video' || view == 'audio' || view == 'reader';
    if (!expandable || selfFullscreen) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -8,
          right: 8,
          child: GestureDetector(
            onTap: () => _openFull(context),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE7EDF5)),
                boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 6) ],
              ),
              child: const Icon(Icons.open_in_full_rounded, size: 13, color: Color(0xFF64748B)),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardFullscreen extends StatefulWidget {
  final String view;
  final String title;
  final Map<String, dynamic> data;
  final void Function(String text)? onAction;
  const _CardFullscreen({
    required this.view,
    required this.title,
    required this.data,
    this.onAction,
  });

  @override
  State<_CardFullscreen> createState() => _CardFullscreenState();
}

class _CardFullscreenState extends State<_CardFullscreen> {
  String _orient = 'auto';

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    super.dispose();
  }

  void _setOrient(String mode) {
    setState(() => _orient = mode);
    switch (mode) {
      case 'portrait':
        SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
        break;
      case 'landscape':
        SystemChrome.setPreferredOrientations(
            const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        break;
      default:
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    }
  }

  Widget _orientBtn(String mode, String label) {
    final on = _orient == mode;
    return GestureDetector(
      onTap: () => _setOrient(mode),
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.brand : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: on ? Colors.white : const Color(0xFF64748B))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5FA),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                _orientBtn('auto', '自动'),
                _orientBtn('portrait', '竖'),
                _orientBtn('landscape', '横'),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: ViewCard(
                  view: widget.view,
                  title: widget.title,
                  data: widget.data,
                  onAction: widget.onAction,
                  expandable: false,
                  fullscreen: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _shell({required String title, String? subtitle, IconData? icon, required Widget child}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GlassContainer.card(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 14, color: AppColors.brand),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.text)),
              ),
              if (subtitle != null)
                Text(subtitle,
                    style: const TextStyle(fontSize: 9.5, color: AppColors.muted, fontFamily: 'monospace')),
            ],
          ),
        ),
        child,
        ],
      ),
    ),
  );
}

class _ListViewCard extends StatefulWidget {
  final String title;
  final Map<String, dynamic> data;
  final bool fullscreen;
  const _ListViewCard({required this.title, required this.data, this.fullscreen = false});

  @override
  State<_ListViewCard> createState() => _ListViewCardState();
}

class _ListViewCardState extends State<_ListViewCard> {
  static const _capAfter = 8;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = (widget.data['items'] as List?) ?? const [];
    if (items.isEmpty) {
      return _shell(icon: Icons.list_alt_rounded, title: widget.title, child: const Padding(padding: EdgeInsets.all(14), child: Text('（空）')));
    }
    final capped = items.length > _capAfter;
    final listHeight = widget.fullscreen
        ? MediaQuery.of(context).size.height * 0.62
        : 340.0;
    final tiles = [for (final raw in items) _tile(raw as Map)];
    final content = capped
        ? SizedBox(
            height: listHeight,
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.zero,
                children: tiles,
              ),
            ),
          )
        : Column(children: tiles);
    return _shell(
      icon: Icons.list_alt_rounded,
      title: widget.title,
      subtitle: '${items.length} 项',
      child: Column(
        children: [
          content,
          if (capped)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFFFBFCFE),
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Text('共 ${items.length} 项 · 卡片内滚动查看',
                  style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
            ),
        ],
      ),
    );
  }

  Widget _tile(Map it) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${it['title'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
                if (it['subtitle'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('${it['subtitle']}',
                        style: const TextStyle(
                            fontSize: 9.5, fontFamily: 'monospace', color: AppColors.muted)),
                  ),
              ],
            ),
          ),
          if (it['badge'] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text('${it['badge']}',
                  style: const TextStyle(fontSize: 8.5, color: AppColors.brand)),
            ),
        ],
      ),
    );
  }
}

class _MemSearchCard extends StatefulWidget {
  final String title;
  final Map<String, dynamic> data;
  final void Function(String text)? onAction;
  const _MemSearchCard({required this.title, required this.data, this.onAction});

  @override
  State<_MemSearchCard> createState() => _MemSearchCardState();
}

class _MemSearchCardState extends State<_MemSearchCard> {
  static const _types = [
    ['A', '自动', 'auto'],
    ['B', 'Byte', 'i8'],
    ['W', 'Word', 'i16'],
    ['D', 'Dword', 'i32'],
    ['Q', 'Qword', 'i64'],
    ['F', 'Float', 'f32'],
    ['E', 'Double', 'f64'],
    ['H', 'Hex', 'bytes'],
  ];

  late final TextEditingController _pid =
      TextEditingController(text: '${widget.data['pid'] ?? ''}');
  final _value = TextEditingController();
  String _tag = 'D';
  String _err = '';

  @override
  void dispose() {
    _pid.dispose();
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final pid = _pid.text.trim();
    final v = _value.text.trim();
    if (pid.isEmpty || v.isEmpty) {
      setState(() => _err = 'PID 和搜索值都要填');
      return;
    }
    setState(() => _err = '');
    final t = _types.firstWhere((e) => e[0] == _tag);
    final text = t[2] == 'bytes'
        ? '内存搜索：pid $pid，类型 H（bytes），字节序列 $v'
        : '内存搜索：pid $pid，类型 $_tag（${t[2]}），值 $v';
    widget.onAction?.call(text);
  }

  Widget _field(TextEditingController c, String hint, {int flex = 1, bool digits = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        alignment: Alignment.center,
        child: TextField(
          controller: c,
          keyboardType: digits ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF9AA4B2)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F7)),
        boxShadow: const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 22, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.memory_rounded, size: 16, color: AppColors.brand),
            const SizedBox(width: 7),
            Text(widget.title,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.text)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _field(_pid, 'PID', digits: true),
            const SizedBox(width: 8),
            _field(_value, '搜索值', flex: 2),
          ]),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in _types)
                GestureDetector(
                  onTap: () => setState(() => _tag = t[0]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: _tag == t[0] ? AppColors.brand : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: _tag == t[0] ? AppColors.brand : const Color(0xFFEDF2F8)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(t[0],
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: _tag == t[0] ? Colors.white : const Color(0xFF475569))),
                      const SizedBox(width: 4),
                      Text(t[1],
                          style: TextStyle(
                              fontSize: 8.5,
                              color: _tag == t[0] ? Colors.white : const Color(0xFF94A3B8))),
                    ]),
                  ),
                ),
            ],
          ),
          if (_err.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(_err, style: const TextStyle(fontSize: 10, color: AppColors.red)),
            ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _submit,
            child: Container(
              height: 36,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(11)),
              child: const Text('搜索',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailViewCard extends StatefulWidget {
  final String title;
  final Map<String, dynamic> data;
  const _DetailViewCard({required this.title, required this.data});
  @override
  State<_DetailViewCard> createState() => _DetailViewCardState();
}

class _DetailViewCardState extends State<_DetailViewCard> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = (widget.data['tabs'] as List?) ?? const [];
    if (tabs.isEmpty) return _shell(icon: Icons.article_outlined, title: widget.title, child: const SizedBox.shrink());
    final cur = tabs[_tab.clamp(0, tabs.length - 1)] as Map;
    final rows = (cur['rows'] as List?) ?? const [];
    return _shell(
      icon: Icons.article_outlined,
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _tab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: i == _tab ? AppColors.brand : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text('${(tabs[i] as Map)['name'] ?? ''}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: i == _tab ? FontWeight.w700 : FontWeight.w400,
                            color: i == _tab ? AppColors.brand : AppColors.muted,
                          )),
                    ),
                  ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 84,
                            child: Text('${(r as Map)['k'] ?? ''}',
                                style: const TextStyle(
                                    fontSize: 9.5,
                                    fontFamily: 'monospace',
                                    color: AppColors.muted)),
                          ),
                          Expanded(
                            child: Text('${r['v'] ?? ''}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    height: 1.5,
                                    color: AppColors.text)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamViewCard extends StatefulWidget {
  final String title;
  final Map<String, dynamic> data;
  const _StreamViewCard({required this.title, required this.data});
  @override
  State<_StreamViewCard> createState() => _StreamViewCardState();
}

class _StreamViewCardState extends State<_StreamViewCard> {
  final _ctrl = ScrollController();
  bool _open = true;

  @override
  void initState() {
    super.initState();
    _open = widget.data['running'] == true;
  }

  @override
  void didUpdateWidget(covariant _StreamViewCard oldWidget) {
    if (widget.data['running'] == true && !_open) {
      _open = true;
    }
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ctrl.hasClients && _open) _ctrl.jumpTo(_ctrl.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = ((widget.data['lines'] as List?) ?? const []).map((e) => '$e').toList();
    final running = widget.data['running'] == true;
    final elapsed = (widget.data['elapsed'] as num?)?.toInt() ?? 0;
    final dur = elapsed >= 60
        ? '${elapsed ~/ 60}m${(elapsed % 60).toString().padLeft(2, '0')}s'
        : '${elapsed}s';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F7)),
        boxShadow: const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 22, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 12, 11),
              child: Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: running ? AppColors.brand : const Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.text)),
                ),
                if (lines.isNotEmpty)
                  Text('${lines.length} 行',
                      style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8), fontFamily: 'monospace')),
                const SizedBox(width: 6),
                Text(running ? '运行中 · $dur' : '完成 · $dur',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: running ? AppColors.brand : const Color(0xFF94A3B8),
                    )),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: const Icon(Icons.expand_more_rounded, size: 16, color: Color(0xFFCBD5E1)),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E293B),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(children: [
                        for (final c in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)])
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                          ),
                        const Spacer(),
                        const Text('输出',
                            style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: Scrollbar(
                        controller: _ctrl,
                        child: ListView(
                          controller: _ctrl,
                          shrinkWrap: true,
                          children: [
                            for (final l in lines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(l,
                                    style: const TextStyle(
                                        fontSize: 10, fontFamily: 'monospace', color: Color(0xFFCBD5E1), height: 1.7)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
                      ),
                      Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 11),
              child: Row(children: [
                _miniBtn('复制', Icons.copy_rounded, () async {
                  await Clipboard.setData(ClipboardData(text: lines.join('\n')));
                  if (context.mounted) showToast(context, '已复制输出');
                }),
                const SizedBox(width: 8),
                _miniBtn('打开终端', Icons.open_in_new_rounded, () => NativeBridge.openTerminal()),
                const Spacer(),
                if (running)
                  const Text('AI 正在执行…',
                      style: TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8))),
              ]),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: const Color(0xFF475569)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569))),
        ]),
      ),
    );
  }
}

class _FormViewCard extends StatefulWidget {
  final String title;
  final Map<String, dynamic> data;
  final void Function(String)? onAction;
  const _FormViewCard({required this.title, required this.data, this.onAction});

  @override
  State<_FormViewCard> createState() => _FormViewCardState();
}

class _FormViewCardState extends State<_FormViewCard> {
  final Map<String, TextEditingController> _c = {};

  @override
  void initState() {
    super.initState();
    for (final f in (widget.data['fields'] as List?) ?? const []) {
      final m = f as Map;
      final k = '${m['key'] ?? ''}';
      _c[k] = TextEditingController(text: '${m['value'] ?? ''}');
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final fields = (widget.data['fields'] as List?) ?? const [];
    final submit = (widget.data['submit'] ?? '提交').toString();
    final lines = <String>[submit];
    for (final f in fields) {
      final m = f as Map;
      final k = '${m['key'] ?? ''}';
      final label = '${m['label'] ?? k}';
      lines.add('$label: ${_c[k]?.text.trim() ?? ''}');
    }
    widget.onAction?.call(lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final fields = (widget.data['fields'] as List?) ?? const [];
    final submit = widget.data['submit'];
    return _shell(
      icon: Icons.edit_note_rounded,
      title: widget.title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${(f as Map)['label'] ?? ''}',
                        style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
                    const SizedBox(height: 3),
                    TextField(
                      controller: _c['${f['key'] ?? ''}'],
                      style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: AppColors.text),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (submit != null)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                  child: Text('${submit}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmViewCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  const _ConfirmViewCard({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    final danger = data['danger'] == true;
    return _shell(
      icon: Icons.shield_outlined,
      title: title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(danger ? Icons.error_outline_rounded : Icons.shield_outlined,
                size: 16, color: danger ? const Color(0xFFF59E0B) : AppColors.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${data['message'] ?? ''}',
                  style: const TextStyle(fontSize: 10.5, height: 1.6, color: AppColors.text)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChooseSummaryCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  const _ChooseSummaryCard({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    final n = ((data['options'] as List?) ?? const []).length;
    final multi = data['multi'] == true;
    return _shell(
      icon: Icons.tune_rounded,
      title: title,
      subtitle: multi ? '多选 · $n 项' : '单选 · $n 项',
      child: const Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(children: [
          Icon(Icons.ads_click_rounded, size: 14, color: Color(0xFF94A3B8)),
          SizedBox(width: 6),
          Expanded(
            child: Text('已弹出选择窗口，选完会作为消息回传',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
          ),
        ]),
      ),
    );
  }
}

class _JsonViewCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  final void Function(String text)? onAction;
  const _JsonViewCard({required this.title, required this.data, this.onAction});

  @override
  Widget build(BuildContext context) {
    return _shell(
      icon: Icons.widgets_rounded,
      title: title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: JsonView(data['json'], onAction: (action, args) {
          final text = args.isEmpty
              ? action
              : '$action: ${args.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
          onAction?.call(text);
        }),
      ),
    );
  }
}

class _FallbackCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  const _FallbackCard({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    return _shell(
      icon: Icons.info_outline_rounded,
      title: title,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(data.toString(),
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.muted)),
      ),
    );
  }
}
