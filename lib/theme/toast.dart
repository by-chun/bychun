import 'dart:async';
import 'package:flutter/material.dart';
import 'app_theme.dart';

OverlayEntry? _current;

/// 顶部浮出的轻提示（代替 SnackBar）。
void showToast(BuildContext context, String message, {bool error = false}) {
  _current?.remove();
  _current = null;

  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastWidget(message: message, error: error),
  );
  _current = entry;
  overlay.insert(entry);

  Timer(const Duration(seconds: 2), () {
    if (_current == entry) {
      entry.remove();
      _current = null;
    }
  });
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool error;
  const _ToastWidget({required this.message, required this.error});
  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 14;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween(begin: const Offset(0, -0.35), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: widget.error ? const Color(0xFFEF4444) : const Color(0xF20F172A),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Color(0x330F172A), blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(widget.error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(widget.message,
                          style: const TextStyle(fontSize: 12.5, color: Colors.white, height: 1.4)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
