import 'package:flutter/foundation.dart';

/// 让抽屉内部的页面（设置等）也能开关外层抽屉；并统一“拖出一定距离才收起”的判定。
class DrawerCtrl {
  static void Function()? close;
  static void Function()? open;

  /// 请求打开抽屉时直接展开的节点 key（如 `set:compact`）。
  static final ValueNotifier<String?> openNode = ValueNotifier<String?>(null);

  static double _dist = 0;
  static bool _closed = false;

  static void closeDrawer() => close?.call();

  /// 打开外层树状抽屉（聊天页快捷动作等入口用）。
  static void openDrawer() => open?.call();

  /// 打开抽屉并展开到设置里的某个节点。
  static void openSetting(String key) {
    openNode.value = 'set:$key';
    open?.call();
  }

  static void dragStart() {
    _dist = 0;
    _closed = false;
  }

  /// 累计拖动距离，超过 [threshold] 时关闭抽屉（只关一次）。
  static void dragUpdate(double delta, {double threshold = 70}) {
    if (_closed) return;
    _dist += delta;
    if (_dist > threshold) {
      _closed = true;
      close?.call();
    }
  }
}
