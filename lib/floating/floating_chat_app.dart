import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/json_view.dart';

const MethodChannel floatingChannel = MethodChannel('com.chun.by/floating');

/// 灵动岛胶囊 + 对话小窗（跑在第二个 Flutter 引擎里）。
class FloatingChatApp extends StatefulWidget {
  const FloatingChatApp({super.key});
  @override
  State<FloatingChatApp> createState() => _FloatingChatAppState();
}

class _FloatingChatAppState extends State<FloatingChatApp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _spring;
  bool _expanded = false;
  String _state = 'AI 待命';
  final List<Map<String, dynamic>> _msgs = [];
  dynamic _view;
  final TextEditingController _input = TextEditingController();
  bool _pillDragged = false;
  Offset _dragAcc = Offset.zero;
  DateTime _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // 从 0.9 放到 1.0，避免 scale 从 0 起跳导致小窗口里布局撑爆
    _spring = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    floatingChannel.setMethodCallHandler(_onCall);
  }

  @override
  void dispose() {
    _input.dispose();
    _ctrl.dispose();
    floatingChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'state':
        if (mounted) setState(() => _state = (call.arguments['text'] ?? _state).toString());
        break;
      case 'push':
        if (mounted) {
          setState(() => _msgs.add({
                'role': call.arguments['role'] ?? 'assistant',
                'text': call.arguments['text'] ?? '',
              }));
        }
        break;
      case 'view':
        if (mounted) setState(() => _view = call.arguments['json']);
        break;
    }
    return null;
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    floatingChannel.invokeMethod(_expanded ? 'expand' : 'collapse');
    if (_expanded) _ctrl.forward(); else _ctrl.reverse();
  }

  void _send() {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    // 本地先显示，再发给主引擎
    setState(() => _msgs.add({'role': 'user', 'text': t}));
    floatingChannel.invokeMethod('send', {'text': t});
    _input.clear();
  }

  void _attach() {
    floatingChannel.invokeMethod('attach');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _expanded ? _window() : _pill(),
    );
  }

  /// 液态玻璃：白磨砂 + 双层亮边 + 内高光。
  BoxDecoration _glass(double radius) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xF2141B2E), Color(0xE60B1020)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0xFF2A3550)),
      boxShadow: const [
        BoxShadow(color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 6)),
        BoxShadow(color: Color(0x1FFFFFFF), blurRadius: 0, spreadRadius: 0.5),
      ],
    );
  }

  // ---------- 胶囊 ----------
  /// 灵动岛胶囊：可拖动；没怎么动就松手 = 点击展开。
  Widget _pill() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        _pillDragged = false;
        _dragAcc = Offset.zero;
        _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);
      },
      onPanUpdate: (d) {
        if (d.delta.distance > 0.5) _pillDragged = true;
        _dragAcc += d.delta;
        // 节流：每 ~50ms 把累计位移刷给原生一次，既跟手又不抖
        final now = DateTime.now();
        if (now.difference(_lastFlush).inMilliseconds >= 50) {
          _lastFlush = now;
          floatingChannel.invokeMethod('move', {'dx': _dragAcc.dx, 'dy': _dragAcc.dy});
          _dragAcc = Offset.zero;
        }
      },
      onPanEnd: (_) {
        if (!_pillDragged) {
          _toggle();
        } else if (_dragAcc != Offset.zero) {
          floatingChannel.invokeMethod('move', {'dx': _dragAcc.dx, 'dy': _dragAcc.dy});
          _dragAcc = Offset.zero;
        }
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: _glass(20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(),
            const SizedBox(width: 8),
            Flexible(
              child: Text(_state,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD4DBE8))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot() => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          gradient: const RadialGradient(
            colors: [Colors.white, Color(0xFFFF3B30)],
            stops: [0.0, 0.6],
          ),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: const Color(0xFFFF3B30).withValues(alpha: .8), blurRadius: 8, spreadRadius: 1)],
        ),
      );

  // ---------- 小窗 ----------
  Widget _window() {
    return ScaleTransition(
      scale: _spring,
      child: FadeTransition(
        opacity: _ctrl,
        child: Container(
          decoration: _glass(18),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
                children: [
                  _header(),
                  Expanded(child: _body()),
                  _inputBar(),
                ],
              ),
              Positioned(right: 2, bottom: 2, child: _resizeHandle()),
            ],
          ),
        ),
      ),
    );
  }

  /// 右下角缩放把手：拖动时把每帧增量发给原生 resize。
  Widget _resizeHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        floatingChannel.invokeMethod('resize', {'dw': d.delta.dx, 'dh': d.delta.dy});
      },
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        child: Icon(Icons.open_in_full, size: 13, color: AppColors.muted.withValues(alpha: 0.7)),
      ),
    );
  }

  Widget _header() {
    Offset start = Offset.zero;
    return GestureDetector(
      onPanStart: (d) => start = d.globalPosition,
      onPanUpdate: (d) {
        final dx = d.globalPosition.dx - start.dx;
        final dy = d.globalPosition.dy - start.dy;
        floatingChannel.invokeMethod('move', {'dx': dx, 'dy': dy});
        start = d.globalPosition;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x1FFFFFFF))),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text('Rowan',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
            // 缩回胶囊
            GestureDetector(
              onTap: _toggle,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close, size: 15, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    // reverse：新消息在底部自动可见，不用手动滚
    return ListView(
      reverse: true,
      padding: const EdgeInsets.all(11),
      children: [
        if (_view != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: JsonView(_view, onAction: (a, args) {
              floatingChannel.invokeMethod('action', {'action': a, 'args': args});
            }),
          ),
        for (final m in _msgs.reversed) _bubble(m),
      ],
    );
  }

  Widget _bubble(Map m) {
    final mine = m['role'] == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF4D7CFE) : Colors.white.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
          border: mine ? null : Border.all(color: const Color(0xFF2A3550)),
        ),
        child: Text('${m['text']}',
            style: TextStyle(fontSize: 12, height: 1.5, color: mine ? Colors.white : AppColors.text)),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 18, 18),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1FFFFFFF)))),
      child: Row(
        children: [
          // 上传文件
          GestureDetector(
            onTap: _attach,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2A3550)),
              ),
              child: const Icon(Icons.attach_file, size: 15, color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _input,
              style: const TextStyle(fontSize: 11.5, color: AppColors.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: '给 AI 发消息…',
                hintStyle: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .10),
                contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: const Color(0xFF2A3550)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: const Color(0xFF2A3550)),
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _send,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF4D7CFE), Color(0xFF8A6BFF)]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x4D2563EB), blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: const Text('发送', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
