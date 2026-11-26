import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../theme/ref_draggable.dart';
import '../theme/glass_dialog.dart';
import '../state/chat_refs.dart';
import '../agent/persona.dart';
import 'settings_page.dart' show embedShell;

class PersonasPage extends StatefulWidget {
  final bool embedded;
  const PersonasPage({super.key, this.embedded = false});
  @override
  State<PersonasPage> createState() => _PersonasPageState();
}

class _PersonasPageState extends State<PersonasPage> {
  List<Persona> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await PersonaStore.load();
    if (mounted) setState(() => _list = l);
  }

  Future<void> _persist() => PersonaStore.save(_list);

  Future<void> _edit([Persona? p]) async {
    final name = TextEditingController(text: p?.name ?? '');
    final persona = TextEditingController(text: p?.persona ?? '');
    final style = TextEditingController(text: p?.style ?? '');
    String avatar = p?.avatar ?? '';

    final ok = await showGlassDialog<bool>(
      context: context,
      title: p == null ? '新建人物' : '编辑人物',
      confirmText: '保存',
      content: StatefulBuilder(
        builder: (ctx, setSt) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: GestureDetector(
                onTap: () async {
                  final x = await ImagePicker().pickImage(source: ImageSource.gallery);
                  if (x != null) {
                    final saved = await PersonaStore.saveAvatar(x.path, name.text);
                    setSt(() => avatar = saved);
                  }
                },
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.brandSoft,
                  backgroundImage: avatar.isNotEmpty && File(avatar).existsSync() ? FileImage(File(avatar)) : null,
                  child: avatar.isEmpty || !File(avatar).existsSync()
                      ? const Icon(Icons.person_outline_rounded, color: AppColors.brand)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text('点头像从相册选择', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
            ),
            const SizedBox(height: 10),
            TextField(controller: name, decoration: const InputDecoration(labelText: '名字')),
            const SizedBox(height: 8),
            TextField(controller: persona, maxLines: 5, decoration: const InputDecoration(labelText: '人设 / 描述')),
            const SizedBox(height: 8),
            TextField(controller: style, decoration: const InputDecoration(labelText: '说话风格')),
          ],
        ),
      ),
    );

    if (ok == true && name.text.trim().isNotEmpty) {
      if (p == null) {
        _list.add(Persona(
          name: name.text.trim(),
          avatar: avatar,
          persona: persona.text.trim(),
          style: style.text.trim(),
          active: _list.isEmpty,
        ));
      } else {
        p.name = name.text.trim();
        p.avatar = avatar;
        p.persona = persona.text.trim();
        p.style = style.text.trim();
      }
      await _persist();
      await _load();
    }
  }

  Future<void> _setActive(int i) async {
    for (var j = 0; j < _list.length; j++) {
      _list[j].active = j == i;
    }
    await _persist();
    await _load();
  }

  Future<void> _del(int i) async {
    _list.removeAt(i);
    await _persist();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final body = _list.isEmpty
        ? const EmptyState(icon: Icons.person_outline_rounded, text: '还没有人物\n点右上角 ＋ 新建，可设多个并切换当前')
        : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (var i = 0; i < _list.length; i++)
                  RefSwipeDelete(
                    itemKey: 'persona-${_list[i].name}',
                    onDelete: () async { _del(i); },
                    child: GlassCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    onTap: () => _setActive(i),
                    child: RefDraggable(
                      ref: ChatRef(type: 'persona', name: _list[i].name, detail: _list[i].persona),
                      child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.brandSoft,
                          backgroundImage: _list[i].avatar.isNotEmpty && File(_list[i].avatar).existsSync()
                              ? FileImage(File(_list[i].avatar))
                              : null,
                          child: _list[i].avatar.isEmpty || !File(_list[i].avatar).existsSync()
                              ? const Icon(Icons.person_outline_rounded, size: 20, color: AppColors.brand)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_list[i].name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              if (_list[i].persona.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(_list[i].persona,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                ),
                            ],
                          ),
                        ),
                        Transform.scale(
                          scale: 0.72,
                          child: Switch(
                            value: _list[i].active,
                            activeThumbColor: AppColors.brand,
                            onChanged: (v) async {
                              if (v) {
                                await _setActive(i);
                              } else {
                                setState(() => _list[i].active = false);
                                await _persist();
                                await _load();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => _edit(_list[i]),
                          icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                    ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('点卡片：设为当前人物　长按：删除',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
                ),
              ],
            );
    final addButton = IconButton(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add_rounded, color: Color(0xFF334155)),
    );
    if (widget.embedded) {
      return embedShell(title: 'AI 人物', actions: [addButton], body: body);
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('AI 人物', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [addButton],
      ),
      body: body,
    );
  }
}
