import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../native/native_bridge.dart';

/// 当前工作区（目录）。AI 默认在这个目录里干活。
class WorkspaceNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    try {
      final dir = await NativeBridge.appDataDir();
      if (dir.isEmpty) return null;
      final f = File('$dir/workspace.json');
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final p = (m['path'] ?? '').toString();
      return p.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }

  Future<void> set(String path) async {
    try {
      final dir = await NativeBridge.appDataDir();
      if (dir.isEmpty) return;
      await File('$dir/workspace.json').writeAsString(jsonEncode({'path': path}));
      state = AsyncData(path);
    } catch (_) {}
  }

  Future<void> clear() async {
    await set('');
    state = const AsyncData(null);
  }
}

final workspaceProvider = AsyncNotifierProvider<WorkspaceNotifier, String?>(WorkspaceNotifier.new);
