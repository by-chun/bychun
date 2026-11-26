import 'dart:convert';
import 'dart:io';
import 'native_bridge.dart';

/// root helper：所有内存操作通过 `su -c gmem ...` 以 root 身份执行。
class Gmem {
  static String? _binPath;
  static bool _noAsset = false;

  /// 首次使用时把 assets/gmem 释放到私有目录并加可执行权限。
  static Future<String?> ensure() async {
    if (_binPath != null) return _binPath;
    try {
      // 优先：jniLibs 里的 libgmem.so（随 APK 装到 nativeLibraryDir，已可执行）
      final dir = await NativeBridge.nativeLibDir();
      if (dir != null && dir.isNotEmpty) {
        final f = File('$dir/libgmem.so');
        if (await f.exists()) {
          _binPath = f.path;
          return _binPath;
        }
      }
    } catch (_) {}
    if (_noAsset) return null;
    try {
      final dir = await NativeBridge.appDataDir();
      if (dir.isEmpty) return null;
      final dst = File('$dir/gmem');
      if (!await dst.exists() || await dst.length() < 1024) {
        final bytes = await NativeBridge.readAsset('gmem');
        if (bytes == null) {
          _noAsset = true;
          return null;
        }
        await dst.writeAsBytes(bytes);
      }
      await Process.run('chmod', ['755', dst.path]);
      _binPath = dst.path;
      return _binPath;
    } catch (_) {
      _noAsset = true;
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _run(String args) async {
    final bin = await ensure();
    if (bin == null) return null;
    final r = await NativeBridge.rootExec('"$bin" $args');
    final out = r.stdout.trim();
    if (out.isEmpty) return null;
    try {
      final line = out.split('\n').lastWhere((e) => e.trim().startsWith('{'), orElse: () => '');
      if (line.isEmpty) return null;
      return jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>?> scan(int pid, String value, {String type = 'i32', String region = 'all', int max = 200}) async {
    final r = await _run('scan $pid $type $value $max $region');
    if (r == null || r['ok'] != true) return null;
    return ((r['hits'] as List?) ?? const []).map((e) => e.toString()).toList();
  }

  static Future<String?> readHex(int pid, String addr, {int size = 4}) async {
    final r = await _run('read $pid ${addr.replaceFirst('0x', '')} $size');
    if (r == null || r['ok'] != true) return null;
    return (r['hex'] ?? '').toString();
  }

  static Future<bool> writeHex(int pid, String addr, String hex) async {
    final r = await _run('write $pid ${addr.replaceFirst('0x', '')} $hex');
    return r != null && r['ok'] == true;
  }

  static Future<List<String>?> regions(int pid) async {
    final r = await _run('regions $pid');
    if (r == null || r['ok'] != true) return null;
    return ((r['regions'] as List?) ?? const []).map((e) => e.toString()).toList();
  }

  static Future<List<String>?> threads(int pid) async {
    final r = await _run('threads $pid');
    if (r == null || r['ok'] != true) return null;
    return ((r['threads'] as List?) ?? const []).map((e) => e.toString()).toList();
  }
}
