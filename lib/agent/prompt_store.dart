import 'dart:convert';
import 'dart:io';
import '../native/native_bridge.dart';
import 'default_prompt.dart';


/// 提示词（可多条，当前生效一条）。
class Prompt {
  String name;
  String content;
  bool active;
  Prompt({this.name = '', this.content = '', this.active = false});

  Map<String, dynamic> toJson() => {'name': name, 'content': content, 'active': active};
  factory Prompt.fromJson(Map<String, dynamic> m) => Prompt(
        name: (m['name'] ?? '').toString(),
        content: (m['content'] ?? '').toString(),
        active: m['active'] == true,
      );
}

class PromptStore {
  static Future<File?> _file() async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return null;
    return File('$dir/prompts.json');
  }

  static Future<List<Prompt>> load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => Prompt.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Prompt> list) async {
    try {
      final f = await _file();
      await f?.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// 内置规则升级：旧版内置规则（无 builtin 标记）替换为最新内容。
  static Future<void> ensureBuiltin() async {
    final list = await load();
    final idx = list.indexWhere((p) => p.name == kDefaultPromptName);
    if (idx < 0) {
      list.add(Prompt(
        name: kDefaultPromptName,
        content: kDefaultPromptContent,
        active: list.every((p) => !p.active),
      ));
      await save(list);
      return;
    }
    if (!list[idx].content.contains('builtin:v16')) {
      list[idx] = Prompt(
        name: kDefaultPromptName,
        content: kDefaultPromptContent,
        active: list[idx].active,
      );
      await save(list);
    }
  }

  /// 当前生效的提示词正文（没有则空）。
  static Future<String> activeContent() async {
    for (final p in await load()) {
      if (p.active && p.content.trim().isNotEmpty) return p.content.trim();
    }
    return '';
  }
}
