import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 液态玻璃面板的通用外观（与网页原型 .glass / .sheet 一致）：
/// 低透明白底 + 深色边框 + 内高光 + 外阴影。
class LiquidPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool strong;

  const LiquidPanel({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding,
    this.margin,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final a = strong ? 0.16 : 0.10;
    return Container(
      margin: margin,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: a + 0.04), Colors.white.withValues(alpha: a - 0.04)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8)),
          BoxShadow(color: Color(0x14FFFFFF), blurRadius: 0, spreadRadius: 0.5),
        ],
      ),
      child: child,
    );
  }
}

/// 玻璃图标按钮（原型 .btn）：36×36、圆角 12。
class GlassSquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  const GlassSquareButton({super.key, required this.icon, this.onTap, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return ScaleOnTap(
      onTap: onTap,
      pressedScale: 0.9,
      child: LiquidPanel(
        radius: 12,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.46, color: AppColors.text),
        ),
      ),
    );
  }
}

/// 玻璃主按钮（原型 .btn2.primary）：主题色渐变。
class GlassPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  const GlassPrimaryButton({super.key, required this.label, this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ScaleOnTap(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent, Color.lerp(accent, const Color(0xFF8A6BFF), 0.5)!],
          ),
          borderRadius: BorderRadius.circular(13),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: Colors.white), const SizedBox(width: 6)],
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
    );
  }
}

/// 玻璃次按钮（原型 .btn2.ghost）。
class GlassGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  const GlassGhostButton({super.key, required this.label, this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return ScaleOnTap(
      onTap: onTap,
      pressedScale: 0.97,
      child: LiquidPanel(
        radius: 13,
        padding: EdgeInsets.zero,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: AppColors.text), const SizedBox(width: 6)],
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
          ]),
        ),
      ),
    );
  }
}

/// 设置行（原型 .optrow）：图标 + 标题 + 副标题 + 右侧箭头。
class GlassOptionRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  const GlassOptionRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.margin = const EdgeInsets.only(bottom: 9),
  });

  @override
  Widget build(BuildContext context) {
    return ScaleOnTap(
      onTap: onTap,
      pressedScale: 0.98,
      child: LiquidPanel(
        radius: 15,
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          if (icon != null) ...[
            LiquidPanel(
              radius: 10,
              padding: EdgeInsets.zero,
              child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 16, color: AppColors.text)),
            ),
            const SizedBox(width: 11),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
              if (subtitle != null)
                Text(subtitle!, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ]),
          ),
          trailing ?? const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
        ]),
      ),
    );
  }
}

/// iOS 风格玻璃开关（原型 .sw）。
class GlassSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const GlassSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => onChanged?.call(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        width: 46,
        height: 26,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: value ? null : Colors.white.withValues(alpha: 0.16),
          gradient: value
              ? LinearGradient(colors: [accent, Color.lerp(accent, const Color(0xFF8A6BFF), 0.5)!])
              : null,
          border: Border.all(color: AppColors.border),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x4D000000), blurRadius: 3, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}

/// 带开关的设置行（原型 .rowsw）。
class GlassSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const GlassSwitchRow({super.key, required this.title, this.subtitle, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LiquidPanel(
      radius: 14,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          ]),
        ),
        GlassSwitch(value: value, onChanged: onChanged),
      ]),
    );
  }
}

/// 玻璃输入框（原型 .ff / .ta）。
class GlassField extends StatelessWidget {
  final String? hint;
  final String? label;
  final TextEditingController? controller;
  final bool obscure;
  final int maxLines;
  const GlassField({
    super.key,
    this.hint,
    this.label,
    this.controller,
    this.obscure = false,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.10),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: maxLines > 1 ? 10 : 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
      ),
    );
    if (label == null) return field;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label!, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      const SizedBox(height: 4),
      field,
    ]);
  }
}

/// 底部玻璃抽屉的壳（原型 .sheet）：顶部把手 + 标题 + 内容。
/// 用法：showGlassSheet(context, title: '标题', body: [...])
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required String title,
  required Widget body,
  double maxHeight = 0.82,
  /// 为 true 时按 maxHeight 固定高度；为 false 时随内容自适应（内容少的面板用）。
  bool fixedHeight = true,
}) {
  Widget sheet = ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.06)],
              ),
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                  child: body,
                ),
              ),
            ]),
          ),
        ),
      );
  if (fixedHeight) {
    sheet = FractionallySizedBox(heightFactor: maxHeight, child: sheet);
  }
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    isScrollControlled: true,
    builder: (ctx) => SafeArea(top: false, child: sheet),
  );
}

/// 居中玻璃弹窗（原型 .dialog）：标题 + 说明 + 两个按钮。
Future<bool> showGlassConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool danger = false,
}) async {
  final accent = Theme.of(context).colorScheme.primary;
  final r = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: LiquidPanel(
          radius: 20,
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.6)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: GlassGhostButton(
                  label: cancelLabel,
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ScaleOnTap(
                  onTap: () => Navigator.of(ctx).pop(true),
                  pressedScale: 0.97,
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: danger
                          ? const LinearGradient(colors: [Color(0xFFF87171), Color(0xFFDC2626)])
                          : LinearGradient(colors: [accent, Color.lerp(accent, const Color(0xFF8A6BFF), 0.5)!]),
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: (danger ? const Color(0xFFDC2626) : accent).withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(confirmLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
  return r ?? false;
}

/// 三格卡片（原型 .grid3 .cell）：添加内容弹窗用。
class GlassGridCell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback? onTap;
  const GlassGridCell({super.key, required this.icon, required this.title, required this.desc, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ScaleOnTap(
      onTap: onTap,
      pressedScale: 0.95,
      child: LiquidPanel(
        radius: 15,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        child: Column(children: [
          LiquidPanel(
            radius: 12,
            padding: EdgeInsets.zero,
            child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 18, color: AppColors.text)),
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 3),
          Text(desc, style: const TextStyle(fontSize: 9, color: AppColors.muted)),
        ]),
      ),
    );
  }
}
