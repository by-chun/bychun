import 'dart:convert';
import 'dart:io';
import '../native/native_bridge.dart';

/// AI 人物（头像、名字、人设、说话风格）。
class Persona {
  String name;
  String avatar;
  String persona;
  String style;
  bool active;

  Persona({
    this.name = '',
    this.avatar = '',
    this.persona = '',
    this.style = '',
    this.active = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'avatar': avatar,
        'persona': persona,
        'style': style,
        'active': active,
      };

  factory Persona.fromJson(Map<String, dynamic> m) => Persona(
        name: (m['name'] ?? '').toString(),
        avatar: (m['avatar'] ?? '').toString(),
        persona: (m['persona'] ?? '').toString(),
        style: (m['style'] ?? '').toString(),
        active: m['active'] == true,
      );
}

class PersonaStore {
  static Future<File?> _file() async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return null;
    return File('$dir/personas.json');
  }

  static Future<List<Persona>> load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => Persona.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Persona> list) async {
    try {
      final f = await _file();
      await f?.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<Persona?> active() async {
    final list = await load();
    for (final p in list) {
      if (p.active) return p;
    }
    return null;
  }

  /// 保存头像文件（来自相册）到 app 私有目录，返回路径。
  static Future<String> saveAvatar(String srcPath, String name) async {
    try {
      final dir = await NativeBridge.appDataDir();
      if (dir.isEmpty) return srcPath;
      final ext = srcPath.contains('.') ? srcPath.substring(srcPath.lastIndexOf('.')) : '.png';
      final dest = '$dir/avatar_${DateTime.now().millisecondsSinceEpoch}$ext';
      await File(srcPath).copy(dest);
      return dest;
    } catch (_) {
      return srcPath;
    }
  }
}
