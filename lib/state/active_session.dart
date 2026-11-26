import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../native/native_bridge.dart';

/// 主页正在显示的会话 id（null = 新对话）。
///
/// 会持久化到 filesDir/last_session，下次启动由 main() 预先读出来交给 [seed]，
/// 这样关掉 App 再打开还能回到上次那个会话。
class ActiveSessionNotifier extends Notifier<int?> {
  static int? _seed;

  /// 启动时由 main() 调用，注入上次打开的会话 id。
  static void seed(int? id) => _seed = id;

  @override
  int? build() => _seed;

  void open(int id) {
    state = id;
    NativeBridge.writeAppFile('last_session', '$id');
  }

  void reset() {
    state = null;
    NativeBridge.writeAppFile('last_session', '');
  }
}

final activeSessionProvider = NotifierProvider<ActiveSessionNotifier, int?>(ActiveSessionNotifier.new);
