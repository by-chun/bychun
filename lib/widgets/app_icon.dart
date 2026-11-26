import 'dart:convert';
import 'package:flutter/material.dart';

/// 应用图标：优先用 APK 里的真实图标（原生侧已转 base64），取不到再退回首字块。
class AppIcon extends StatelessWidget {
  final Map<String, dynamic> app;
  final double size;
  const AppIcon({super.key, required this.app, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final b64 = (app['icon'] ?? '').toString();
    final label = (app['label'] ?? '?').toString();
    Widget child;
    if (b64.isNotEmpty) {
      try {
        child = Image.memory(
          base64Decode(b64),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _fallback(label),
        );
      } catch (_) {
        child = _fallback(label);
      }
    } else {
      child = _fallback(label);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _fallback(String label) {
    const cs = [
      Color(0xFF22C55E), Color(0xFF0EA5E9), Color(0xFF2563EB),
      Color(0xFF7C3AED), Color(0xFFF59E0B), Color(0xFFEF4444),
    ];
    final c = cs[label.isEmpty ? 0 : label.codeUnitAt(0) % cs.length];
    return Container(
      color: c,
      alignment: Alignment.center,
      child: Text(
        label.isEmpty ? '?' : label.substring(0, 1),
        style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w700),
      ),
    );
  }
}
