import 'dart:convert';

import 'tool.dart';
import 'tool_registry.dart';
import 'plugins_store.dart';

/// AI 自己创建插件：给一个 JSON 清单就能装上，装完即生效（不用重启）。
class PluginCreateTool extends AgentTool {
  @override
  String get name => 'plugin_create';

  @override
  String get description =>
      '创建一个 Rowan 插件（声明式 JSON 清单，装完即生效，不用重启）。'
      '参数 id（小写字母数字-，如 local-quote）和 manifest（JSON 字符串）。'
      'manifest 字段：title（标题）、icon（可选：bolt star sparkle heart flag bookmark pin bell clock note document folder search code terminal globe chart lightbulb book puzzle robot chat mail translate image camera mic link summary wrench bug info warning check done settings send copy quote share edit add delete refresh plugin bot agent skill model tool workflow goal plan command time today schedule user group phone cloud server power theme palette）'
      '、"composer.actions"（输入框上方胶囊，≤2，每个 {id,label≤10字,icon?,effect?}）、'
      '"message.actions"（长按回复菜单，≤2，{id,label≤12字,icon?,effect?}）、'
      '"panels"（面板，≤4，{id,title≤16字,icon?,view?}，view 是 JSON 视图树：stack/row/text/metric/list/keyValue/table/actions/progress/callout）。'
      'effect 是点按后的静态效果，只能写一个：{"insert":"文字"}放进输入框不发、{"send":"文字"}直接发给 AI、{"toast":"提示"}、{"open":"panel:<面板id>"}。'
      '同一插件内所有 id 不能重复。不要在清单里放密钥。';

  @override
  Map<String, String> get parameters => {
        'id': '插件 id：小写字母、数字、- . _，字母数字开头，≤40 字',
        'manifest': 'JSON 清单字符串，见说明',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final id = (args['id'] ?? '').trim();
    final raw = (args['manifest'] ?? '').trim();
    if (id.isEmpty) return const ToolResult(false, 'id 不能为空');
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$').hasMatch(id)) {
      return const ToolResult(false, 'id 只能是小写字母、数字、- . _，且字母数字开头');
    }
    dynamic m;
    try {
      m = jsonDecode(raw);
    } catch (e) {
      return ToolResult(false, 'manifest 不是合法 JSON：$e');
    }
    if (m is! Map) return const ToolResult(false, 'manifest 必须是 JSON 对象');
    // 校验：id 不重复、数量上限
    final ids = <String>{};
    for (final slot in ['composer.actions', 'message.actions', 'panels']) {
      final v = m[slot];
      if (v is! List) continue;
      for (final e in v) {
        if (e is! Map) continue;
        final eid = (e['id'] ?? '').toString();
        if (eid.isEmpty) return ToolResult(false, '$slot 里有条目缺 id');
        if (!ids.add(eid)) return ToolResult(false, 'id 重复：$eid（整个插件内不能重复）');
      }
    }
    try {
      final p = await PluginsNotifier.create(id: id, manifest: Map<String, dynamic>.from(m));
      return ToolResult(true, '已创建插件「${p.title}」（${p.dir}）。'
          '胶囊在输入框上方、菜单项在长按回复的菜单里，已即时生效。'
          '要改就再调一次 plugin_create 覆盖；要关掉用 plugin_toggle。');
    } catch (e) {
      return ToolResult(false, '创建失败：$e');
    }
  }
}

/// 列出已装插件。
class PluginListTool extends AgentTool {
  @override
  String get name => 'plugin_list';

  @override
  String get description => '列出 /sdcard/Rowan/plugins 下已安装的 Rowan 插件及其开关状态、贡献的按钮/菜单/面板。';

  @override
  Map<String, String> get parameters => {};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final list = await PluginsNotifier.loadAll();
    if (list.isEmpty) return const ToolResult(true, '还没有插件。用 plugin_create 创建一个。');
    final buf = StringBuffer();
    for (final p in list) {
      buf.writeln('${p.enabled ? '✓' : '✗'} ${p.id}（${p.title}）${p.dir}');
      for (final a in p.composerActions) buf.writeln('   胶囊: ${a['id']} · ${a['label']}');
      for (final a in p.messageActions) buf.writeln('   菜单: ${a['id']} · ${a['label']}');
      for (final a in p.panels) buf.writeln('   面板: ${a['id']} · ${a['title']}');
    }
    return ToolResult(true, buf.toString().trimRight());
  }
}

/// 开关插件。
class PluginToggleTool extends AgentTool {
  @override
  String get name => 'plugin_toggle';

  @override
  String get description => '打开或关闭一个 Rowan 插件（改 plugin.json 的 enabled，即时生效）。';

  @override
  Map<String, String> get parameters => {
        'id': '插件 id（或目录名）',
        'enabled': 'true 打开 / false 关闭',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final id = (args['id'] ?? '').trim();
    final en = (args['enabled'] ?? 'true').trim().toLowerCase() == 'true';
    if (id.isEmpty) return const ToolResult(false, 'id 不能为空');
    final list = await PluginsNotifier.loadAll();
    final p = list.where((e) => e.id == id || e.dir.endsWith('/$id')).toList();
    if (p.isEmpty) return ToolResult(false, '没找到插件 $id');
    await PluginsNotifier.setEnabled(p.first.dir, en);
    return ToolResult(true, '已${en ? '打开' : '关闭'}插件「${p.first.title}」');
  }
}

/// 删除插件。
class PluginDeleteTool extends AgentTool {
  @override
  String get name => 'plugin_delete';

  @override
  String get description => '删除一个 Rowan 插件（整个目录）。高危，建议先确认。';

  @override
  Map<String, String> get parameters => {'id': '插件 id（或目录名）'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final id = (args['id'] ?? '').trim();
    if (id.isEmpty) return const ToolResult(false, 'id 不能为空');
    final list = await PluginsNotifier.loadAll();
    final p = list.where((e) => e.id == id || e.dir.endsWith('/$id')).toList();
    if (p.isEmpty) return ToolResult(false, '没找到插件 $id');
    await PluginsNotifier.delete(p.first.dir);
    return ToolResult(true, '已删除插件 $id');
  }
}

void registerRowanPluginTools(ToolRegistry reg) {
  reg.register(PluginCreateTool());
  reg.register(PluginListTool());
  reg.register(PluginToggleTool());
  reg.register(PluginDeleteTool());
}
