import 'dart:convert';
import 'dart:io';
import '../native/native_bridge.dart';

/// 一条 Xposed 脚本：名称、启用、作用域（目标包名）、JS 代码。
class XposedScript {
  String name;
  bool enabled;
  List<String> targets;
  String code;
  XposedScript({this.name = '', this.enabled = true, List<String>? targets, this.code = ''})
      : targets = targets ?? [];

  Map<String, dynamic> toJson() =>
      {'name': name, 'enabled': enabled, 'targets': targets, 'code': code};

  factory XposedScript.fromJson(Map<String, dynamic> m) => XposedScript(
        name: (m['name'] ?? '').toString(),
        enabled: m['enabled'] != false,
        targets: ((m['targets'] as List?) ?? const []).map((e) => e.toString()).toList(),
        code: (m['code'] ?? '').toString(),
      );
}

/// XposedHook 在目标进程里读同一个文件（/data/data/com.chun.by/files/xposed_scripts.json）。
class XposedStore {
  static Future<File?> _file() async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return null;
    return File('$dir/xposed_scripts.json');
  }

  static Future<List<XposedScript>> load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => XposedScript.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<XposedScript> list) async {
    final json = jsonEncode(list.map((e) => e.toJson()).toList());
    try {
      final f = await _file();
      await f?.writeAsString(json);
    } catch (_) {}
    // 目标进程（Xposed 模块）读不到 Rowan 私有目录，额外用 root 写一份 world-readable 副本
    try {
      final b64 = base64Encode(utf8.encode(json));
      await NativeBridge.rootExec(
        "mkdir -p /data/local/tmp/rowan && echo '$b64' | base64 -d > /data/local/tmp/rowan/xposed_scripts.json "
        "&& chmod 644 /data/local/tmp/rowan/xposed_scripts.json && chmod 755 /data/local/tmp/rowan",
        timeout: 15,
      );
    } catch (_) {}
  }
}
