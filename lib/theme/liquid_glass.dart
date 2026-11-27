import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/appearance_store.dart';

/// 液态玻璃外观参数（可在 设置 → 外观 里调）。
class GlassSpec {
  /// 磨砂强度（BackdropFilter sigma）
  final double blur;

  /// 玻璃底色不透明度 0.2 ~ 0.9
  final double tint;

  /// 边缘高光强度 0 ~ 1
  final double edge;

  /// 圆角
  final double radius;

  const GlassSpec({
    this.blur = 22,
    this.tint = 0.14,
    this.edge = 0.9,
    this.radius = 20,
  });

  GlassSpec copyWith({double? blur, double? tint, double? edge, double? radius}) => GlassSpec(
        blur: blur ?? this.blur,
        tint: tint ?? this.tint,
        edge: edge ?? this.edge,
        radius: radius ?? this.radius,
      );
}

class GlassSpecNotifier extends Notifier<GlassSpec> {
  @override
  GlassSpec build() {
    _load();
    return const GlassSpec();
  }

  Future<void> _load() async {
    try {
      final a = await AppearanceStore.load();
      state = GlassSpec(blur: a.glassBlur, tint: a.glassTint, edge: a.glassEdge);
    } catch (_) {}
  }

  Future<void> update(GlassSpec s) async {
    state = s;
    try {
      final a = await AppearanceStore.load();
      await AppearanceStore.save(a.copyWith(
        glassBlur: s.blur,
        glassTint: s.tint,
        glassEdge: s.edge,
      ));
    } catch (_) {}
  }
}

final glassSpecProvider = NotifierProvider<GlassSpecNotifier, GlassSpec>(
  GlassSpecNotifier.new,
);

/// 液态玻璃容器：模糊 + 半透明 + 边缘折射高光 + 内阴影。
class LiquidGlass extends ConsumerWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? radius;
  final Color? tintColor;
  final bool strong;

  const LiquidGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius,
    this.tintColor,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(glassSpecProvider);
    final r = radius ?? spec.radius;
    final br = BorderRadius.circular(r);
    final tint = tintColor ?? Colors.white;
    final alpha = (spec.tint + (strong ? 0.06 : 0)).clamp(0.06, 0.92);
    final e = spec.edge.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: spec.blur, sigmaY: spec.blur),
        child: Stack(
          children: [
            // 玻璃主体
            Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: br,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint.withValues(alpha: alpha + 0.06),
                    tint.withValues(alpha: alpha - 0.04),
                  ],
                ),
                // 边缘那一圈折射高光
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35 + e * 0.45),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEAF0FB).withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                  // 双层边框：外圈细环
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.10 + e * 0.10),
                    spreadRadius: 0.6,
                  ),
                  // 内阴影：制造玻璃厚度
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.30 + e * 0.35),
                    blurRadius: 1,
                    spreadRadius: -0.5,
                    offset: const Offset(0, 1),
                  ),
                  // 边缘色散：极淡的冷暖色晕，模拟折射彩边
                  BoxShadow(
                    color: const Color(0xFF7DD3FC).withValues(alpha: 0.06 * e),
                    blurRadius: 2,
                    spreadRadius: 0.4,
                  ),
                  BoxShadow(
                    color: const Color(0xFFF0A0C8).withValues(alpha: 0.05 * e),
                    blurRadius: 2,
                    spreadRadius: 0.2,
                  ),
                ],
              ),
              child: child,
            ),
            // 顶部弧形高光（只弯边缘）
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: br,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [
                        Colors.white.withValues(alpha: 0.22 + e * 0.20),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 右下角微弱反光
            Positioned(
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(r)),
                    gradient: RadialGradient(
                      center: const Alignment(1, 1),
                      radius: 0.9,
                      colors: [
                        Colors.white.withValues(alpha: 0.10 * e),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 液态玻璃描边（给已有 Container 用，不模糊）。
BoxDecoration liquidBorder(double radius, {double edge = 0.9, Color tint = Colors.white}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.35 + edge * 0.45), width: 1.1),
  );
}
