import 'tool.dart';
import 'tool_registry.dart';

/// 在对话里给出候选选项让用户挑（不确定走哪条路时用）。
class AskChooseTool extends AgentTool {
  @override
  String get name => 'askChoose';

  @override
  String get description =>
      '让用户在对话里点选一个选项。options 用「标题|说明」逗号分隔，可加 tag 标记推荐。用户点完会作为一条消息回来。';

  @override
  Map<String, String> get parameters => {
        'title': '问题，如「用哪种方式改」',
        'options': '选项，用分号 ; 分隔，每个写成 标题|说明（说明里可以带逗号）',
        'multi': '可选：true 表示可多选',
        'cancel': '可选：取消项文字，默认「都别用」',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final title = (args['title'] ?? '').trim();
    final raw = (args['options'] ?? '').trim();
    if (raw.isEmpty) return const ToolResult(false, 'options 不能为空');
    final options = <Map<String, dynamic>>[];
    for (final part in raw.split(RegExp(r'[;；\n]'))) {
      final s = part.trim();
      if (s.isEmpty) continue;
      final cut = s.indexOf('|');
      final t = cut >= 0 ? s.substring(0, cut).trim() : s;
      final d = cut >= 0 ? s.substring(cut + 1).trim() : '';
      if (t.isEmpty) continue;
      options.add({'title': t, 'desc': d});
    }
    if (options.isEmpty) return const ToolResult(false, 'options 不能为空');
    return ToolResult(
      true,
      '已弹出 ${options.length} 个选项，等用户选择',
      view: 'choose',
      title: title.isEmpty ? '选一个' : title,
      viewData: {
        'options': options,
        'multi': (args['multi'] ?? '').toLowerCase() == 'true',
        'cancel': (args['cancel'] ?? '都别用').trim().isEmpty ? '都别用' : args['cancel']!.trim(),
      },
    );
  }
}

/// 用于收集配置（如仓库 owner / token），AI 拿到后自己写脚本或文件。
class AskFormTool extends AgentTool {
  @override
  String get name => 'askForm';

  @override
  String get description => '在对话里弹出填写表单：fields 传字段名（逗号分隔）。用户提交后会收到一条「label: value」的用户消息。';

  @override
  Map<String, String> get parameters => {
        'title': '表单标题，如「云端构建配置」',
        'fields': '字段名，逗号分隔，如：仓库 owner,仓库名 repo,分支,Token',
        'submit': '可选：提交按钮文字，默认「提交」',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final title = (args['title'] ?? '').trim();
    final raw = (args['fields'] ?? '').trim();
    if (raw.isEmpty) return const ToolResult(false, 'fields 不能为空');
    final fields = raw
        .split(RegExp(r'[,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => {'key': e, 'label': e, 'value': ''})
        .toList();
    if (fields.isEmpty) return const ToolResult(false, 'fields 不能为空');
    return ToolResult(
      true,
      '已弹出表单「${title.isEmpty ? '填写' : title}」，等用户提交',
      view: 'form',
      title: title.isEmpty ? '填写' : title,
      viewData: {
        'fields': fields,
        'submit': (args['submit'] ?? '提交').trim().isEmpty ? '提交' : args['submit']!.trim(),
      },
    );
  }
}

/// 弹出内存搜索卡片：用户选类型（A/B/W/D/Q/F/E/H）并填值，提交后作为消息回来。
class AskMemSearchTool extends AgentTool {
  @override
  String get name => 'askMemSearch';

  @override
  String get description =>
      '用户要搜索/修改内存值时，先调它弹出内存搜索卡片（GG 类型 A/B/W/D/Q/F/E/H + PID + 搜索值），'
      '不要直接猜类型和值。用户提交后会收到一条「内存搜索：pid …，类型 …，值 …」的消息，再用 memScan 执行。';

  @override
  Map<String, String> get parameters => {'pid': '可选：目标进程 PID，已知就填'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final pid = (args['pid'] ?? '').trim();
    return ToolResult(
      true,
      '已弹出内存搜索卡片，等用户选择类型并填值',
      view: 'memsearch',
      title: '内存搜索',
      viewData: {'pid': pid},
    );
  }
}

void registerFormTools(ToolRegistry reg) {
  reg.register(AskFormTool());
  reg.register(AskChooseTool());
  reg.register(AskMemSearchTool());
}
