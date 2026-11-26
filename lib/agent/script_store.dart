import 'dart:convert';
import 'dart:io';
import '../native/native_bridge.dart';

/// 通用脚本：类型决定执行方式（shell 走容器/宿主，lua/js 需对应解释器）。
class Script {
  String name;
  String type; // shell / python / js / lua / xp / capture / api / rule
  String content;

  /// 结构化配置：image / icon / width / height / opacity / permissions …
  Map<String, String> meta;

  /// 是否启用（关掉的插件不会被 AI 使用、也不注入规则）。
  bool enabled;

  Script({
    this.name = '',
    this.type = 'shell',
    this.content = '',
    Map<String, String>? meta,
    this.enabled = true,
  }) : meta = meta ?? {};

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'content': content,
        'enabled': enabled,
        if (meta.isNotEmpty) 'meta': meta,
      };

  factory Script.fromJson(Map<String, dynamic> m) => Script(
        name: (m['name'] ?? '').toString(),
        type: (m['type'] ?? 'shell').toString(),
        content: (m['content'] ?? '').toString(),
        meta: (m['meta'] is Map)
            ? Map<String, String>.from(
                (m['meta'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
            : {},
        enabled: m['enabled'] != false,
      );
}

class ScriptStore {
  static Future<File?> _file() async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return null;
    return File('$dir/scripts.json');
  }

  static Future<List<Script>> load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => Script.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Script> list) async {
    try {
      final f = await _file();
      await f?.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
