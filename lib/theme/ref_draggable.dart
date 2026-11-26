import 'package:flutter/material.dart';
import '../state/chat_refs.dart';
import '../state/drawer_ctrl.dart';
import 'app_theme.dart';

/// 长按拖到对话框即可把该条目（技能/人物/应用/文件…）作为上下文交给 AI。
class RefDraggable extends StatelessWidget {
  final ChatRef ref;
  final Widget child;
  const RefDraggable({super.key, required this.ref, required this.child});

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<ChatRef>(
      data: ref,
      delay: const Duration(milliseconds: 180),
      onDragStarted: DrawerCtrl.dragStart,
      onDragUpdate: (d) => DrawerCtrl.dragUpdate(d.delta.distance),
      onDraggableCanceled: (_, __) {},
      onDragEnd: (_) {},
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 190),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.brand,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x332563EB), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.drag_indicator_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text('${ref.label}·${ref.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: child),
      child: child,
    );
  }
}

/// 左滑删除 + 长按拖动（两者不冲突）。
class RefSwipeDelete extends StatelessWidget {
  final String itemKey;
  final Future<void> Function() onDelete;
  final Widget child;
  const RefSwipeDelete({super.key, required this.itemKey, required this.onDelete, required this.child});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(itemKey),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
      ),
      child: child,
    );
  }
}
