import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db_provider.dart';
import '../data/app_db.dart';
import '../theme/app_theme.dart';
import '../theme/glass_kit.dart';
import '../theme/toast.dart';
import '../agent/provider_store.dart';
import '../agent/persona.dart';
import '../pages/settings_page.dart' show embedShell;

/// 群成员 = 供应商配置（选一个）+ 可选人物 + 角色提示词 + 气泡颜色。
/// 旁边开关控制是否参与群聊。
class GroupMembersPage extends ConsumerStatefulWidget {
  final bool embedded;
  const GroupMembersPage({super.key, this.embedded = false});

  @override
  ConsumerState<GroupMembersPage> createState() => _GroupMembersPageState();
}

/// 群聊气泡用的几种颜色，成员轮流取。
const List<int> kMemberColors = [
  0xFF4D7CFE, 0xFF2DD4BF, 0xFFF472B6, 0xFFF59E0B, 0xFFA78BFA, 0xFF34D399, 0xFF60A5FA,
];

class _GroupMembersPageState extends ConsumerState<GroupMembersPage> {
  @override
  Widget build(BuildContext context) {
    final db = ref.read(appDbProvider);
    return StreamBuilder(
      stream: db.watchGroupMembers(),
      builder: (context, snap) {
        final members = snap.data ?? [];
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Text('每个成员用自己的供应商/模型发言；关掉开关就不参与。',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
            ),
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text('还没有成员，点右上角 ＋ 添加', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
            for (final m in members) _memberRow(m),
          ],
        );
        final add = IconButton(
          onPressed: () => _editMember(null),
          icon: const Icon(Icons.add_rounded, color: AppColors.text),
        );
        if (!widget.embedded) {
          return Scaffold(
            appBar: AppBar(title: const Text('群成员'), actions: [add]),
            body: ListView(padding: const EdgeInsets.all(16), children: [body]),
          );
        }
        return embedShell(title: '群成员', actions: [add], body: body);
      },
    );
  }

  Widget _memberRow(dynamic m) {
    final color = Color(m.color);
    return LiquidPanel(
      radius: 14,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.white, 0.35)!]), borderRadius: BorderRadius.circular(10)),
          child: Text(m.name.isEmpty ? '?' : m.name.characters.first, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: InkWell(
            onTap: () => _editMember(m),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 2),
              Text(
                [m.provider, if ((m.model as String).isNotEmpty) m.model, if ((m.persona as String).isNotEmpty) '人物:${m.persona}'].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        // 旁边开关：选这个成员是否参与
        GlassSwitch(
          value: m.enabled,
          onChanged: (v) async {
            final db = ref.read(appDbProvider);
            await db.setGroupMemberEnabled(m.id, v);
          },
        ),
        IconButton(
          onPressed: () async {
            final db = ref.read(appDbProvider);
            await db.deleteGroupMember(m.id);
          },
          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.muted),
        ),
      ]),
    );
  }

  /// 新建/编辑成员：选供应商 + 模型 + 可选人物 + 角色提示词。
  Future<void> _editMember(dynamic m) async {
    final (providers, _) = await ProviderStore.loadAllWithActive();
    final personas = await PersonaStore.load();
    var name = m?.name as String? ?? '';
    var provider = m?.provider as String? ?? (providers.isNotEmpty ? providers.first.name : '');
    var model = m?.model as String? ?? '';
    var persona = m?.persona as String? ?? '';
    var rolePrompt = m?.rolePrompt as String? ?? '';
    var color = m?.color as int? ?? kMemberColors[(m?.id as int? ?? 0) % kMemberColors.length];
    final nameCtrl = TextEditingController(text: name);
    final roleCtrl = TextEditingController(text: rolePrompt);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(m == null ? '添加群成员' : '编辑成员'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GlassField(label: '成员名', hint: '比如 研究员 / 程序员', controller: nameCtrl),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: providers.any((p) => p.name == provider) ? provider : null,
                items: [for (final p in providers) DropdownMenuItem(value: p.name, child: Text(p.name, style: const TextStyle(fontSize: 13)))],
                onChanged: (v) => setD(() => provider = v ?? ''),
                decoration: const InputDecoration(labelText: '供应商', isDense: true),
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                dropdownColor: const Color(0xFF141B2E),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: model.isEmpty ? '' : model,
                items: [
                  const DropdownMenuItem(value: '', child: Text('（供应商默认模型）', style: TextStyle(fontSize: 13))),
                  for (final p in providers)
                    if (p.name == provider)
                      for (final mm in p.models) DropdownMenuItem(value: mm, child: Text(mm, style: const TextStyle(fontSize: 13))),
                ],
                onChanged: (v) => setD(() => model = v ?? ''),
                decoration: const InputDecoration(labelText: '模型', isDense: true),
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                dropdownColor: const Color(0xFF141B2E),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: persona,
                items: [
                  const DropdownMenuItem(value: '', child: Text('（不绑定人物）', style: TextStyle(fontSize: 13))),
                  for (final p in personas) DropdownMenuItem(value: p.name, child: Text(p.name, style: const TextStyle(fontSize: 13))),
                ],
                onChanged: (v) => setD(() => persona = v ?? ''),
                decoration: const InputDecoration(labelText: '人物（可选）', isDense: true),
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                dropdownColor: const Color(0xFF141B2E),
              ),
              const SizedBox(height: 12),
              GlassField(label: '群里的角色提示词', hint: '比如：你负责检索资料，回答要简短', controller: roleCtrl, maxLines: 3),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in kMemberColors)
                  GestureDetector(
                    onTap: () => setD(() => color = c),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 2),
                      ),
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(
              onPressed: () {
                name = nameCtrl.text.trim();
                rolePrompt = roleCtrl.text.trim();
                Navigator.pop(ctx, name.isNotEmpty && provider.isNotEmpty);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final db = ref.read(appDbProvider);
    final existing = m;
    if (existing == null) {
      await db.addGroupMember(GroupMembersCompanion.insert(
        name: name,
        provider: provider,
        model: Value(model),
        persona: Value(persona),
        rolePrompt: Value(rolePrompt),
        color: Value(color),
      ));
    } else {
      await db.updateGroupMember(GroupMembersCompanion(
        id: Value(existing.id),
        name: Value(name),
        provider: Value(provider),
        model: Value(model),
        persona: Value(persona),
        rolePrompt: Value(rolePrompt),
        color: Value(color),
        enabled: Value(existing.enabled),
      ));
    }
    if (mounted) showToast(context, '已保存');
  }
}
