import 'dart:convert';
import 'dart:io';
import '../native/native_bridge.dart';

/// 长期记忆：落盘到 filesDir/memory.json。
class MemoryStore {
  final Map<String, String> _data = {};

  /// 被关闭的记忆（留着不删，但不注入给 AI）。
  final Set<String> _disabled = {};

  Map<String, String> get all => Map.unmodifiable(_data);

  bool isEnabled(String key) => !_disabled.contains(key);

  Map<String, String> get enabledOnly =>
      Map.unmodifiable({for (final e in _data.entries) if (isEnabled(e.key)) e.key: e.value});

  Future<void> setEnabled(String key, bool on) async {
    on ? _disabled.remove(key) : _disabled.add(key);
    await _persist();
  }

  Future<File?> _file() async {
    final d = await NativeBridge.appDataDir();
    if (d.isEmpty) return null;
    return File('$d/memory.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _data.clear();
      _disabled.clear();
      if (m['entries'] is Map) {
        final e = m['entries'] as Map;
        _data.addAll(e.map((k, v) => MapEntry(k.toString(), v.toString())));
        final d = m['disabled'];
        if (d is List) _disabled.addAll(d.map((x) => x.toString()));
      } else {
        // 旧格式：直接是 key -> value
        _data.addAll(m.map((k, v) => MapEntry(k, v.toString())));
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final f = await _file();
      await f?.writeAsString(jsonEncode({'entries': _data, 'disabled': _disabled.toList()}));
    } catch (_) {}
  }

  void set(String key, String value) {
    _data[key] = value;
    _persist();
  }

  String? get(String key) => _data[key];

  void remove(String key) {
    _data.remove(key);
    _persist();
  }

  void clear() {
    _data.clear();
    _persist();
  }

  String summary() {
    final on = enabledOnly;
    if (on.isEmpty) {
      return _data.isEmpty ? '（暂无记忆）' : '（记忆都关闭了：${_data.length} 条）';
    }
    final sb = StringBuffer(on.entries.map((e) => '- ${e.key}: ${e.value}').join('\n'));
    final off = _data.length - on.length;
    if (off > 0) sb.write('\n（另有 $off 条记忆已关闭）');
    return sb.toString();
  }
}
