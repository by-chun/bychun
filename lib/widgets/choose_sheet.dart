import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// AI 不确定时的选项弹层：支持单选/多选，可补充要求。
Future<void> showChooseSheet(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> options,
  bool multi = false,
  String cancel = '都别用',
  required void Function(String text) onDone,
}) async {
  final picked = <int>{};
  final extra = TextEditingController();

  void close(BuildContext ctx, String text) {
    Navigator.of(ctx).pop();
    onDone(text);
  }

  String label(int i) => '${(options[i]['title'] ?? '').toString()}';

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final maxH = MediaQuery.of(ctx).size.height * 0.72;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A3550),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Text(title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Text(multi ? '可以多选，选完点确认' : '点一项直接选，或写补充要求',
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF9AA7C0))),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final o = options[i];
                      final t = '${o['title'] ?? ''}';
                      final d = '${o['desc'] ?? ''}';
                      final on = picked.contains(i);
                      return InkWell(
                        onTap: () {
                          if (multi) {
                            setState(() {
                              if (on) {
                                picked.remove(i);
                              } else {
                                picked.add(i);
                              }
                            });
                          } else {
                            close(ctx, t);
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(13, 11, 12, 12),
                          decoration: BoxDecoration(
                            color: on ? const Color(0xFF1E2A45) : const Color(0xFF141B2E),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: on ? const Color(0xFF2A3A5E) : const Color(0xFF1A2338)),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(t,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: on ? AppColors.brand : AppColors.text,
                                    )),
                                if (d.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(d,
                                        style: const TextStyle(
                                            fontSize: 10.5, color: Color(0xFF9AA7C0), height: 1.5)),
                                  ),
                              ]),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              multi
                                  ? (on ? Icons.check_circle_rounded : Icons.circle_outlined)
                                  : Icons.chevron_right_rounded,
                              size: multi ? 18 : 18,
                              color: on ? AppColors.brand : const Color(0xFFCBD5E1),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: TextField(
                    controller: extra,
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 12),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: '补充要求'),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(14, 10, 14, 12 + MediaQuery.of(ctx).viewInsets.bottom),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => close(ctx, cancel),
                        child: const Text('取消', style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: (picked.isEmpty && extra.text.trim().isEmpty)
                            ? null
                            : () {
                                final ex = extra.text.trim();
                                final sel = picked.map(label).where((e) => e.isNotEmpty).toList();
                                final buf = <String>[];
                                if (sel.isNotEmpty) buf.add(multi ? '已选择：${sel.join('、')}' : sel.first);
                                if (ex.isNotEmpty) buf.add('补充要求：$ex');
                                close(ctx, buf.join('\n'));
                              },
                        child: Text(
                          picked.isEmpty
                              ? '只发补充'
                              : (multi ? '确认 ${picked.length} 项' : '发送'),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
