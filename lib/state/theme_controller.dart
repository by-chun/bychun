import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一套主题：主色 + 辅色（渐变两端），与网页原型的 7 套一一对应。
class RowanTheme {
  final String name;
  final Color accent;
  final Color accent2;
  const RowanTheme(this.name, this.accent, this.accent2);

  /// 主色 → 辅色的对角渐变，用于按钮 / 发送 / 头像等强调元素。
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, accent2],
      );
}

const List<RowanTheme> rowanThemes = [
  RowanTheme('星蓝', Color(0xFF4D7CFE), Color(0xFF8A6BFF)),
  RowanTheme('晨曦', Color(0xFFFF6B8A), Color(0xFFFFA94D)),
  RowanTheme('极光', Color(0xFF2DD4BF), Color(0xFF22D3EE)),
  RowanTheme('暮紫', Color(0xFFA78BFA), Color(0xFFF472B6)),
  RowanTheme('青柠', Color(0xFF84CC16), Color(0xFF22C55E)),
  RowanTheme('落日', Color(0xFFF97316), Color(0xFFEF4444)),
  RowanTheme('夜黑', Color(0xFF6366F1), Color(0xFF0EA5E9)),
];

class ThemeColorNotifier extends Notifier<RowanTheme> {
  @override
  RowanTheme build() => rowanThemes.first;

  /// 按索引切换主题（设置 → 外观主题）。
  void set(int i) => state = rowanThemes[i % rowanThemes.length];
}

/// 当前主题（Material 种子色取其 accent）。
final themeColorProvider = NotifierProvider<ThemeColorNotifier, RowanTheme>(ThemeColorNotifier.new);
