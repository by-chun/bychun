import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/toast.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../agent/compact_store.dart';
import '../agent/model_limits.dart';
import '../agent/provider_store.dart';
import '../theme/number_field.dart';
import 'settings_page.dart' show embedShell;
import '../state/agent_controller.dart';

class CompactPage extends ConsumerStatefulWidget {
  final bool embedded;
  const CompactPage({super.key, this.embedded = false});
  @override
  ConsumerState<CompactPage> createState() => _CompactPageState();
}

class _CompactPageState extends ConsumerState<CompactPage> {
  CompactConfig _cfg = CompactConfig();
  int _limit = 128000;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await CompactStore.load();
    final ctx = await ProviderStore.activeContextLength();
    final limit = ctx;
    if (mounted) {
      setState(() {
        _cfg = c;
        _limit = limit;
      });
    }
  }

  Future<void> _save() => CompactStore.save(_cfg);

  @override
  Widget build(BuildContext context) {
    final saveButton = TextButton(
      onPressed: () async {
        await _save();
        if (!mounted) return;
        showToast(context, '已保存');
      },
      child: const Text('保存',
          style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
    );
    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                _limit > 0 ? '上下文上限：${fmtTokens(_limit)}（${_limit} token）' : '上下文上限：不限制（默认）',
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ),
          GlassCard(
            child: Row(children: [
              const Expanded(
                child: Text('自动压缩', style: TextStyle(fontSize: 13)),
              ),
              Text(_cfg.enabled ? '超过阈值时自动摘要' : '已关闭',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
              const SizedBox(width: 6),
              Switch(
                value: _cfg.enabled,
                activeThumbColor: AppColors.brand,
                onChanged: (v) {
                  setState(() => _cfg.enabled = v);
                  _save();
                },
              ),
            ]),
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('立即压缩', style: TextStyle(fontSize: 13)),
                  Text('马上把旧消息摘要成一条，保留最近几条', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
                ]),
              ),
              FilledButton(
                onPressed: () async {
                  await ref.read(agentEngineProvider).compactNow();
                  if (!mounted) return;
                  showToast(context, '已压缩，结果见对话');
                },
                child: const Text('执行', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('触发阈值', style: TextStyle(fontSize: 13)),
                const Spacer(),
                Text('${_cfg.threshold}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
              const Text('估算 token 超过该值时自动压缩', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
              NumberFieldRow(
                label: '触发阈值',
                value: _cfg.threshold.toDouble(),
                min: 10000,
                max: 200000,
                onChanged: (v) {
                  setState(() => _cfg.threshold = v.round());
                  _save();
                },
              ),
              const Divider(height: 1, color: AppColors.border),
              Row(children: [
                const Text('保留最近条数', style: TextStyle(fontSize: 13)),
                const Spacer(),
                Text('${_cfg.keep}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
              const Text('压缩时原文保留的最后几条消息', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
              NumberFieldRow(
                label: '保留最近条数',
                value: _cfg.keep.toDouble(),
                min: 2,
                max: 50,
                onChanged: (v) {
                  setState(() => _cfg.keep = v.round());
                  _save();
                },
              ),
              const Divider(height: 1, color: AppColors.border),
              const Text('一次对话里最多允许的工具调用轮数',
                  style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
              NumberFieldRow(
                label: '工具调用轮数上限',
                value: _cfg.maxTurns.toDouble(),
                min: 0,
                max: 999,
                onChanged: (v) {
                  setState(() => _cfg.maxTurns = v.round());
                  _save();
                },
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('对话里发 /compact 或 /compress 可手动压缩一次。', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
          ),
        ],
      );
    if (widget.embedded) {
      return embedShell(title: '上下文压缩', actions: [saveButton], body: body);
    }
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: const Text('上下文压缩', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [saveButton],
      ),
      body: body,
    );
  }
}
