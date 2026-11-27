import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import '../theme/app_theme.dart';
import '../agent/permission.dart';
import '../theme/liquid_glass.dart';
import '../theme/glass.dart';
import '../theme/toast.dart';
import '../theme/ref_draggable.dart';
import '../theme/glass_dialog.dart';
import '../state/chat_refs.dart';
import '../native/native_bridge.dart';
import '../agent/provider_store.dart';
import '../agent/llm.dart';
import '../agent/persona.dart';
import '../agent/prompt_store.dart';
import '../agent/default_prompt.dart';
import '../theme/number_field.dart';
import '../state/agent_controller.dart';
import '../data/db_provider.dart';
import '../data/app_db.dart';

/// 抽屉里内联展示设置页时用的外壳：无 Scaffold，标题 + 右上动作 + 内容区。
Widget embedShell({
  required String title,
  required Widget body,
  List<Widget> actions = const [],
}) {
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 2),
        child: Row(children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          ...actions,
        ]),
      ),
      Expanded(child: body),
    ],
  );
}


class ProvidersPage extends StatefulWidget {
  final bool embedded;
  const ProvidersPage({super.key, this.embedded = false});
  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  List<ProviderConfig> _list = [];
  String _active = '';
  final Map<String, String?> _bal = {};
  final Set<String> _balLoading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (l, a) = await ProviderStore.loadAllWithActive();
    if (mounted) {
      setState(() {
        _list = l;
        _active = a;
      });
      for (final p in l) {
        _loadBalance(p);
      }
    }
  }

  Future<void> _loadBalance(ProviderConfig p, {bool force = false}) async {
    if (!force && (_bal.containsKey(p.name) || _balLoading.contains(p.name))) return;
    setState(() => _balLoading.add(p.name));
    final v = await BalanceFetcher.fetch(p);
    if (!mounted) return;
    setState(() {
      _bal[p.name] = v;
      _balLoading.remove(p.name);
    });
  }

  Widget _balanceChip(ProviderConfig p) {
    final loading = _balLoading.contains(p.name);
    final v = _bal[p.name];
    return InkWell(
      onTap: () => _loadBalance(p, force: true),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: v == null ? const Color(0xFF1A2338) : const Color(0xFF1E2A45),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 12, color: v == null ? const Color(0xFF7886A0) : AppColors.brand),
          const SizedBox(width: 4),
          Text(
            loading ? '…' : (v ?? '—'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: v == null ? const Color(0xFF7886A0) : AppColors.brand,
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _setActive(ProviderConfig p) async {
    await ProviderStore.saveAll(_list, p.name);
    await _load();
  }

  Future<void> _delete(ProviderConfig p) async {
    final l = [..._list]..remove(p);
    final a = _active == p.name ? (l.isEmpty ? '' : l.first.name) : _active;
    await ProviderStore.saveAll(l, a);
    await _load();
  }

  Future<void> _editProvider(ProviderConfig? p) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141B2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: ProviderEditPage(initial: p, embedded: true),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final body = _list.isEmpty
        ? const EmptyState(icon: Icons.cloud_outlined, text: '还没有供应商\n点右上角 ＋ 添加自己的供应商与模型')
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final p in _list)
                RefSwipeDelete(
                  itemKey: 'provider-${p.name}',
                  onDelete: () => _delete(p),
                  child: GlassCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    onTap: () => _editProvider(p),
                    child: Row(children: [
                      Icon(
                        p.name == _active ? Icons.check_circle_rounded : Icons.cloud_outlined,
                        size: 20,
                        color: p.name == _active ? AppColors.brand : const Color(0xFF7886A0),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name.isEmpty ? '未命名' : p.name,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        Text('${p.model}  ·  ${p.baseUrl}', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                      ])),
                      const SizedBox(width: 8),
                      _balanceChip(p),
                      TextButton(
                        onPressed: p.name == _active ? null : () => _setActive(p),
                        child: Text(p.name == _active ? '当前' : '设为当前',
                            style: TextStyle(fontSize: 11, color: p.name == _active ? AppColors.muted : AppColors.brand)),
                      ),
                    ]),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('点卡片编辑 · 左滑删除 · 「设为当前」切换正在用的供应商',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
              ),
            ],
          );
    final addButton = IconButton(
      onPressed: () => _editProvider(null),
      icon: const Icon(Icons.add_rounded, color: Color(0xFFD4DBE8)),
    );
    if (widget.embedded) {
      return embedShell(title: 'AI 供应商', actions: [addButton], body: body);
    }
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: const Text('AI 供应商', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [addButton],
      ),
      body: body,
    );
  }
}

