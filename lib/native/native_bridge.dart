import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class ExecResult {
  final String stdout;
  final String stderr;
  final int code;
  final bool timeout;

  const ExecResult(this.stdout, this.stderr, this.code, this.timeout);

  bool get ok => code == 0 && !timeout;
}

/// Dart ↔ Kotlin 原生桥。
class NativeBridge {
  static const MethodChannel _ch = MethodChannel('com.chun.by/native');

  static Future<ExecResult> exec(String cmd, {int timeout = 15}) async {
    try {
      final r = await _ch.invokeMethod<Map>('exec', {'cmd': cmd, 'timeout': timeout});
      if (r == null) return const ExecResult('', 'no result', -1, false);
      return ExecResult(
        (r['stdout'] ?? '').toString(),
        (r['stderr'] ?? '').toString(),
        (r['code'] ?? -1) as int,
        (r['timeout'] ?? false) == true,
      );
    } on MissingPluginException {
      return const ExecResult('', '原生通道不可用（非 Android 平台）', -1, false);
    } catch (e) {
      return ExecResult('', e.toString(), -1, false);
    }
  }

  /// 写文件到容器根（path 以 / 开头，如 /root/x.py）。
  static Future<bool> prootWriteFile(String path, String content) async {
    try {
      final r = await _ch.invokeMethod<bool>('containerWrite', {'path': path, 'content': content});
      return r == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> writeAppFile(String name, String content) async {
    try {
      return await _ch.invokeMethod<bool>('writeAppFile', {'name': name, 'content': content}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> readAppFile(String name) async {
    try {
      return await _ch.invokeMethod<String>('readAppFile', {'name': name});
    } catch (_) {
      return null;
    }
  }

  static Future<String?> listAppDir(String name) async {
    try {
      return await _ch.invokeMethod<String>('listAppDir', {'name': name});
    } catch (_) {
      return null;
    }
  }

  static Future<String?> captureLog(int limit) async {
    try {
      return await _ch.invokeMethod<String>('captureLog', {'limit': limit});
    } catch (_) {
      return null;
    }
  }

  static Future<bool> captureClear() async {
    try {
      return await _ch.invokeMethod<bool>('captureClear') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> runJavaPlugin(String dex, String className) async {
    try {
      return await _ch.invokeMethod<String>('runJavaOverlay', {'dex': dex, 'className': className}) ??
          'no result';
    } catch (e) {
      return '通道异常：$e';
    }
  }

  static Future<bool> showLogWindow({String title = '实时输出'}) async {
    try {
      return await _ch.invokeMethod<bool>('logShow', {'title': title}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> pushLogLine(String line) async {
    try {
      await _ch.invokeMethod<bool>('logLine', {'line': line});
    } catch (_) {}
  }

  static Future<void> hideLogWindow() async {
    try {
      await _ch.invokeMethod<bool>('logHide');
    } catch (_) {}
  }

  /// 急停：杀掉所有正在跑的容器进程。
  static Future<void> killAllProcs() async {
    try {
      await _ch.invokeMethod<bool>('killAllProcs');
    } catch (_) {}
  }

  /// 杀掉正在流式执行的容器命令。
  static Future<void> killStream(String tag) async {
    try {
      await _ch.invokeMethod<bool>('killStream', {'tag': tag});
    } catch (_) {}
  }

  static const _streamCh = EventChannel('rowan/stream');

  /// 容器命令的实时输出（tag 用于区分多个任务）。
  static Stream<Map<String, dynamic>> get outputStream =>
      _streamCh.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));

  /// 流式执行容器命令；返回退出码。
  static Future<int> streamExec(String cmd, {String tag = 'stream'}) async {
    try {
      return await _ch.invokeMethod<int>('streamExec', {'cmd': cmd, 'tag': tag}) ?? -1;
    } catch (e) {
      return -1;
    }
  }

  static Future<bool> exportJson(String name, String content) async {
    try {
      return await _ch.invokeMethod<bool>('exportJson', {'name': name, 'content': content}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> pickTextFile() async {
    try {
      return await _ch.invokeMethod<String>('pickTextFile');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setOverlayHtml(String html) async {
    try {
      return await _ch.invokeMethod<bool>('overlayHtml', {'html': html}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<ExecResult> prootExec(String cmd) async {
    try {
      final r = await _ch.invokeMethod<Map>('prootExec', {'cmd': cmd});
      if (r == null) return const ExecResult('', 'no result', -1, false);
      return ExecResult(
        (r['stdout'] ?? '').toString(),
        (r['stderr'] ?? '').toString(),
        (r['code'] ?? -1) as int,
        (r['timeout'] ?? false) == true,
      );
    } catch (e) {
      return ExecResult('', e.toString(), -1, false);
    }
  }

  static Future<String> home() async {
    try {
      return await _ch.invokeMethod<String>('home') ?? '/';
    } catch (_) {
      return '/';
    }
  }

  static Future<bool> showOverlay() async {
    try {
      return await _ch.invokeMethod<bool>('showOverlay') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hideOverlay() async {
    try {
      return await _ch.invokeMethod<bool>('hideOverlay') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> prootReady() async {
    try {
      return await _ch.invokeMethod<bool>('prootReady') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<ExecResult> rootExec(String cmd, {int timeout = 60}) async {
    try {
      final r = await _ch.invokeMethod<Map>('rootExec', {'cmd': cmd, 'timeout': timeout});
      if (r == null) return const ExecResult('', 'no result', -1, false);
      return ExecResult(
        (r['stdout'] ?? '').toString(),
        (r['stderr'] ?? '').toString(),
        (r['code'] ?? -1) as int,
        (r['timeout'] ?? false) == true,
      );
    } on MissingPluginException {
      return const ExecResult('', '原生通道不可用', -1, false);
    } catch (e) {
      return ExecResult('', e.toString(), -1, false);
    }
  }

  /// 无障碍读屏：dump 当前屏幕控件（text/desc/坐标/可点击…）。未开启返回空。
  static Future<List<Map<String, dynamic>>> screenDump() async {
    try {
      final r = await _ch.invokeMethod<List>('screenDump');
      return (r ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 无障碍截图，返回 PNG 字节；失败回退 root screencap。不落盘。
  static Future<Uint8List?> screenShot() async {
    try {
      return await _ch.invokeMethod<Uint8List>('screenShot');
    } catch (_) {
      return null;
    }
  }

  /// 无障碍是否已开启。
  static Future<bool> screenEnabled() async {
    try {
      return await _ch.invokeMethod<bool>('screenEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 打开系统无障碍设置。
  static Future<void> screenOpenSettings() async {
    try {
      await _ch.invokeMethod('screenOpenSettings');
    } catch (_) {}
  }

  static Future<bool> screenTap(int x, int y) async {
    try {
      return await _ch.invokeMethod<bool>('screenTap', {'x': x, 'y': y}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> screenSwipe(int x1, int y1, int x2, int y2, {int ms = 300}) async {
    try {
      return await _ch.invokeMethod<bool>(
              'screenSwipe', {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'ms': ms}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> screenType(String text) async {
    try {
      return await _ch.invokeMethod<bool>('screenType', {'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// MediaProjection 截图（Android 全版本可用，首次会弹录屏授权框）。返回 PNG 字节，不落盘。
  static Future<Uint8List?> projectShot() async {
    try {
      return await _ch.invokeMethod<Uint8List>('projectShot');
    } catch (_) {
      return null;
    }
  }

  /// 开始录屏（MediaProjection），返回 MP4 路径（录制中）。
  static Future<String?> recordStart() async {
    try {
      return await _ch.invokeMethod<String>('recordStart');
    } catch (_) {
      return null;
    }
  }

  /// 停止录屏，返回 MP4 路径。
  static Future<String?> recordStop() async {
    try {
      return await _ch.invokeMethod<String>('recordStop');
    } catch (_) {
      return null;
    }
  }

  static Future<String> appDataDir() async {
    try {
      return await _ch.invokeMethod<String>('appDataDir') ?? '';    } catch (_) {
      return '';
    }
  }

  static Future<bool> prootPrepare() async {
    try {
      return await _ch.invokeMethod<bool>('prootPrepare') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 开启 DNS 抓包（VpnService）；首次会弹系统 VPN 授权。
  /// 返回 {ok, running, dns, auto, needDns}；needDns=true 表示系统 DNS 取不到，需要用户手填。
  static Future<Map<String, dynamic>> vpnStart() async {
    try {
      final r = await _ch.invokeMethod<Map>('vpnStart');
      return r == null ? <String, dynamic>{} : Map<String, dynamic>.from(r);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 抓包状态：{running, dns, auto, needDns}
  static Future<Map<String, dynamic>> vpnStatus() async {
    try {
      final r = await _ch.invokeMethod<Map>('vpnStatus');
      return r == null ? <String, dynamic>{} : Map<String, dynamic>.from(r);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 手动设置上游 DNS（写入后会重启 VPN）。
  static Future<bool> vpnSetDns(String dns) async {
    try {
      final r = await _ch.invokeMethod<Map>('vpnSetDns', {'dns': dns});
      return r != null && r['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> vpnStop() async {
    try {
      return await _ch.invokeMethod<bool>('vpnStop') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 抓包日志：每行 "时间戳 域名 -> ip1,ip2"。
  static Future<String> vpnLog() async {
    try {
      return await _ch.invokeMethod<String>('vpnLog') ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<bool> vpnClear() async {
    try {
      return await _ch.invokeMethod<bool>('vpnClear') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 生成并安装自签 CA 到系统信任区（需 root），返回 {ok, log}。
  static Future<Map<String, dynamic>> caInstall() async {
    try {
      final r = await _ch.invokeMethod<Map>('caInstall');
      return Map<String, dynamic>.from(r ?? {});
    } catch (e) {
      return {'ok': false, 'log': e.toString()};
    }
  }

  /// 当前 CA 信息：{hash, pem}。
  static Future<Map<String, dynamic>> caStatus() async {
    try {
      final r = await _ch.invokeMethod<Map>('caStatus');
      return Map<String, dynamic>.from(r ?? {});
    } catch (e) {
      return {'hash': '', 'pem': ''};
    }
  }

  /// 已安装的容器环境：[{name, ready, size}]。
  static Future<List<Map<String, dynamic>>> envList() async {
    try {
      final r = await _ch.invokeMethod<List>('envList');
      return (r ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 从 URL 安装容器，返回 {ok, log}。
  static Future<Map<String, dynamic>> envInstallUrl(String url, String name) async {
    try {
      final r = await _ch.invokeMethod<Map>('envInstallUrl', {'url': url, 'name': name});
      return Map<String, dynamic>.from(r ?? {});
    } catch (e) {
      return {'ok': false, 'log': e.toString()};
    }
  }

  static Future<String> envCurrent() async {
    try {
      return await _ch.invokeMethod<String>('envCurrent') ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<bool> envSet(String env) async {
    try {
      return await _ch.invokeMethod<bool>('envSet', {'env': env}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> envRemove(String env) async {
    try {
      return await _ch.invokeMethod<bool>('envRemove', {'env': env}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 导入本地 tar/tar.gz，返回 {ok, log}。
  static Future<Map<String, dynamic>> envImport(String path, String env) async {
    try {
      final r = await _ch.invokeMethod<Map>('envImport', {'path': path, 'env': env});
      return Map<String, dynamic>.from(r ?? {});
    } catch (e) {
      return {'ok': false, 'log': e.toString()};
    }
  }



  static Future<bool> requestPermissions() async {
    try {
      return await _ch.invokeMethod<bool>('requestPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<int> ptyOpen([String shell = '/system/bin/sh']) async {
    try {
      return await _ch.invokeMethod<int>('ptyOpen', {'shell': shell}) ?? -1;
    } catch (_) {
      return -1;
    }
  }

  static Future<void> ptyWrite(int fd, List<int> data) async {
    try {
      await _ch.invokeMethod<int>('ptyWrite', {'fd': fd, 'data': data});
    } catch (_) {}
  }

  static Future<List<int>?> ptyRead(int fd, {int size = 4096}) async {
    try {
      return await _ch.invokeMethod<List<int>>('ptyRead', {'fd': fd, 'size': size});
    } catch (_) {
      return null;
    }
  }

  static Future<void> ptyClose(int fd) async {
    try {
      await _ch.invokeMethod<bool>('ptyClose', {'fd': fd});
    } catch (_) {}
  }

  /// 已安装应用列表（label/package/apk/size/system）。
  static Future<List<Map<String, dynamic>>> listApps() async {
    try {
      final r = await _ch.invokeMethod<List>('listApps');
      return (r ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 列出 APK（zip）内所有条目（name/size/dir）。
  static Future<List<Map<String, dynamic>>> zipList(String path) async {
    try {
      final r = await _ch.invokeMethod<List>('zipList', {'path': path});
      return (r ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 读取 APK（zip）内某个条目内容（最多 max 字节）。
  static Future<Uint8List?> zipRead(String path, String entry, {int max = 1048576}) async {
    try {
      return await _ch.invokeMethod<Uint8List>('zipRead', {'path': path, 'entry': entry, 'max': max});
    } catch (_) {
      return null;
    }
  }

  // ——— 内存工具（需 NDK 编 libmemory.so）———
  static Future<bool> memoryAvailable() async {
    try { return await _ch.invokeMethod<bool>('memoryAvailable') ?? false; } catch (_) { return false; }
  }

  static Future<Uint8List?> memoryRead(int pid, int addr, {int size = 256}) async {
    try { return await _ch.invokeMethod<Uint8List>('memoryRead', {'pid': pid, 'addr': addr, 'size': size}); } catch (_) { return null; }
  }

  static Future<bool> memoryWrite(int pid, int addr, List<int> data) async {
    try { return await _ch.invokeMethod<bool>('memoryWrite', {'pid': pid, 'addr': addr, 'data': data}) ?? false; } catch (_) { return false; }
  }

  static Future<List<int>> memoryScan(int pid, int value) async {
    try {
      final r = await _ch.invokeMethod<List>('memoryScan', {'pid': pid, 'value': value});
      return (r ?? []).map((e) => (e as num).toInt()).toList();
    } catch (_) { return []; }
  }

  static Future<List<int>> memoryPointerScan(int pid, int target) async {
    try {
      final r = await _ch.invokeMethod<List>('memoryPointerScan', {'pid': pid, 'target': target});
      return (r ?? []).map((e) => (e as num).toInt()).toList();
    } catch (_) { return []; }
  }

  static Future<bool> memoryPatch(int pid, int addr, List<int> data) async {
    try { return await _ch.invokeMethod<bool>('memoryPatch', {'pid': pid, 'addr': addr, 'data': data}) ?? false; } catch (_) { return false; }
  }

  static Future<bool> openOverlaySettings() async {
    try { return await _ch.invokeMethod<bool>('openOverlaySettings') ?? false; } catch (_) { return false; }
  }

  static Future<Map<String, bool>> permStatus() async {
    try {
      final r = await _ch.invokeMethod<Map>('permStatus');
      return {
        'overlay': r?['overlay'] == true,
        'storage': r?['storage'] == true,
        'allFiles': r?['allFiles'] == true,
        'notification': r?['notification'] == true,
        'root': r?['root'] == true,
        'installPackages': r?['installPackages'] == true,
        'battery': r?['battery'] == true,
        'usageStats': r?['usageStats'] == true,
        'mediaImages': r?['mediaImages'] == true,
        'mediaVideo': r?['mediaVideo'] == true,
        'mediaAudio': r?['mediaAudio'] == true,
        'shizuku': r?['shizuku'] == true,
        'vpn': r?['vpn'] == true,
      };
    } catch (_) { return {}; }
  }

  /// 打开系统权限设置：unknownSources / battery / usage / overlay / appDetails / vpn
  static Future<bool> openSettings(String kind) async {
    try {
      final r = await _ch.invokeMethod<bool>('openSettings', {'kind': kind});
      return r == true;
    } catch (_) { return false; }
  }

  /// 请求图片/视频/音频读取权限。
  static Future<bool> requestMedia() async {
    try {
      final r = await _ch.invokeMethod<bool>('requestMedia');
      return r == true;
    } catch (_) { return false; }
  }

  /// 把内置的 Zygisk Frida 模块 zip 交给 Magisk 安装（需 root + 内置 assets/rowan-module.zip）。
  static Future<Map<String, dynamic>> installFridaModule({String manager = 'auto'}) async {
    try {
      final r = await _ch.invokeMethod<Map>('installFridaModule', {'manager': manager});
      return {'ok': r?['ok'] == true, 'msg': (r?['msg'] ?? '').toString()};
    } catch (e) {
      return {'ok': false, 'msg': e.toString()};
    }
  }

  /// 打开独立终端窗口（原生 Activity，避免 platform view 崩溃）。
  static Future<void> openTerminal() async {
    try { await _ch.invokeMethod('openTerminal'); } catch (_) {}
  }

  /// 按需申请存储/媒体权限（未授予时系统会弹窗，已授予则立即返回）。
  static Future<void> requestStorage() async {
    try {
      await _ch.invokeMethod('requestPermissions');
    } catch (_) {}
  }

  /// 申请悬浮窗权限（跳系统设置页）。
  static Future<void> requestOverlay() async {
    try {
      await _ch.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  /// 汇编一行代码 → 机器码（hex，失败返 null）。
  static Future<Map<String, dynamic>?> assembleHex(String asm, {String addr = '0', String arch = 'arm64'}) async {
    try {
      final s = await _ch.invokeMethod<String>('assemble', {'asm': asm, 'addr': addr, 'arch': arch});
      if (s == null) return null;
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 反汇编本地 .so 里的某个虚拟地址（返回 JSON）。
  static Future<String?> disasmFile(String path, String vaddr, {int count = 200}) async {
    try {
      return await _ch.invokeMethod<String>('disasm', {'path': path, 'vaddr': vaddr, 'count': count});
    } catch (_) {
      return null;
    }
  }

  /// 原生库目录（nativeLibraryDir）。
  static Future<String?> nativeLibDir() async {
    try {
      return await _ch.invokeMethod<String>('nativeLibDir');
    } catch (_) {
      return null;
    }
  }

  /// 打开模块 WebUI（内置 WebView + root 桥）。
  static Future<void> openModuleWebUi() async {
    try { await _ch.invokeMethod('openModuleWebUi'); } catch (_) {}
  }

  /// 安装 APK（通过 root 的 pm install）。
  static Future<Map<String, dynamic>> installApk(String path) async {
    try {
      final r = await _ch.invokeMethod<Map>('installApk', {'path': path});
      return {'ok': r?['ok'] == true, 'msg': (r?['msg'] ?? '').toString()};
    } catch (e) {
      return {'ok': false, 'msg': e.toString()};
    }
  }

  /// 读取内置 assets 二进制（如 gmem）。
  static Future<Uint8List?> readAsset(String name) async {
    try {
      return await _ch.invokeMethod<Uint8List>('readAsset', {'name': name});
    } catch (_) {
      return null;
    }
  }

  /// 用系统字符集解码字节（支持 GBK/GB2312 等 Dart 没有的编码）。
  static Future<String?> decodeText(List<int> bytes, String charset) async {
    try {
      return await _ch.invokeMethod<String>('decodeText', {
        'bytes': Uint8List.fromList(bytes),
        'charset': charset,
      });
    } catch (_) {
      return null;
    }
  }

  /// 系统文件选择器（ACTION_GET_CONTENT），返回复制到应用目录后的真实路径。
  static Future<String?> pickFile() async {
    try {
      return await _ch.invokeMethod<String>('pickFile');
    } catch (_) {
      return null;
    }
  }

  /// 悬浮球大小/透明度 → 原生立即生效并持久化。
  static Future<void> setOverlayPref({required int size, required double opacity}) async {
    try {
      await _ch.invokeMethod('setOverlayPref', {'size': size, 'opacity': opacity});
    } catch (_) {}
  }

  /// 向当前终端会话写入原始按键（ESC/方向/字符等）。
  static Future<bool> termKey(String data) async {
    try { return await _ch.invokeMethod<bool>('termKey', {'data': data}) ?? false; } catch (_) { return false; }
  }

  static Future<bool> overlayResults(List<String> list) async {
    try { return await _ch.invokeMethod<bool>('overlayResults', {'list': list}) ?? false; } catch (_) { return false; }
  }

  static Future<bool> rootCheck() async {
    try { return await _ch.invokeMethod<bool>('rootCheck') ?? false; } catch (_) { return false; }
  }

  static Future<bool> shizukuAvailable() async { try { return await _ch.invokeMethod<bool>('shizukuAvailable') ?? false; } catch (_) { return false; } }
  static Future<bool> shizukuPermission() async { try { return await _ch.invokeMethod<bool>('shizukuPermission') ?? false; } catch (_) { return false; } }
  static Future<void> shizukuRequest() async { try { await _ch.invokeMethod<bool>('shizukuRequest'); } catch (_) {} }
  static Future<ExecResult> shizukuExec(String cmd) async {
    try {
      final r = await _ch.invokeMethod<Map>('shizukuExec', {'cmd': cmd});
      if (r == null) return const ExecResult('', 'no result', -1, false);
      return ExecResult((r['stdout'] ?? '').toString(), (r['stderr'] ?? '').toString(), (r['code'] ?? -1) as int, (r['timeout'] ?? false) == true);
    } catch (e) { return ExecResult('', e.toString(), -1, false); }
  }

  // ---------------- AI 对话悬浮窗 ----------------

  static void Function(String type, String data)? _chatOverlayHandler;

  /// 浮窗里的发送/停止事件（type = send / stop，data = 文本）。
  static void setChatOverlayHandler(void Function(String type, String data) h) {
    _chatOverlayHandler = h;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'chatOverlayEvent') {
        final args = (call.arguments as Map?) ?? const {};
        _chatOverlayHandler?.call(
          (args['type'] ?? '').toString(),
          (args['data'] ?? '').toString(),
        );
      }
      return null;
    });
  }

  static Future<void> chatOverlayShow() async {
    try { await _ch.invokeMethod<bool>('chatOverlayShow'); } catch (_) {}
  }

  /// 显示悬浮窗并把主界面最小化（转到后台）。
  static Future<void> chatOverlayMinimize() async {
    try { await _ch.invokeMethod<bool>('chatOverlayMinimize'); } catch (_) {}
  }

  static Future<void> chatOverlayHide() async {
    try { await _ch.invokeMethod<bool>('chatOverlayHide'); } catch (_) {}
  }

  static Future<void> chatOverlayState(String text) async {
    try { await _ch.invokeMethod<bool>('chatOverlayState', {'text': text}); } catch (_) {}
  }

  static Future<void> chatOverlayPush(String role, String text) async {
    try { await _ch.invokeMethod<bool>('chatOverlayPush', {'role': role, 'text': text}); } catch (_) {}
  }

  // ================= 定位 =================
  static Future<Map<String, dynamic>> getLocation() async {
    try {
      final r = await _ch.invokeMethod<Map>('getLocation');
      return Map<String, dynamic>.from(r ?? {'ok': false, 'error': '调用失败'});
    } catch (e) { return {'ok': false, 'error': '$e'}; }
  }

  // ================= 蓝牙 =================
  static Future<Map<String, dynamic>> bluetoothState() async {
    try { final r = await _ch.invokeMethod<Map>('bluetoothState'); return Map<String, dynamic>.from(r ?? {'ok': false}); }
    catch (_) { return {'ok': false}; }
  }
  static Future<Map<String, dynamic>> bluetoothScan(int seconds) async {
    try { final r = await _ch.invokeMethod<Map>('bluetoothScan', {'seconds': seconds}); return Map<String, dynamic>.from(r ?? {'ok': false}); }
    catch (_) { return {'ok': false}; }
  }
  static Future<Map<String, dynamic>> bluetoothConnect(String address) async {
    try { final r = await _ch.invokeMethod<Map>('bluetoothConnect', {'address': address}); return Map<String, dynamic>.from(r ?? {'ok': false}); }
    catch (_) { return {'ok': false}; }
  }
  static Future<Map<String, dynamic>> bluetoothRead(String address, String? service, String char) async {
    try { final r = await _ch.invokeMethod<Map>('bluetoothRead', {'address': address, 'service': service ?? '', 'char': char}); return Map<String, dynamic>.from(r ?? {'ok': false}); }
    catch (_) { return {'ok': false}; }
  }
  static Future<Map<String, dynamic>> bluetoothWrite(String address, String? service, String char, String base64, {bool wait = true}) async {
    try { final r = await _ch.invokeMethod<Map>('bluetoothWrite', {'address': address, 'service': service ?? '', 'char': char, 'data': base64, 'wait': wait}); return Map<String, dynamic>.from(r ?? {'ok': false}); }
    catch (_) { return {'ok': false}; }
  }
  static Future<Map<String, dynamic>> bluetoothSubscribe(String address, String? service, String char, int seconds) async {
    try { final r = await _ch.invokeMethod<Map>('bluetoothSubscribe', {'address': address, 'service': service ?? '', 'char': char, 'seconds': seconds}); return Map<String, dynamic>.from(r ?? {'ok': false}); }
    catch (_) { return {'ok': false}; }
  }
  static Future<Map<String, dynamic>> bluetoothDisconnect(String address) async {
    try { final r = await _ch.invokeMethod<Map>('bluetoothDisconnect', {'address': address}); return Map<String, dynamic>.from(r ?? {'ok': true}); }
    catch (_) { return {'ok': true}; }
  }

  // ================= 浏览器 =================
  static Future<bool> browserOpen(String url) async {
    try { return await _ch.invokeMethod<bool>('browserOpen', {'url': url}) ?? false; } catch (_) { return false; }
  }
  static Future<bool> browserNavigate(String url) async {
    try { return await _ch.invokeMethod<bool>('browserNavigate', {'url': url}) ?? false; } catch (_) { return false; }
  }
  static Future<String> browserExecJs(String js) async {
    try { return await _ch.invokeMethod<String>('browserExecJs', {'js': js}) ?? ''; } catch (_) { return ''; }
  }
  static Future<String> browserSnapshot({int max = 4000}) async {
    try { return await _ch.invokeMethod<String>('browserSnapshot', {'max': max}) ?? ''; } catch (_) { return ''; }
  }
  static Future<String> browserTitle() async {
    try { return await _ch.invokeMethod<String>('browserTitle') ?? ''; } catch (_) { return ''; }
  }
  static Future<bool> browserClose() async {
    try { return await _ch.invokeMethod<bool>('browserClose') ?? false; } catch (_) { return false; }
  }
}
