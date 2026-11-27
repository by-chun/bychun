import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/native_bridge.dart';

/// Rowan 插件清单（`plugin.json`），仿 dsh-go 的声明式设计：
/// 一个目录 = 一个插件；清单声明它在 App 里出现什么；按钮点按可以带静态效果。
///
/// 目录结构：
///   /storage/emulated/0/Rowan/plugins/<id>/plugin.json
///
/// 清单字段：
/// {
///   "v": 1,
///   "id": "local-quote",
///   "title": "引用",
///   "icon": "quote",                       // 可选
///   "enabled": true,                        // 可选，开关
///   "composer.actions": [ {id,label,icon?,effect?} ],   // 输入框上方胶囊（≤2）
///   "message.actions":  [ {id,label,icon?,effect?} ],   // 长按回复菜单（≤2）
///   "panels": [ {id,title,icon?,view?} ]               // 面板（≤4），view 是 JSON 视图树
/// }
///
/// effect（静态效果，App 直接执行，不跑代码）：
///   { "insert": "文字" }   放进输入框，不自动发送
///   { "send": "文字" }     直接作为消息发送给 AI
///   { "toast": "提示" }
///   { "open": "panel:<id>" }
class RowanPlugin {
  final String id;
  final String dir;
  final Map<String, dynamic> manifest;
  final bool enabled;

  const RowanPlugin({required this.id, required this.dir, required this.manifest, required this.enabled});

  String get title => (manifest['title'] is Map)
      ? ((manifest['title']['zh'] ?? manifest['title']['en'] ?? id).toString())
      : (manifest['title'] ?? id).toString();

  String get icon => (manifest['icon'] ?? 'plugin').toString();

  /// 输入框上方胶囊（最多 2 个）。
  List<Map<String, dynamic>> get composerActions =>
      _listOf(manifest['composer.actions'], 2);

  /// 长按回复菜单项（最多 2 个）。
  List<Map<String, dynamic>> get messageActions =>
      _listOf(manifest['message.actions'], 2);

  /// 面板（最多 4 个）。
  List<Map<String, dynamic>> get panels => _listOf(manifest['panels'], 4);

  static List<Map<String, dynamic>> _listOf(dynamic v, int max) {
    if (v is! List) return const [];
    return v.whereType<Map>().take(max).map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

class PluginsNotifier extends Notifier<List<RowanPlugin>> {
  @override
  List<RowanPlugin> build() {
    _load();
    return const [];
  }

  static String get rootDir => '/storage/emulated/0/Rowan/plugins';

  Future<void> _load() async {
    state = await loadAll();
  }

  Future<void> refresh() async => _load();

  /// 扫描插件目录，读取每个 plugin.json。
  static Future<List<RowanPlugin>> loadAll() async {
    final root = Directory(rootDir);
    if (!await root.exists()) return const [];
    final out = <RowanPlugin>[];
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final f = File('${e.path}/plugin.json');
      if (!await f.exists()) continue;
      try {
        final m = jsonDecode(await f.readAsString());
        if (m is Map) {
          out.add(RowanPlugin(
            id: (m['id'] ?? e.path.split('/').last).toString(),
            dir: e.path,
            manifest: Map<String, dynamic>.from(m),
            enabled: m['enabled'] != false,
          ));
        }
      } catch (_) {}
    }
    return out;
  }

  /// 创建（或覆盖）一个插件：写目录 + plugin.json。
  static Future<RowanPlugin> create({
    required String id,
    required Map<String, dynamic> manifest,
  }) async {
    final safe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(id) ? id : 'plugin-${DateTime.now().millisecondsSinceEpoch}';
    final dir = Directory('$rootDir/$safe');
    await dir.create(recursive: true);
    final m = {...manifest, 'id': safe, 'v': manifest['v'] ?? 1};
    await File('${dir.path}/plugin.json').writeAsString(const JsonEncoder.withIndent('  ').convert(m));
    return RowanPlugin(id: safe, dir: dir.path, manifest: m, enabled: m['enabled'] != false);
  }

  /// 开关插件（改 plugin.json 的 enabled）。
  static Future<void> setEnabled(String dir, bool enabled) async {
    final f = File('$dir/plugin.json');
    if (!await f.exists()) return;
    final m = jsonDecode(await f.readAsString());
    if (m is! Map) return;
    m['enabled'] = enabled;
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(m));
  }

  /// 删除插件目录。
  static Future<void> delete(String dir) async {
    try {
      await Directory(dir).delete(recursive: true);
    } catch (_) {}
  }
}

final pluginsProvider = NotifierProvider<PluginsNotifier, List<RowanPlugin>>(PluginsNotifier.new);

/// 汇总所有启用插件的胶囊按钮（App 全局上限 8 个）。
List<(RowanPlugin, Map<String, dynamic>)> allComposerActions(List<RowanPlugin> list) {
  final out = <(RowanPlugin, Map<String, dynamic>)>[];
  for (final p in list) {
    if (!p.enabled) continue;
    for (final a in p.composerActions) {
      out.add((p, a));
      if (out.length >= 8) return out;
    }
  }
  return out;
}

/// 汇总所有启用插件的菜单项。
List<(RowanPlugin, Map<String, dynamic>)> allMessageActions(List<RowanPlugin> list) {
  final out = <(RowanPlugin, Map<String, dynamic>)>[];
  for (final p in list) {
    if (!p.enabled) continue;
    for (final a in p.messageActions) {
      out.add((p, a));
    }
  }
  return out;
}

/// 执行一个静态效果。
/// 返回 (type, text)：type = insert / send / toast / open。
(String, String) applyEffect(Map<String, dynamic> effect) {
  if (effect['insert'] != null) return ('insert', effect['insert'].toString());
  if (effect['send'] != null) return ('send', effect['send'].toString());
  if (effect['open'] != null) return ('open', effect['open'].toString());
  if (effect['toast'] != null) return ('toast', effect['toast'].toString());
  return ('toast', '这个按钮没有配置效果');
}

/// 预置：确保插件目录存在，并放入一个示例插件（首次）。
Future<void> ensurePluginsSeeded() async {
  try {
    final root = Directory(PluginsNotifier.rootDir);
    await root.create(recursive: true);
    final example = File('${root.path}/local-hello/plugin.json');
    if (await example.exists()) return;
    await PluginsNotifier.create(
      id: 'local-hello',
      manifest: {
        'title': '示例',
        'icon': 'sparkle',
        'composer.actions': [
          {'id': 'summarize', 'label': '总结', 'icon': 'summary', 'effect': {'send': '总结上面的对话，列三条要点。'}},
          {'id': 'hello', 'label': '打招呼', 'icon': 'chat', 'effect': {'insert': '你好，'}},
        ],
      },
    );
  } catch (_) {}
}
