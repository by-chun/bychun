import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 目录/选集面板：竖屏底部弹出，横屏右侧栏；带搜索与跳转。
Future<void> showCatalogSheet(
  BuildContext context, {
  required List<String> titles,
  required int current,
  required void Function(int index) onPick,
  String jumpLabel = '跳章',
  String unit = '章',
}) async {
  if (titles.isEmpty) return;
  final search = TextEditingController();
  final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
  var keyword = '';

  Widget content(StateSetter setSt) {
    final indexes = <int>[
      for (var i = 0; i < titles.length; i++)
        if (keyword.isEmpty || titles[i].toLowerCase().contains(keyword.toLowerCase())) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(children: [
            const Text('目录', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text('共 ${titles.length} $unit', style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
            const Spacer(),
            if (!landscape)
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF7886A0)),
              ),
          ]),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF141B2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1A2338)),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: search,
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '搜索$unit节 / 标题',
                  hintStyle: const TextStyle(fontSize: 10.5, color: Color(0xFF9AA4B2)),
                ),
                onChanged: (v) => setSt(() => keyword = v.trim()),
              ),
            ),
            GestureDetector(
              onTap: () async {
                final c = TextEditingController(text: '${current + 1}');
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('$jumpLabel', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    content: TextField(
                      controller: c,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: InputDecoration(hintText: '1 - ${titles.length}'),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('跳转')),
                    ],
                  ),
                );
                if (ok == true) {
                  final n = (int.tryParse(c.text.trim()) ?? 1).clamp(1, titles.length);
                  onPick(n - 1);
                  Navigator.of(context).maybePop();
                }
              },
              child: Text(jumpLabel,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.brand, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: indexes.length,
            itemBuilder: (_, k) {
              final i = indexes[k];
              final on = i == current;
              return GestureDetector(
                onTap: () {
                  onPick(i);
                  Navigator.of(context).maybePop();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: on ? const Color(0xFF1E2A45) : Colors.white,
                  child: Row(children: [
                    Container(
                      width: 26,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? AppColors.brand : const Color(0xFF1A2338),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 8.5,
                              fontFamily: 'monospace',
                              color: on ? Colors.white : const Color(0xFF7886A0))),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        titles[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: on ? const Color(0xFF1D4ED8) : const Color(0xFFAEB9CC),
                            fontWeight: on ? FontWeight.w700 : FontWeight.w400),
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  if (landscape) {
    await showDialog(
      context: context,
      barrierColor: const Color(0x330F172A),
      builder: (_) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          child: SizedBox(
            width: 320,
            height: double.infinity,
            child: SafeArea(
              child: StatefulBuilder(builder: (_, setSt) => content(setSt)),
            ),
          ),
        ),
      ),
    );
  } else {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.72,
        child: StatefulBuilder(builder: (_, setSt) => content(setSt)),
      ),
    );
  }
}
