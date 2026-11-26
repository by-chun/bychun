/// Agent 工具契约与结果。
///
/// 工具除了返回文本，还可以附带一个「视图」（view），由 App 用通用渲染器画成卡片。
/// 这样新功能只要返回数据 + view 类型，不用为每个功能单独写页面。
class ToolResult {
  final bool ok;
  final String content;

  /// 视图类型：list / detail / stream / form / media / confirm / code。
  /// 为空表示只是一段文本结果，不渲染卡片。
  final String? view;

  /// 视图标题（卡片头部）。
  final String? title;

  /// 视图数据，结构随 view 类型而定，见 lib/widgets/view_cards.dart。
  final Map<String, dynamic>? viewData;

  const ToolResult(
    this.ok,
    this.content, {
    this.view,
    this.title,
    this.viewData,
  });

  ToolResult withView(String view, {String? title, Map<String, dynamic>? data}) =>
      ToolResult(ok, content, view: view, title: title, viewData: data);
}

/// 把一次命令执行整理成终端风格的行（stream 卡片用）。
List<String> terminalLines(
  String cmd, {
  String stdout = '',
  String stderr = '',
  int code = 0,
}) {
  final lines = <String>['\$ $cmd'];
  final out = stdout.trimRight();
  if (out.isNotEmpty) lines.addAll(out.split('\n'));
  final err = stderr.trimRight();
  if (err.isNotEmpty) lines.addAll(err.split('\n').map((l) => '[err] $l'));
  lines.add('[exit $code]');
  return lines;
}

/// 实时命令输出的接收方（UI 渲染成 stream 卡片）。
abstract class LiveShellSink {
  void startLive(String title);
  void pushLive(String line);
  void endLive(int code);
}

abstract class AgentTool {
  String get name;
  String get description;

  /// 参数名 -> 说明（用于生成函数调用 schema 与提示词）。
  Map<String, String> get parameters;

  Future<ToolResult> execute(Map<String, String> args);
}
