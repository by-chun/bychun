import 'dart:async';

/// 一次待确认的工具调用。
class PendingPermission {
  final String tool;
  final Map<String, String> args;
  final Completer<String> completer = Completer<String>(); // once / always / deny
  PendingPermission(this.tool, this.args);

  void resolve(String choice) {
    if (!completer.isCompleted) completer.complete(choice);
  }
}