class ProviderEditPage extends StatefulWidget {
  final ProviderConfig? initial;
  final bool embedded;
  const ProviderEditPage({super.key, this.initial, this.embedded = false});
  @override
  State<ProviderEditPage> createState() => _ProviderEditPageState();
}

class _ProviderEditPageState extends State<ProviderEditPage> {
  final _name = TextEditingController();
  final _key = TextEditingController();
  final _url = TextEditingController();
  final _ctx = TextEditingController();
  String _protocol = 'OpenAI 兼容';
  String _testMsg = '';
  List<String> _available = [];
  final Set<String> _picked = {};
  String _model = '';

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    if (c != null) {
      _name.text = c.name;
      _key.text = c.apiKey;
      _url.text = c.baseUrl;
      _protocol = c.protocol;
      _available = List.of(c.models);
      _picked.addAll(c.models);
      _model = c.model;
      if (c.contextLength > 0) _ctx.text = '${c.contextLength}';
      if (_model.isNotEmpty) _picked.add(_model);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _url.dispose();
    _ctx.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final (list, active) = await ProviderStore.loadAllWithActive();
    final name = _name.text.trim().isEmpty ? (_model.isEmpty ? '供应商' : _model) : _name.text.trim();
    final p = ProviderConfig(
      name: name,
      baseUrl: _url.text.trim(),
      apiKey: _key.text.trim(),
      protocol: _protocol,
      models: _picked.toList(),
      model: _model.isEmpty && _picked.isNotEmpty ? _picked.first : _model,
      contextLength: int.tryParse(_ctx.text.trim()) ?? 0,
    );
    final oldName = widget.initial?.name;
    final idx = oldName == null ? -1 : list.indexWhere((e) => e.name == oldName);
    if (idx >= 0) {
      list[idx] = p;
    } else {
      list.add(p);
    }
    final newActive = (active.isEmpty || active == oldName) ? p.name : active;
    await ProviderStore.saveAll(list, newActive);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _fetch() async {
    setState(() => _testMsg = '请求中…');
    try {
      final client = HttpClient();
      final url = '${_url.text.trim().replaceAll(RegExp(r'/+$'), '')}/models';
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('Authorization', 'Bearer ${_key.text.trim()}');
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode != 200) {
        setState(() => _testMsg = '✗ HTTP ${resp.statusCode}');
        return;
      }
      final ids = <String>[];
      final m = RegExp(r'"id"\s*:\s*"([^"]+)"').allMatches(body);
      for (final x in m) {
        final id = x.group(1)!;
        if (!id.contains('embedding')) ids.add(id);
      }
      setState(() {
        _available = ids;
        if (_picked.isEmpty && ids.isNotEmpty) {
          _picked.add(ids.first);
          _model = ids.first;
        }
        _testMsg = ids.isEmpty ? '✓ 连接正常（未解析到模型列表）' : '✓ 连接正常 · ${ids.length} 个模型，点「添加」选';
      });
    } catch (e) {
      setState(() => _testMsg = '✗ ${e.toString().split('\n').first}');
    }
  }

