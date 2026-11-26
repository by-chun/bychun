import 'dart:convert';
import '../native/native_bridge.dart';
import 'tool.dart';
import 'tool_registry.dart';

/// 在容器里写文本文件（用 base64 传输，避免引号/换行转义问题）。
class WriteFileTool extends AgentTool {
  @override
  String get name => 'writeFile';

  @override
  String get description =>
      '把文本内容写入容器里的文件（自动建目录、覆盖）。适合写脚本、配置文件，如 /root/mitm/capture.py。';

  @override
  Map<String, String> get parameters => {'path': '容器内绝对路径', 'content': '文件内容'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final path = (args['path'] ?? '').trim();
    final content = args['content'] ?? '';
    if (path.isEmpty) return const ToolResult(false, 'path 不能为空');
    final b64 = base64Encode(utf8.encode(content));
    final dir = path.substring(0, path.lastIndexOf('/') == -1 ? 0 : path.lastIndexOf('/'));
    final r = await NativeBridge.prootExec(
      '${dir.isEmpty ? '' : 'mkdir -p "$dir" && '}'
      'printf %s "$b64" | base64 -d > "$path" && echo OK && wc -c < "$path"',
    );
    if (!r.stdout.contains('OK')) {
      return ToolResult(false, '写入失败：${r.stderr.trim()}');
    }
    final bytes = r.stdout.split('\n').last.trim();
    return ToolResult(true, '已写入 $path（$bytes 字节）');
  }
}

/// 读取容器里的文本文件（前 N 行）。
class ReadFileTool extends AgentTool {
  @override
  String get name => 'readFile';

  @override
  String get description => '读取容器里的文本文件内容（默认全部读出，不截断）。';

  @override
  Map<String, String> get parameters => {'path': '容器内绝对路径'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final path = (args['path'] ?? '').trim();
    if (path.isEmpty) return const ToolResult(false, 'path 不能为空');
    final r = await NativeBridge.prootExec('cat "$path"');
    if (r.code != 0) return ToolResult(false, '读取失败：${r.stderr.trim()}');
    final out = r.stdout;
    return ToolResult(true, out.isEmpty ? '（空文件）' : out);
  }
}

void registerFileTools(ToolRegistry reg) {
  reg.register(WriteFileTool());
  reg.register(ReadFileTool());
}
