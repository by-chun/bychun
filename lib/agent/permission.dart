import 'dart:convert';
import 'dart:io';
import '../native/native_bridge.dart';

enum DangerLevel { pure, read, write }

/// 工具授权规则：deny > confirm > allow；空规则默认 allow。
/// 可持久化到 filesDir/permission.json。
class PermissionPolicy {
  final List<String> allow = [];
  final List<String> deny = [];
  final List<String> confirm = [];

  static bool _match(String pattern, String s) {
    if (pattern.isEmpty) return false;
    if (pattern == '*') return true;
    if (pattern.endsWith('*')) return s.startsWith(pattern.substring(0, pattern.length - 1));
    return s == pattern || s.startsWith('$pattern ');
  }

  static bool _hit(List<String> rules, String tool, String cmd) {
    for (final r in rules) {
      if (_match(r, tool) || (cmd.isNotEmpty && _match(r, cmd))) return true;
    }
    return false;
  }

  /// 高危工具：没有 allow 记录时一律现场确认（auto 模式也不例外），
  /// 选了「始终允许」后按 allow 记录放行。
  static const Set<String> highRisk = {
    'rootShell',
    'memWrite',
    'installApk',
    'install_container',
    'runPlugin',
    'stop_tasks',
  };

  static bool isHighRisk(String tool) => highRisk.contains(tool) || tool.startsWith('root');

  /// 只读工具：规划模式下只允许这些。
  static const Set<String> readOnlyTools = {
    'readFile',
    'listFiles',
    'listApps',
    'listContainers',
    'listPlugins',
    'captureList',
    'captureLog',
    'mcpList',
    'webSearch',
    'fetchPage',
    'readConfig',
    'memoryRead',
    'memScan',
    'listSkills',
    'listSubAgents',
  };

  /// 返回 allow / deny / confirm。
  ///
  /// mode:
  /// - build（执行）：所有工具都先问
  /// - plan（规划）：只读工具直接放行，写操作直接拒结
  /// - auto（自动）：除高危外都不问
  String check(String tool, Map<String, String> args, {String mode = 'build'}) {
    final cmd = args['cmd'] ?? '';
    if (_hit(deny, tool, cmd)) return 'deny';
    if (mode == 'plan') {
      return readOnlyTools.contains(tool) ? 'allow' : 'deny';
    }
    // 高危操作没有「始终允许」记录时，不管什么模式都重新问
    if (isHighRisk(tool)) return _hit(allow, tool, cmd) ? 'allow' : 'confirm';
    if (mode == 'auto') return 'allow';
    if (_hit(confirm, tool, cmd)) return 'confirm';
    if (_hit(allow, tool, cmd)) return 'allow';
    return 'confirm';
  }

  bool allowTool(String tool, Map<String, String> args, {String mode = 'build'}) =>
      check(tool, args, mode: mode) == 'allow';

  // ---------- 持久化 ----------
  static Future<File?> _file() async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return null;
    return File('$dir/permission.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      allow
        ..clear()
        ..addAll(((m['allow'] as List?) ?? const []).map((e) => e.toString()));
      deny
        ..clear()
        ..addAll(((m['deny'] as List?) ?? const []).map((e) => e.toString()));
      confirm
        ..clear()
        ..addAll(((m['confirm'] as List?) ?? const []).map((e) => e.toString()));
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final f = await _file();
      await f?.writeAsString(jsonEncode({'allow': allow, 'deny': deny, 'confirm': confirm}));
    } catch (_) {}
  }

  /// 设置某工具的决策（allow / confirm / deny），并清理其他两类。
  Future<void> setDecision(String tool, String decision) async {
    allow.removeWhere((e) => e == tool);
    confirm.removeWhere((e) => e == tool);
    deny.removeWhere((e) => e == tool);
    if (decision == 'allow') allow.add(tool);
    if (decision == 'confirm') confirm.add(tool);
    if (decision == 'deny') deny.add(tool);
    await save();
  }
}