  Widget _modelChip(String m) {
    final on = _model == m;
    return InkWell(
      onTap: () => setState(() => _model = m),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 30,
        padding: const EdgeInsets.only(left: 9, right: 3),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF1E2A45) : const Color(0xFF141B2E),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: on ? const Color(0xFF2A3A5E) : const Color(0xFF2A3550)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(m,
              style: TextStyle(
                fontSize: 11.5,
                color: on ? AppColors.brand : const Color(0xFFD4DBE8),
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              )),
          const SizedBox(width: 3),
          InkWell(
            onTap: () => setState(() {
              _picked.remove(m);
              if (_model == m) _model = _picked.isEmpty ? '' : _picked.first;
            }),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 12, color: Color(0xFF7886A0)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _addChip() {
    return InkWell(
      onTap: _pickModels,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF141B2E),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF2A3A5E)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, size: 13, color: AppColors.brand),
          SizedBox(width: 3),
          Text('添加', style: TextStyle(fontSize: 11, color: AppColors.brand)),
        ]),
      ),
    );
  }

  Future<void> _pickModels() async {
    final all = <String>{..._available, ..._picked}.toList()..sort();
    if (all.isEmpty) {
      setState(() => _testMsg = '先点「测试并拉取模型」');
      return;
    }
    final picked = Set<String>.from(_picked);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF141B2E),
          title: Row(children: [
            const Text('选择模型', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton(onPressed: () => setD(() => picked.addAll(all)), child: const Text('全选')),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final m in all)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: picked.contains(m),
                    title: Text(m, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                    onChanged: (v) => setD(() {
                      if (v == true) {
                        picked.add(m);
                      } else {
                        picked.remove(m);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('确定 ${picked.length}')),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        _picked
          ..clear()
          ..addAll(picked);
        if (!_picked.contains(_model) && _picked.isNotEmpty) _model = _picked.first;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('名称', style: TextStyle(fontSize: 11, color: AppColors.muted)),
        TextField(controller: _name),
        const SizedBox(height: 10),
        const Text('API Key', style: TextStyle(fontSize: 11, color: AppColors.muted)),
        TextField(controller: _key),
        const SizedBox(height: 10),
        const Text('Base URL', style: TextStyle(fontSize: 11, color: AppColors.muted)),
        TextField(controller: _url),
        const SizedBox(height: 10),
        const Text('上下文长度', style: TextStyle(fontSize: 11, color: AppColors.muted)),
        TextField(
          controller: _ctx,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(),
        ),
        const SizedBox(height: 6),
        Row(children: [
          GlassButton(label: '测试并拉取模型', icon: Icons.wifi_tethering_rounded, onTap: _fetch),
        ]),
        if (_testMsg.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_testMsg, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
        Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text('已选模型 ${_picked.length} 个 · 点选设为默认',
                style: const TextStyle(fontSize: 11, color: AppColors.muted))),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in _picked) _modelChip(m),
            _addChip(),
          ],
        ),
        if (_picked.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('先点「测试并拉取模型」，再点「添加」选模型',
                style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
          ),
      ],
    );
    if (widget.embedded) {
      return embedShell(
        title: widget.initial == null ? '添加供应商' : '编辑供应商',
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
          ),
        ],
        body: body,
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: Text(widget.initial == null ? '添加供应商' : '编辑供应商',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700))),
        ],
      ),
      body: body,
    );
  }
}


// ---------------- 技能 / 子代理 ----------------
class SkillsSubPage extends ConsumerStatefulWidget {
  final bool embedded;
  const SkillsSubPage({super.key, this.embedded = false});
  @override
  ConsumerState<SkillsSubPage> createState() => _SkillsSubPageState();
}

class _SkillsSubPageState extends ConsumerState<SkillsSubPage> {
  List<SubAgent> _subs = [];

  AppDb get _db => ref.read(appDbProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await _db.allSubAgents();
    if (mounted) setState(() => _subs = a);
  }

