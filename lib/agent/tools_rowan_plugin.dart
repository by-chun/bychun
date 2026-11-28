import 'dart:convert';

import 'tool.dart';
import 'tool_registry.dart';
import 'plugins_store.dart';
import '../native/native_bridge.dart';

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

/// 从 GitHub 直接安装插件：给仓库地址，自动下载解包到插件目录并注册。
class PluginInstallTool extends AgentTool {
  @override
  String get name => 'plugin_install';

  @override
  String get description =>
      '从 GitHub 直接安装插件：传仓库地址（如 https://github.com/owner/repo），'
      '自动下载解包到 /sdcard/Rowan/plugins/<id>/，装完即生效（不用重启）。'
      '仓库里有 plugin.json 就直接用；只有 package.json（dsh-go 插件）就自动把 dshGo 清单转成 Rowan 插件；都没有就生成一个最小清单。';

  @override
  Map<String, String> get parameters => {
        'url': 'GitHub 仓库地址（也支持 tar.gz 直链）',
        'id': '可选：插件目录名，默认从仓库名取',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final rawUrl = (args['url'] ?? '').trim();
    if (rawUrl.isEmpty) return const ToolResult(false, 'url 不能为空');
    // 解析 owner/repo
    final m = RegExp(r'github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)').firstMatch(rawUrl);
    final owner = m?.group(1) ?? '';
    final repo = (m?.group(2) ?? '').replaceAll(RegExp(r'\.git$'), '');
    // 目录名
    var id = (args['id'] ?? '').trim().isNotEmpty ? args['id']!.trim() : (repo.isNotEmpty ? repo : '');
    id = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    if (id.isEmpty) id = 'plugin-${DateTime.now().millisecondsSinceEpoch}';
    if (!RegExp(r'^[A-Za-z0-9]').hasMatch(id)) id = 'p-$id';
    final dir = '/sdcard/Rowan/plugins';
    final tarball = owner.isNotEmpty
        ? 'https://github.com/$owner/$repo/archive/HEAD.tar.gz'
        : rawUrl;
    // 容器里下载 + 解包（busybox 自带 wget/tar）
    final script = "mkdir -p '$dir' && rm -rf '$dir/$id' && mkdir -p '$dir/$id' && "
        "cd '$dir/$id' && wget -qO- '$tarball' | tar xz --strip-components=1 && echo INSTALLED";
    final r = await NativeBridge.prootExec(script);
    if (!r.stdout.contains('INSTALLED')) {
      final err = r.stderr.trim().isEmpty ? r.stdout.trim() : r.stderr.trim();
      return ToolResult(false, '下载/解包失败（容器未就绪或网络问题）：$err');
    }
    // 检查 plugin.json；没有就从 package.json 生成
    final check = await NativeBridge.prootExec(
        "cat '$dir/$id/plugin.json' 2>/dev/null; echo '===PKG==='; cat '$dir/$id/package.json' 2>/dev/null");
    final parts = check.stdout.split('===PKG===');
    final hasPluginJson = (parts.isNotEmpty ? parts[0] : '').trim().isNotEmpty;
    if (!hasPluginJson) {
      final pkg = (parts.length > 1 ? parts[1] : '').trim();
      final manifest = <String, dynamic>{'v': 1, 'title': id, 'icon': 'plugin', 'enabled': true};
      if (pkg.isNotEmpty) {
        try {
          final pm = jsonDecode(pkg);
          if (pm is Map) {
            final dshGo = pm['dshGo'];
            if (dshGo is Map) {
              if (dshGo['title'] is String && (dshGo['title'] as String).isNotEmpty) manifest['title'] = dshGo['title'];
              if (dshGo['icon'] is String) manifest['icon'] = dshGo['icon'];
              final contrib = dshGo['contributes'];
              if (contrib is Map) {
                for (final k in ['composer.actions', 'message.actions', 'panels']) {
                  if (contrib[k] is List) manifest[k] = contrib[k];
                }
              }
            } else if (pm['name'] is String && (pm['name'] as String).isNotEmpty) {
              manifest['title'] = (pm['name'] as String).split('/').last;
            }
          }
        } catch (_) {}
      }
      final b64 = base64Encode(utf8.encode(jsonEncode(manifest)));
      await NativeBridge.prootExec(
          "mkdir -p '$dir/$id' && printf %s '$b64' | base64 -d > '$dir/$id/plugin.json'");
    }
    // 校验 + 返回
    final list = await PluginsNotifier.loadAll();
    final hit = list.where((p) => p.id == id || p.dir.endsWith('/$id')).toList();
    if (hit.isEmpty) {
      return ToolResult(true, '已下载到 $dir/$id，但没检测到有效 plugin.json（仓库可能不是插件，可让 AI 自己写一个）。');
    }
    return ToolResult(true,
        '已安装插件「${hit.first.title}」到 $dir/$id，输入框上方胶囊已即时生效（关掉用 plugin_toggle，删掉用 plugin_delete）。');
  }
}

void registerRowanPluginTools(ToolRegistry reg) {
  reg.register(PluginCreateTool());
  reg.register(PluginListTool());
  reg.register(PluginToggleTool());
  reg.register(PluginDeleteTool());
  reg.register(PluginInstallTool());
}
