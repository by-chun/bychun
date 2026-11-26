import 'tool.dart';

class ToolRegistry {
  final Map<String, AgentTool> _tools = {};

  void register(AgentTool tool) => _tools[tool.name] = tool;

  AgentTool? get(String name) => _tools[name];

  List<AgentTool> get all => _tools.values.toList();

  String describe() {
    final sb = StringBuffer();
    for (final t in _tools.values) {
      sb.writeln('- ${t.name}: ${t.description}');
    }
    return sb.toString();
  }
}
