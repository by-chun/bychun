import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../theme/ref_draggable.dart';
import '../theme/glass_dialog.dart';
import '../state/chat_refs.dart';
import '../state/agent_controller.dart';

class MemoriesPage extends ConsumerStatefulWidget {
  const MemoriesPage({super.key});
  @override
  ConsumerState<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends ConsumerState<MemoriesPage> {
  Map<String, String> _items = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = ref.read(agentEngineProvider).memory;
    await m.load();
    if (mounted) setState(() => _items = Map.of(m.all));
  }

  Future<void> _add() async {
    final k = TextEditingController();
    final v = TextEditingController();
    final ok = await showGlassDialog<bool>(
      context: context,
      title: '添加记忆',
      confirmText: '保存',
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: k, decoration: const InputDecoration(labelText: '标题')),
        const SizedBox(height: 8),
        TextField(controller: v, maxLines: 3, decoration: const InputDecoration(labelText: '内容')),
      ]),
    );
    if (ok == true && k.text.trim().isNotEmpty) {
      ref.read(agentEngineProvider).memory.set(k.text.trim(), v.text.trim());
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('记忆', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: _add, icon: const Icon(Icons.add_rounded, color: Color(0xFFD4DBE8))),
        ],
      ),
      body: _items.isEmpty
          ? const EmptyState(icon: Icons.bookmark_outline_rounded, text: '还没有记忆\n点右上角 ＋ 添加，或让 AI 记住')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final e in _items.entries)
                  RefSwipeDelete(
                    itemKey: 'mem-${e.key}',
                    onDelete: () async {
                      ref.read(agentEngineProvider).memory.remove(e.key);
                      await _load();
                    },
                    child: GlassCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: RefDraggable(
                        ref: ChatRef(type: 'file', name: e.key, detail: e.value),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              if (e.value.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(e.value, maxLines: 3, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5)),
                                ),
                            ]),
                          ),
                          Transform.scale(
                            scale: 0.72,
                            child: Switch(
                              value: ref.read(agentEngineProvider).memory.isEnabled(e.key),
                              activeThumbColor: AppColors.brand,
                              onChanged: (v) async {
                                await ref.read(agentEngineProvider).memory.setEnabled(e.key, v);
                                await _load();
                              },
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('左滑删除 · 长按可拖到对话框', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
                ),
              ],
            ),
    );
  }
}
