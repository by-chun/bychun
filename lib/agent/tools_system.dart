import 'dart:convert';

import '../native/native_bridge.dart';
import 'tool.dart';

/// 系统设置 / 通知 / 应用使用时长 —— 走 root shell 命令（settings / dumpsys），
/// 这些 Android API 没有对应的「无 root 可写」通道，root 下命令最稳。
void registerSystemTools(ToolRegistry reg) {
  reg.register(GetSystemSettingTool());
  reg.register(SetSystemSettingTool());
  reg.register(GetNotificationsTool());
  reg.register(GetAppUsageTool());
}

/// 读系统设置：settings get <namespace> <key>。
/// namespace: system / global / secure（secure 需要 root）。
class GetSystemSettingTool extends AgentTool {
  @override
  String get name => 'getSystemSetting';

  @override
  String get description =>
      '读一项 Android 系统设置。namespace 用 system（一般项）/ global（全局）/ secure（安全项，需 root）。'
      '常用：screen_brightness、screen_off_timeout、volume_music_speaker（system）；airplane_mode_on（global）。';

  @override
  Map<String, String> get parameters => {
        'namespace': 'system / global / secure',
        'key': '设置键名',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final ns = (args['namespace'] ?? 'system').trim();
    final key = (args['key'] ?? '').trim();
    if (key.isEmpty) return const ToolResult(false, 'key 不能为空');
    if (!['system', 'global', 'secure'].contains(ns)) {
      return const ToolResult(false, 'namespace 只能是 system/global/secure');
    }
    final r = await NativeBridge.rootExec('settings get $ns $key');
    final v = (r.stdout + r.stderr).trim();
    if (v.isEmpty || v == 'null') return ToolResult(true, '未设置（空）');
    return ToolResult(true, '$ns.$key = $v');
  }
}

/// 写系统设置：settings put <namespace> <key> <value>。
class SetSystemSettingTool extends AgentTool {
  @override
  String get name => 'setSystemSetting';

  @override
  String get description =>
      '写一项 Android 系统设置（需 root）。namespace 用 system / global / secure。'
      '会先确认值合法；写失败会带回 stderr。改音量/亮度/屏幕超时/飞行模式等都用这个。';

  @override
  Map<String, String> get parameters => {
        'namespace': 'system / global / secure',
        'key': '设置键名',
        'value': '要写入的值（数字或字符串）',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final ns = (args['namespace'] ?? 'system').trim();
    final key = (args['key'] ?? '').trim();
    final value = (args['value'] ?? '').trim();
    if (key.isEmpty || value.isEmpty) return const ToolResult(false, 'key 和 value 不能为空');
    if (!['system', 'global', 'secure'].contains(ns)) {
      return const ToolResult(false, 'namespace 只能是 system/global/secure');
    }
    final r = await NativeBridge.rootExec('settings put $ns $key "$value"');
    if (r.code != 0) return ToolResult(false, '写入失败：${r.stderr.trim()}');
    return ToolResult(true, '已设置 $ns.$key = $value');
  }
}

/// 读通知：dumpsys notification --noredact（root 下能拿到不脱敏的文本）。
class GetNotificationsTool extends AgentTool {
  @override
  String get name => 'getNotifications';

  @override
  String get description =>
      '读取当前通知栏里的通知（标题、正文、来源应用）。需 root，用 dumpsys notification 解析。'
      '返回可见的活跃通知列表；读不到就是没有通知或需要通知读取权限。';

  @override
  Map<String, String> get parameters => {'limit': '最多返回几条，默认 20'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final limit = int.tryParse(args['limit'] ?? '') ?? 20;
    final r = await NativeBridge.rootExec('dumpsys notification --noredact');
    final text = r.stdout.isNotEmpty ? r.stdout : r.stderr;
    if (text.trim().isEmpty) return const ToolResult(false, '读不到通知（可能无通知或 root 不可用）');

    // 解析：NotificationRecord 0x... pkg=xxx user=xxx 之后跟标题/正文行
    final out = <Map<String, String>>[];
    final lines = text.split('\n');
    var cur = <String, String>{};
    for (final line in lines) {
      final m = RegExp(r'pkg=(\S+)\s+user=').firstMatch(line);
      if (m != null) {
        if (cur.isNotEmpty && out.length < limit) out.add(cur);
        cur = {'pkg': m.group(1)!};
      } else if (cur.containsKey('pkg')) {
        final t = line.trim();
        if (t.isNotEmpty && !t.startsWith('NotificationRecord') && !t.contains('=')) {
          if (cur['title'] == null && !t.startsWith('android.')) cur['title'] = t;
          else if (cur['body'] == null && cur['title'] != null) cur['body'] = t;
        }
      }
      if (out.length >= limit) break;
    }
    if (cur.isNotEmpty && out.length < limit) out.add(cur);
    if (out.isEmpty) return const ToolResult(true, '当前没有活跃通知');

    return ToolResult(
      true,
      '共 ${out.length} 条通知',
      view: 'list',
      title: '通知栏',
      viewData: {
        'items': [
          for (final n in out)
            {
              'title': (n['title'] ?? '').toString(),
              'subtitle': (n['body'] ?? '').toString(),
              'badge': (n['pkg'] ?? '').toString(),
            }
        ],
      },
    );
  }
}

/// 应用使用时长：dumpsys usagestats。
class GetAppUsageTool extends AgentTool {
  @override
  String get name => 'getAppUsage';

  @override
  String get description =>
      '查应用使用时长/次数（最近一段时间）。需 root 或已授权「使用情况访问权限」。'
      'package 可留空看全部，或给包名看单个。';

  @override
  Map<String, String> get parameters => {
        'package': '包名（可留空）',
        'days': '看最近几天，默认 1',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final pkg = (args['package'] ?? '').trim();
    final r = await NativeBridge.rootExec('dumpsys usagestats');
    final text = r.stdout.isNotEmpty ? r.stdout : r.stderr;
    if (text.trim().isEmpty) return const ToolResult(false, '读不到使用统计（需 root 或使用情况访问权限）');

    // 解析包名 + 时长块。每个包一段 "Package: com.xxx"，下面有 "totalTimeUsed=..." 
    final out = <Map<String, String>>[];
    final blocks = text.split(RegExp(r'Package:\s+'));
    for (final b in blocks.skip(1)) {
      final name = b.split('\n').first.trim();
      if (pkg.isNotEmpty && name != pkg) continue;
      final tt = RegExp(r'totalTimeUsed=([0-9]+)').firstMatch(b);
      final tc = RegExp(r'timesUsed=([0-9]+)').firstMatch(b);
      final secs = int.tryParse(tt?.group(1) ?? '') ?? 0;
      final cnt = int.tryParse(tc?.group(1) ?? '') ?? 0;
      if (secs == 0 && cnt == 0) continue;
      out.add({
        'pkg': name,
        'time': secs >= 3600
            ? '${(secs / 3600).toStringAsFixed(1)}h'
            : '${(secs / 60).toStringAsFixed(0)}m',
        'count': '$cnt 次',
      });
      if (out.length >= 30) break;
    }
    if (out.isEmpty) return const ToolResult(true, '没有找到${pkg.isEmpty ? '' : ' $pkg '}的使用记录');

    return ToolResult(
      true,
      '共 ${out.length} 个应用',
      view: 'list',
      title: '应用使用时长',
      viewData: {
        'items': [
          for (final a in out)
            {'title': a['pkg'], 'subtitle': '${a['time']} · ${a['count']}', 'badge': a['time']}
        ],
      },
    );
  }
}
