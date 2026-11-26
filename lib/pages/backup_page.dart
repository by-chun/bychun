import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_db.dart';
import '../data/db_provider.dart';
import '../native/native_bridge.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../theme/toast.dart';
import 'settings_page.dart' show embedShell;

/// 备份与恢复：勾选要导出的数据，导出为 JSON；恢复时覆盖选中的项。
class BackupPage extends ConsumerStatefulWidget {
  final bool embedded;
  const BackupPage({super.key, this.embedded = false});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  /// key 前缀：file=应用目录下的 json，db=数据库表，env=容器记录。
  static const Map<String, String> _items = {
    'file:providers.json': 'AI 供应商',
    'file:personas.json': '人物',
    'db:subagents': '子代理',
    'file:scripts.json': '插件',
    'env:containers': '容器记录',
    'file:mcp.json': 'MCP 服务器',
    'file:permission.json': '权限与工具规则',
    'file:compact.json': '上下文压缩',
    'file:xposed_scripts.json': 'Xposed 脚本',
    'file:prompts.json': '提示词',
    'file:memory.json': '记忆',
  };

  final Set<String> _picked = {..._items.keys};
  bool _busy = false;

  Future<void> _pickAndExport() async {
    final picked = <String>{..._items.keys};
    final go = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final allPicked = picked.length == _items.length;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
                    child: Row(children: [
                      const Text('选择要导出的数据', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setS(() {
                          if (allPicked) {
                            picked.clear();
                          } else {
                            picked.addAll(_items.keys);
                          }
                        }),
                        child: Text(allPicked ? '全不选' : '全选', style: const TextStyle(fontSize: 11.5)),
                      ),
                    ]),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final e in _items.entries)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: picked.contains(e.key),
                            onChanged: (v) => setS(() {
                              if (v == true) {
                                picked.add(e.key);
                              } else {
                                picked.remove(e.key);
                              }
                            }),
                            title: Text(e.value, style: const TextStyle(fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size.fromHeight(44)),
                    child: Text('导出选中的 ${picked.length} 项', style: const TextStyle(fontSize: 13.5)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (go != true) return;
    _picked
      ..clear()
      ..addAll(picked);
    await _export();
  }

  Future<void> _export() async {
    if (_picked.isEmpty) {
      showToast(context, '先勾选要导出的内容', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final files = <String, dynamic>{};
      List<Map<String, dynamic>>? subs;
      List<Map<String, dynamic>>? envs;
      for (final key in _picked) {
        final i = key.indexOf(':');
        final kind = key.substring(0, i);
        final name = key.substring(i + 1);
        if (kind == 'file') {
          final txt = await NativeBridge.readAppFile(name);
          if (txt != null && txt.trim().isNotEmpty) files[name] = txt;
        } else if (kind == 'db' && name == 'subagents') {
          final list = await ref.read(appDbProvider).allSubAgents();
          subs = [
            for (final s in list)
              {'name': s.name, 'description': s.description, 'modelTier': s.modelTier, 'enabled': s.enabled},
          ];
        } else if (kind == 'env') {
          envs = await NativeBridge.envList();
        }
      }
      if (files.isEmpty && subs == null && envs == null) {
        if (mounted) showToast(context, '选中的内容都是空的，没有可导出的东西', error: true);
        return;
      }
      final payload = <String, dynamic>{
        'app': 'rowan',
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'files': files,
        if (subs != null) 'subAgents': subs,
        if (envs != null) 'containers': envs,
      };
      final name = 'rowan-backup-${DateTime.now().millisecondsSinceEpoch}.json';
      final ok = await NativeBridge.exportJson(name, const JsonEncoder.withIndent('  ').convert(payload));
      if (mounted) showToast(context, ok ? '已导出到 Download：$name' : '导出失败', error: !ok);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final text = await NativeBridge.pickTextFile();
    if (text == null || text.trim().isEmpty) return;
    Map<String, dynamic>? files;
    List<dynamic>? subs;
    var hasContainers = false;
    try {
      final m = jsonDecode(text);
      if (m is Map) {
        if (m['files'] is Map) files = Map<String, dynamic>.from(m['files'] as Map);
        if (m['subAgents'] is List) subs = m['subAgents'] as List;
        hasContainers = m['containers'] is List;
      }
    } catch (_) {}
    if (files == null && subs == null) {
      if (mounted) showToast(context, '不是有效的备份文件', error: true);
      return;
    }
    if (!mounted) return;
    final names = <String>[
      ...?files?.keys,
      if (subs != null) 'subAgents（子代理）',
      if (hasContainers) 'containers（容器记录，仅记录不自动安装）',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('恢复备份', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          '将覆盖以下 ${names.length} 项：\n${names.join('\n')}\n\n当前配置会被替换，确定吗？',
          style: const TextStyle(fontSize: 12.5, height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('覆盖恢复')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      var n = 0;
      for (final e in (files ?? const <String, dynamic>{}).entries) {
        if (!_items.containsKey('file:${e.key}')) continue;
        final okw = await NativeBridge.writeAppFile(e.key, e.value.toString());
        if (okw) n++;
      }
      if (subs != null) {
        final db = ref.read(appDbProvider);
        for (final raw in subs) {
          final m = Map<String, dynamic>.from(raw as Map);
          await db.upsertSubAgent(SubAgentsCompanion.insert(
            name: (m['name'] ?? '').toString(),
            description: Value((m['description'] ?? '').toString()),
            modelTier: Value((m['modelTier'] ?? 'standard').toString()),
            enabled: Value(m['enabled'] != false),
          ));
          n++;
        }
      }
      if (mounted) showToast(context, '已恢复 $n 项，建议重启 App', error: n == 0);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            onTap: _busy ? null : _pickAndExport,
            child: Row(children: [
              const Icon(Icons.file_upload_outlined, size: 20, color: AppColors.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('导出数据',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('点开勾选要导出的项，共 ${_items.length} 项',
                      style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ]),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
            ]),
          ),
          const SizedBox(height: 10),
          GlassCard(
            onTap: _busy ? null : _import,
            child: Row(children: const [
              Icon(Icons.file_download_outlined, size: 20, color: AppColors.brand),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('从备份恢复', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  SizedBox(height: 3),
                  Text('选择导出的 json，覆盖对应项',
                      style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
          if (_busy) ...[
            const SizedBox(height: 18),
            const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ],
          const SizedBox(height: 22),
          const Text(
            '不含：聊天记录、抓包记录、容器里的系统文件（属于运行时数据）。\n备份里包含 API Key，分享前请自行处理。',
            style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.7),
          ),
        ],
      );
    if (widget.embedded) {
      return embedShell(title: '备份与恢复', body: body);
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('备份与恢复', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: body,
    );
  }
}
