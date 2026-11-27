import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../native/native_bridge.dart';

class Appearance {
  final String path;
  final double opacity; // 0-100
  final double blur; // 0-20

  /// 液态玻璃：磨砂强度
  final double glassBlur;

  /// 液态玻璃：底色不透明度 0.2-0.9
  final double glassTint;

  /// 液态玻璃：边缘高光 0-1
  final double glassEdge;

  const Appearance({
    this.path = '',
    this.opacity = 60,
    this.blur = 4,
    this.glassBlur = 22,
    this.glassTint = 0.14,
    this.glassEdge = 0.9,
  });

  bool get hasImage => path.isNotEmpty && File(path).existsSync();

  Appearance copyWith({
    String? path,
    double? opacity,
    double? blur,
    double? glassBlur,
    double? glassTint,
    double? glassEdge,
  }) =>
      Appearance(
        path: path ?? this.path,
        opacity: opacity ?? this.opacity,
        blur: blur ?? this.blur,
        glassBlur: glassBlur ?? this.glassBlur,
        glassTint: glassTint ?? this.glassTint,
        glassEdge: glassEdge ?? this.glassEdge,
      );
}

class AppearanceNotifier extends AsyncNotifier<Appearance> {
  @override
  Future<Appearance> build() async => AppearanceStore.load();

  Future<void> setImage(String src) async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return;
    final dst = '$dir/background.png';
    await File(src).copy(dst);
    final cur = await AppearanceStore.load();
    await _write(cur.copyWith(path: dst));
  }

  Future<void> setLevels({double? opacity, double? blur}) async {
    final cur = await AppearanceStore.load();
    await _write(cur.copyWith(opacity: opacity, blur: blur));
  }

  Future<void> removeImage() async {
    final cur = await AppearanceStore.load();
    await _write(cur.copyWith(path: ''));
  }

  Future<void> _write(Appearance a) async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return;
    await File('$dir/appearance.json').writeAsString(
      jsonEncode({'path': a.path, 'opacity': a.opacity, 'glassBlur': a.glassBlur, 'glassTint': a.glassTint, 'glassEdge': a.glassEdge, 'blur': a.blur}),
    );
    state = AsyncData(a);
  }
}

final appearanceProvider = AsyncNotifierProvider<AppearanceNotifier, Appearance>(AppearanceNotifier.new);

class AppearanceStore {
  static Future<Appearance> load() async {
    try {
      final dir = await NativeBridge.appDataDir();
      if (dir.isEmpty) return const Appearance();
      final f = File('$dir/appearance.json');
      if (!await f.exists()) return const Appearance();
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return Appearance(
        path: (m['path'] ?? '').toString(),
        opacity: (m['opacity'] as num?)?.toDouble() ?? 60,
        blur: (m['blur'] as num?)?.toDouble() ?? 4,
        glassBlur: (m['glassBlur'] as num?)?.toDouble() ?? 22,
        glassTint: (m['glassTint'] as num?)?.toDouble() ?? 0.14,
        glassEdge: (m['glassEdge'] as num?)?.toDouble() ?? 0.9,
      );
    } catch (_) {
      return const Appearance();
    }
  }

  static Future<void> save(Appearance a) async {
    try {
      final dir = await NativeBridge.appDataDir();
      if (dir.isEmpty) return;
      final f = File('$dir/appearance.json');
      await f.writeAsString(jsonEncode({
        'path': a.path,
        'opacity': a.opacity,
        'blur': a.blur,
        'glassBlur': a.glassBlur,
        'glassTint': a.glassTint,
        'glassEdge': a.glassEdge,
      }));
    } catch (_) {}
  }
}