  Future<void> _addSub() async {
    final name = TextEditingController();
    final desc = TextEditingController();
    String tier = 'standard';
    final ok = await showGlassDialog<bool>(
      context: context,
      title: '新建子代理',
      confirmText: '保存',
      content: StatefulBuilder(
        builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
          const SizedBox(height: 8),
          TextField(controller: desc, decoration: const InputDecoration(labelText: '职责')),
          const SizedBox(height: 8),
          DropdownButton<String>(
            isExpanded: true,
            value: tier,
            items: [
              DropdownMenuItem(value: 'light', child: Text(tierLabel('light'))),
              DropdownMenuItem(value: 'standard', child: Text(tierLabel('standard'))),
              DropdownMenuItem(value: 'strong', child: Text(tierLabel('strong'))),
            ],
            onChanged: (v) => setS(() => tier = v ?? 'standard'),
          ),
        ]),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await _db.upsertSubAgent(SubAgentsCompanion.insert(
        name: name.text.trim(),
        description: Value(desc.text.trim()),
        modelTier: Value(tier),
      ));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: Row(children: [
              const Icon(Icons.groups_outlined, size: 20, color: AppColors.brand),
              const SizedBox(width: 12),
              const Expanded(child: Text('子代理', style: TextStyle(fontSize: 13.5))),
              TextButton(onPressed: _addSub, child: const Text('＋', style: TextStyle(color: AppColors.brand))),
            ]),
          ),
          if (_subs.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('（暂无子代理）', style: TextStyle(fontSize: 11, color: AppColors.muted)))
          else
            for (final a in _subs)
              RefSwipeDelete(
                itemKey: 'subagent-${a.name}',
                onDelete: () async {
                  await _db.deleteSubAgent(a.name);
                  await _load();
                },
                child: GlassCard(
                margin: const EdgeInsets.only(top: 8),
                child: RefDraggable(
                  ref: ChatRef(type: 'subagent', name: a.name, detail: '${tierLabel(a.modelTier)}：${a.description}'),
                  child: Row(children: [
                  const Icon(Icons.groups_outlined, size: 18, color: AppColors.brand),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${a.name} · ${tierLabel(a.modelTier)}', style: const TextStyle(fontSize: 13)),
                    if (a.description.isNotEmpty)
                      Text(a.description, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ])),
                  Switch(
                    value: a.enabled,
                    activeColor: AppColors.brand,
                    onChanged: (v) async {
                      await _db.upsertSubAgent(SubAgentsCompanion.insert(
                        name: a.name,
                        description: Value(a.description),
                        modelTier: Value(a.modelTier),
                        enabled: Value(v),
                      ));
                      await _load();
                    },
                  ),
                ]),
                ),
                ),
              ),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('子代理：档位 + 职责，长按删除，可拖进对话。', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ),
        ],
      );
    if (widget.embedded) {
      return embedShell(title: '子代理', body: body);
    }
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: const Text('子代理', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: body,
    );
  }
}

// ---------------- 提示词 ----------------
class PromptPage extends StatefulWidget {
  final bool embedded;
  const PromptPage({super.key, this.embedded = false});
  @override
  State<PromptPage> createState() => _PromptPageState();
}

class _PromptPageState extends State<PromptPage> {
  List<Prompt> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await PromptStore.load();
    if (mounted) setState(() => _list = l);
  }

  Future<void> _persist() => PromptStore.save(_list);

  Future<void> _restoreBuiltin() async {
    if (_list.any((e) => e.name == kDefaultPromptName)) {
      showToast(context, '已有「$kDefaultPromptName」', error: true);
      return;
    }
    setState(() {
      _list.add(Prompt(name: kDefaultPromptName, content: kDefaultPromptContent, active: _list.isEmpty));
    });
    await PromptStore.save(_list);
    if (mounted) showToast(context, '已恢复内置规则');
  }

  Future<void> _edit([Prompt? p]) async {
    final name = TextEditingController(text: p?.name ?? '');
    final content = TextEditingController(text: p?.content ?? '');
    final ok = await showGlassDialog<bool>(
      context: context,
      title: p == null ? '新建提示词' : '编辑提示词',
      confirmText: '保存',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
          const SizedBox(height: 8),
          TextField(controller: content, maxLines: 6, decoration: const InputDecoration(labelText: '内容')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      if (p == null) {
        _list.add(Prompt(name: name.text.trim(), content: content.text.trim(), active: _list.isEmpty));
      } else {
        p.name = name.text.trim();
        p.content = content.text.trim();
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
        ? const EmptyState(icon: Icons.forum_outlined, text: '还没有提示词\n点右上角 ＋ 新建，可多条并切换当前')
        : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (var i = 0; i < _list.length; i++)
                  RefSwipeDelete(
                    itemKey: 'prompt-${_list[i].name}',
                    onDelete: () async { _del(i); },
                    child: GlassCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    onTap: () => _setActive(i),
                    child: RefDraggable(
                      ref: ChatRef(type: 'prompt', name: _list[i].name, detail: _list[i].content),
                      child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_list[i].name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              if (_list[i].content.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(_list[i].content,
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
                          icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF7886A0)),
                        ),
                      ],
                    ),
                    ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('点卡片：设为当前　左滑：删除', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
                ),
              ],
            );
    final actions = [
      IconButton(
        tooltip: '恢复内置规则',
        onPressed: _restoreBuiltin,
        icon: const Icon(Icons.settings_backup_restore_rounded, color: Color(0xFFD4DBE8)),
      ),
      IconButton(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded, color: Color(0xFFD4DBE8))),
    ];
    if (widget.embedded) {
      return embedShell(title: '提示词', actions: actions, body: body);
    }
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: const Text('提示词', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: actions,
      ),
      body: body,
    );
  }
}

