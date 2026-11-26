import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

class ThemeColorNotifier extends Notifier<Color> {
  @override
  Color build() => AppColors.brand;
  void set(Color c) => state = c;
}

/// 品牌色（设置→外观主题可切换）。
final themeColorProvider = NotifierProvider<ThemeColorNotifier, Color>(ThemeColorNotifier.new);
