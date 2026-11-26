import 'dart:convert';

import '../native/native_bridge.dart';

/// 界面状态的轻量持久化：模式、上次滚动位置等，重启 App 后恢复。
class UiStateStore {
  static const _file = 'ui_state.json';

  static Future<Map<String, dynamic>> _load() async {
    try {
      final text = await NativeBridge.readAppFile(_file);
      if (text == null || text.trim().isEmpty) return {};
      final m = jsonDecode(text);
      return m is Map<String, dynamic> ? m : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, dynamic> m) async {
    try {
      await NativeBridge.writeAppFile(_file, jsonEncode(m));
    } catch (_) {}
  }

  static Future<String?> mode() async {
    final m = await _load();
    final v = (m['mode'] ?? '').toString();
    return v.isEmpty ? null : v;
  }

  static Future<void> saveMode(String mode) async {
    final m = await _load();
    m['mode'] = mode;
    await _save(m);
  }

  static Future<List<String>> drawerOpen() async {
    final m = await _load();
    final list = m['drawer'] as List?;
    return list?.map((e) => '$e').toList() ?? const [];
  }

  static Future<void> saveDrawerOpen(Iterable<String> keys) async {
    final m = await _load();
    m['drawer'] = keys.toList();
    await _save(m);
  }

  /// 输入框草稿，按会话区分（key 用会话 id，新会话用 new）。
  static Future<String> draft(String key) async {
    final m = await _load();
    return (m['draft_$key'] ?? '').toString();
  }

  static Future<void> saveDraft(String key, String text) async {
    final m = await _load();
    if (text.trim().isEmpty) {
      m.remove('draft_$key');
    } else {
      m['draft_$key'] = text;
    }
    await _save(m);
  }
}