// ---------------- 工具授权 / 软件权限 ----------------
class PowerPage extends ConsumerStatefulWidget {
  final bool embedded;
  const PowerPage({super.key, this.embedded = false});
  @override
  ConsumerState<PowerPage> createState() => _PowerPageState();
}

class _PowerPageState extends ConsumerState<PowerPage> {
  final _ctrl = TextEditingController();
  String _moduleMsg = '';
  Map<String, bool> _perm = {};
  final Set<String> _checking = {};
  final Set<String> _checked = {};

  @override
  void initState() {
    super.initState();
    _loadPerm();
  }

  Future<void> _loadPerm() async {
    final p = await NativeBridge.permStatus();
    if (mounted) setState(() => _perm = p);
  }

  /// 权限行：右侧开关反映真实状态；点开关去授权（关闭需在系统设置里改）。
  /// 权限行：点开关 → 真实申请 → 回来重新检测 → 给出成功/失败反馈。
  Widget _permRow(String key, String label, String desc, bool granted, Future<void> Function() onTap) {
    final checking = _checking.contains(key);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                if (desc.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(desc, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                  ),
                if (checking)
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text('检测中…', style: TextStyle(fontSize: 10, color: AppColors.brand)),
                  )
                else if (_checked.contains(key))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      granted ? '✓ 已开启' : '✗ 未开启：需在系统里手动允许，回来后再点一次',
                      style: TextStyle(
                          fontSize: 10,
                          color: granted ? AppColors.green : const Color(0xFFDC2626)),
                    ),
                  ),
              ],
            ),
          ),
          if (checking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Switch(
              value: granted,
              activeColor: AppColors.brand,
              onChanged: (_) => _applyPerm(key, onTap),
            ),
        ]),
      ),
    );
  }

  Future<void> _applyPerm(String key, Future<void> Function() onTap) async {
    setState(() {
      _checking.add(key);
      _checked.remove(key);
    });
    await onTap();
    await Future.delayed(const Duration(milliseconds: 900));
    await _loadPerm();
    if (!mounted) return;
    setState(() {
      _checking.remove(key);
      _checked.add(key);
    });
  }

  Future<void> _installModule() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141B2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text('Zygisk 注入模块', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text('选择安装方式，也可以导出 zip 用管理器自己导入',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ),
          for (final o in [
            ('auto', '自动（KernelSU → APatch → Magisk）', Icons.auto_awesome_rounded),
            ('magisk', 'Magisk', Icons.shield_rounded),
            ('ksu', 'KernelSU', Icons.security_rounded),
            ('apatch', 'APatch', Icons.bolt_rounded),
            ('export', '导出 zip 到 Download（自己手动装）', Icons.download_rounded),
          ])
            ListTile(
              leading: Icon(o.$3, size: 20, color: AppColors.brand),
              title: Text(o.$2, style: const TextStyle(fontSize: 13)),
              onTap: () => Navigator.pop(ctx, o.$1),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null) return;
    setState(() => _moduleMsg = '安装中…');
    final r = await NativeBridge.installFridaModule(manager: choice);
    final msg = (r['msg'] ?? '').toString();
    final ok = r['ok'] == true;
    setState(() => _moduleMsg = ok
        ? (choice == 'export' ? '✓ $msg' : '✓ 已安装，重启生效')
        : '✗ 安装失败：${msg.isEmpty ? '需 root / 管理器未就绪' : msg}');
    if (mounted) {
      showToast(context,
          ok ? (choice == 'export' ? '已导出到 Download' : '模块已安装，重启生效') : '安装失败，看下方提示',
          error: !ok);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(agentEngineProvider).policy;
    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('常用', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          _permRow('allFiles', '所有文件访问', '读写 /sdcard、读 APK', _perm['allFiles'] == true, () async {
            await NativeBridge.requestStorage();
            await Future.delayed(const Duration(milliseconds: 600));
            _loadPerm();
          }),
          _permRow('notification', '通知权限', '后台任务完成时提醒', _perm['notification'] == true, () async {
            await NativeBridge.requestPermissions();
            await Future.delayed(const Duration(milliseconds: 800));
            _loadPerm();
          }),
          _permRow('overlay', '悬浮窗', '日志窗、小窗终端', _perm['overlay'] == true, () async {
            await NativeBridge.openSettings('overlay');
            await Future.delayed(const Duration(milliseconds: 600));
            _loadPerm();
          }),
          _permRow('installPackages', '安装应用', '装 APK 需要', _perm['installPackages'] == true, () async {
            await NativeBridge.openSettings('unknownSources');
          }),

          const SizedBox(height: 10),
          const Text('应用与媒体', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          _permRow('battery', '电池优化白名单', '后台不被杀', _perm['battery'] == true, () async {
            await NativeBridge.openSettings('battery');
          }),
          _permRow('usageStats', '使用情况访问', '看前台应用、流量归属', _perm['usageStats'] == true, () async {
            await NativeBridge.openSettings('usage');
          }),
          _permRow('mediaImages', '图片读取', '选头像、看图', _perm['mediaImages'] == true, () async {
            await NativeBridge.requestMedia();
            await Future.delayed(const Duration(milliseconds: 600));
            _loadPerm();
          }),
          _permRow('mediaVideo', '视频读取', '视频页、选文件', _perm['mediaVideo'] == true, () async {
            await NativeBridge.requestMedia();
            await Future.delayed(const Duration(milliseconds: 600));
            _loadPerm();
          }),
          _permRow('mediaAudio', '音频读取', '音乐页、选文件', _perm['mediaAudio'] == true, () async {
            await NativeBridge.requestMedia();
            await Future.delayed(const Duration(milliseconds: 600));
            _loadPerm();
          }),

          const SizedBox(height: 10),
          const Text('系统能力', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          _permRow('root', 'Root', '高危操作需要', _perm['root'] == true, () async {
            // 真正发起一次 su，触发超级用户弹窗
            await NativeBridge.rootExec('id');
            await _loadPerm();
            if (mounted) {
              showToast(context, _perm['root'] == true ? 'Root 已授权' : '没拿到 root：在超级用户里允许后重试',
                  error: _perm['root'] != true);
            }
          }),
          _permRow('shizuku', 'Shizuku', '免 root 的 shell 能力', _perm['shizuku'] == true, () async {
            if (!await NativeBridge.shizukuAvailable()) {
              if (mounted) showToast(context, 'Shizuku 未运行：先安装并启动 Shizuku', error: true);
              return;
            }
            if (!await NativeBridge.shizukuPermission()) await NativeBridge.shizukuRequest();
            await Future.delayed(const Duration(milliseconds: 600));
            await _loadPerm();
            if (mounted) {
              showToast(context, _perm['shizuku'] == true ? 'Shizuku 已连接' : '已请求授权，请在弹窗里允许',
                  error: _perm['shizuku'] != true);
            }
          }),
          _permRow('accessibility', '无障碍（读屏）', 'AI 读屏/点滑/截图需要', _perm['accessibility'] == true, () async {
            await NativeBridge.screenOpenSettings();
            await Future.delayed(const Duration(milliseconds: 600));
            _loadPerm();
            if (mounted) {
              showToast(context, _perm['accessibility'] == true ? '无障碍已开启' : '请在列表里开启「Rowan 读屏」',
                  error: _perm['accessibility'] != true);
            }
          }),
          _permRow('vpn', 'VPN', '抓包时才会请求', _perm['vpn'] == true, () async {
            await NativeBridge.openSettings('vpn');
            await Future.delayed(const Duration(milliseconds: 800));
            _loadPerm();
          }),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('网络、前台服务、开机自启、唤醒锁安装时自动授予，不需要手动开。',
                style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.6)),
          ),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Text('AI 工具授权', style: TextStyle(fontSize: 11, color: AppColors.muted))),
            TextButton(
              onPressed: () => _addRuleDialog(policy),
              child: const Text('添加规则', style: TextStyle(fontSize: 11.5)),
            ),
          ]),
          if (policy.allow.isEmpty && policy.deny.isEmpty && policy.confirm.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('默认全部允许；关掉开关就是不再允许该工具',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            )
          else ...[
            const Text('常用', style: TextStyle(fontSize: 10.5, color: Color(0xFFB6C0CD))),
            for (final n in policy.allow.where((n) => !PermissionPolicy.isHighRisk(n)))
              _toolRow(policy, n),
            if (policy.allow.where((n) => !PermissionPolicy.isHighRisk(n)).isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('（还没有勾选任何常用工具）', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
              ),
            const SizedBox(height: 6),
            const Text('高危工具（默认每次询问）', style: TextStyle(fontSize: 10.5, color: Color(0xFFB6C0CD))),
            for (final n in policy.allow.where(PermissionPolicy.isHighRisk))
              _toolRow(policy, n),
            for (final n in policy.deny.where(PermissionPolicy.isHighRisk))
              _toolRow(policy, n),
            for (final n in policy.confirm.where(PermissionPolicy.isHighRisk))
              _toolRow(policy, n),
          ],
          const SizedBox(height: 14),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: const [
                Icon(Icons.extension_outlined, size: 20, color: AppColors.brand),
                SizedBox(width: 12),
                Expanded(child: Text('Zygisk 注入模块', style: TextStyle(fontSize: 13))),
              ]),
              const SizedBox(height: 6),
              const Text(
                '模块文件内置在 App 里，可随时部署到 /data/adb/modules；注入靠 gadget，不需要 frida-server。',
                style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.6),
              ),
              const SizedBox(height: 8),
              GlassButton(label: '部署内置模块', icon: Icons.system_update_alt_rounded, onTap: _installModule),
              const SizedBox(height: 8),
              GlassButton(label: '打开模块 WebUI（日志/开关）', icon: Icons.dashboard_customize_outlined, onTap: NativeBridge.openModuleWebUi),
              if (_moduleMsg.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(_moduleMsg, style: const TextStyle(fontSize: 11.5, color: AppColors.muted))),
            ]),
          ),
        ],
      );
    if (widget.embedded) {
      return embedShell(title: '权限', body: body);
    }
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: const Text('权限', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: body,
    );
  }

  Widget _toolRow(PermissionPolicy policy, String name) {
    final decision = policy.allow.contains(name)
        ? 'allow'
        : policy.deny.contains(name)
            ? 'deny'
            : 'confirm';
    return Dismissible(
      key: ValueKey('tool:$name'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1A1A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text('删除规则',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
      ),
      onDismissed: (_) async {
        policy.allow.remove(name);
        policy.deny.remove(name);
        policy.confirm.remove(name);
        await policy.save();
        if (mounted) setState(() {});
      },
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(child: Text(name, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5))),
          Switch(
            value: decision == 'allow',
            activeColor: AppColors.brand,
            onChanged: (v) async {
              await policy.setDecision(name, v ? 'allow' : 'deny');
              setState(() {});
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _addRuleDialog(policy) async {
    final name = TextEditingController();
    String decision = 'deny';
    final ok = await showGlassDialog<bool>(
      context: context,
      title: '添加工具规则',
      confirmText: '添加',
      content: StatefulBuilder(
        builder: (ctx, setSt) => Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: '工具名或命令')),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final d in ['allow', 'confirm', 'deny'])
              ChoiceChip(
                label: Text(d == 'allow' ? '允许' : d == 'confirm' ? '需确认' : '拒绝', style: const TextStyle(fontSize: 12)),
                selected: decision == d,
                onSelected: (_) => setSt(() => decision = d),
              ),
          ]),
        ]),
      ),
    );
    final n = name.text.trim();
    if (ok == true && n.isNotEmpty) {
      setState(() {
        if (decision == 'allow') policy.allow.add(n);
        if (decision == 'confirm') policy.confirm.add(n);
        if (decision == 'deny') policy.deny.add(n);
      });
    }
  }
}
