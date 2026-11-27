import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 小号玻璃按钮（白磨砂、细边、蓝字/蓝图标）。
class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const GlassButton({super.key, required this.label, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ScaleOnTap(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
              boxShadow: const [BoxShadow(color: Color(0x120F172A), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: AppColors.brand),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brand)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形玻璃图标按钮。
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  const GlassIconButton({super.key, required this.icon, this.onTap, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return ScaleOnTap(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Icon(icon, size: size * 0.5, color: const Color(0xFFD4DBE8)),
      ),
    );
  }
}

/// 空状态。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.brand.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, size: 32, color: AppColors.brand),
            ),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFFD4DBE8), height: 1.7, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
