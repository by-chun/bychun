import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 统一的玻璃弹窗：圆角 24、顶部指示条、标题、内容、按钮行。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  String cancelText = '取消',
  String confirmText = '确定',
  bool destructive = false,
  bool showCancel = true,
  String? deleteText,
  T? confirmValue,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: const Color(0x660F172A),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white),
              boxShadow: const [BoxShadow(color: Color(0x1F0F172A), blurRadius: 30, offset: Offset(0, 12))],
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Stack(children: [
                    Center(
                      child: Text(title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.text)),
                    ),
                    if (deleteText != null)
                      Positioned(
                        right: 0,
                        top: -2,
                        child: InkWell(
                          onTap: () => Navigator.of(ctx).pop('delete' as T?),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.red),
                              const SizedBox(width: 2),
                              Text(deleteText,
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.red, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(child: content),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  if (showCancel) ...[
                    Expanded(
                      child: _Btn(
                        label: cancelText,
                        filled: false,
                        onTap: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: _Btn(
                      label: confirmText,
                      filled: true,
                      danger: destructive,
                      onTap: () => Navigator.of(ctx).pop(confirmValue ?? (true as T?)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Btn extends StatelessWidget {
  final String label;
  final bool filled;
  final bool danger;
  final VoidCallback onTap;
  const _Btn({required this.label, required this.filled, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFEF4444) : AppColors.brand;
    return Material(
      color: filled ? color : const Color(0xFFF1F4F8),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }
}
