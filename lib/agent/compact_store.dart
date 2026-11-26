import 'dart:convert';
import 'dart:io';
import '../native/native_bridge.dart';

/// 上下文压缩参数：触发阈值（token 估算）与保留最近条数。
class CompactConfig {
  int threshold;
  int keep;
  int maxTurns;
  bool enabled;
  CompactConfig({this.threshold = 60000, this.keep = 6, this.maxTurns = 30, this.enabled = true});

  Map<String, dynamic> toJson() =>
      {'threshold': threshold, 'keep': keep, 'maxTurns': maxTurns, 'enabled': enabled};
  factory CompactConfig.fromJson(Map<String, dynamic> m) => CompactConfig(
        threshold: (m['threshold'] as num?)?.toInt() ?? 60000,
        keep: (m['keep'] as num?)?.toInt() ?? 6,
        maxTurns: (m['maxTurns'] as num?)?.toInt() ?? 30,
        enabled: m['enabled'] != false,
      );
}

class CompactStore {
  static Future<File?> _file() async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return null;
    return File('$dir/compact.json');
  }

  static Future<CompactConfig> load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return CompactConfig();
      return CompactConfig.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return CompactConfig();
    }
  }

  static Future<void> save(CompactConfig c) async {
    try {
      final f = await _file();
      await f?.writeAsString(jsonEncode(c.toJson()));
    } catch (_) {}
  }
}
