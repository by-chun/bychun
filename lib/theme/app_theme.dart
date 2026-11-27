import 'dart:io';
import 'dart:ui';
import 'liquid_glass.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:flutter/material.dart';

class AppColors {
  static const brand = Color(0xFF4D7CFE);
  static const brandSoft = Color(0xFF1E2A45);
  static const bg = Color(0xFF0B1020);
  static const card = Color(0xFF141B2E);
  static const text = Color(0xFFEAF0FB);
  static const muted = Color(0xFF9AA7C0);
  static const border = Color(0xFF2A3550);
  static const green = Color(0xFF34D399);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFF87171);
}

BoxDecoration glassDecoration({double radius = 18, bool strong = false}) {
  return BoxDecoration(
    color: Colors.white.withValues(alpha: strong ? 0.16 : 0.10),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
    boxShadow: const [
      BoxShadow(color: Color(0x140F172A), blurRadius: 24, offset: Offset(0, 8)),
    ],
  );
}

/// 壁纸背景：有自定义图就用图，否则用彩色晚霞/极光渐变，让液态玻璃的折射有内容可透。
BoxDecoration glassBackground({String? image}) {
  if (image != null && image.isNotEmpty && File(image).existsSync()) {
    return BoxDecoration(
      image: DecorationImage(image: FileImage(File(image)), fit: BoxFit.cover),
    );
  }
  return const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF101A36),
        Color(0xFF0A0F20),
        Color(0xFF141033),
        Color(0xFF0A1226),
      ],
      stops: [0.0, 0.42, 0.78, 1.0],
    ),
  );
}

/// 白底磨砂玻璃卡片：背后高斯模糊 + 半透明白 + 柔和阴影。
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.radius = 18,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final glass = lg.GlassContainer.card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(14),
        child: child,
      ),
    );
    if (onTap == null && onLongPress == null) return Padding(padding: margin, child: glass);
    return Padding(
      padding: margin,
      child: ScaleOnTap(onTap: onTap, onLongPress: onLongPress, child: glass),
    );
  }
}

/// 按压缩放反馈。
class ScaleOnTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  const ScaleOnTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
  });

  @override
  State<ScaleOnTap> createState() => _ScaleOnTapState();
}

class _ScaleOnTapState extends State<ScaleOnTap> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              setState(() => _pressed = false);
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: Duration(milliseconds: _pressed ? 90 : 220),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// 淡入 + 上移进场动画。
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      offset: _show ? Offset.zero : const Offset(0, 0.06),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 340),
        opacity: _show ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}

