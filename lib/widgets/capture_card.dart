import 'dart:async';
import 'package:flutter/material.dart';
import '../native/native_bridge.dart';
import '../theme/app_theme.dart';

/// 抓包窗口：AI 开始抓包后在对话里常驻，实时显示 DNS 记录。
class CaptureCard extends StatefulWidget {
  final Future<void> Function() onStop;
  const CaptureCard({super.key, required this.onStop});

  @override
  State<CaptureCard> createState() => _CaptureCardState();
}

class _CaptureCardState extends State<CaptureCard> {
  Timer? _timer;
  List<CaptureHit> _hits = [];
  String _dns = '';
  bool _auto = true;
  bool _needDns = false;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final text = await NativeBridge.vpnLog();
    final st = await NativeBridge.vpnStatus();
    if (!mounted) return;
    final hits = text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map(CaptureHit.parse)
        .whereType<CaptureHit>()
        .toList()
        .reversed
        .toList();
    setState(() {
      _hits = hits;
      _dns = (st['dns'] ?? '').toString();
      _auto = st['auto'] != false;
      _needDns = st['needDns'] == true;
      _running = st['running'] == true;
    });
  }

  Future<void> _editDns() async {
    final ctrl = TextEditingController(text: _dns);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上游 DNS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('自动获取失败时手动填一个能用的 DNS（如路由器 192.168.1.1、代理的 127.0.0.1）。',
              style: TextStyle(fontSize: 11, color: Color(0xFF9AA7C0), height: 1.5)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存并重试'),
          ),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      await NativeBridge.vpnSetDns(v);
      await Future.delayed(const Duration(milliseconds: 800));
      await _load();
    }
  }

  Future<void> _clear() async {
    await NativeBridge.vpnClear();
    await _load();
  }

  void _expand() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141B2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 6),
              child: Row(children: [
                const Text('抓包记录', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Text('${_hits.length}',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF7886A0), fontFamily: 'monospace')),
                const Spacer(),
                TextButton(onPressed: _clear, child: const Text('清空', style: TextStyle(fontSize: 12))),
              ]),
            ),
            Expanded(
              child: _hits.isEmpty
                  ? const Center(
                      child: Text('还没有抓到记录', style: TextStyle(fontSize: 12, color: Color(0xFF7886A0))),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                      itemCount: _hits.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF1A2338)),
                      itemBuilder: (_, i) => _row(_hits[i], fontSize: 11.5),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(CaptureHit h, {double fontSize = 10.5}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(
          width: 58,
          child: Text(h.time,
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF7886A0), fontFamily: 'monospace')),
        ),
        Expanded(
          child: Text(h.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fontSize, fontFamily: 'monospace', color: const Color(0xFFD4DBE8))),
        ),
        if (h.ips.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(h.ips,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF16A34A), fontFamily: 'monospace')),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _hits.take(6).toList();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3550)),
        boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _needDns
                      ? const Color(0xFFF59E0B)
                      : _running
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFCBD5E1),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(_needDns ? '等待上游 DNS' : (_running ? '抓包中' : '未运行'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text('${_hits.length}',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF7886A0), fontFamily: 'monospace')),
              const Spacer(),
              IconButton(
                onPressed: widget.onStop,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFCBD5E1)),
              ),
            ]),
          ),
          InkWell(
            onTap: _editDns,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(children: [
                const Text('上游 DNS', style: TextStyle(fontSize: 10.5, color: Color(0xFF9AA7C0))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_dns.isEmpty ? '未设置' : _dns,
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFFEAF0FB), fontFamily: 'monospace')),
                ),
                if (_dns.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF1E2A45), borderRadius: BorderRadius.circular(6)),
                    child: Text(_auto ? '自动' : '手动',
                        style: const TextStyle(fontSize: 9, color: AppColors.brand)),
                  ),
                const SizedBox(width: 8),
                const Text('修改', style: TextStyle(fontSize: 10.5, color: AppColors.brand, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          if (_needDns)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              color: const Color(0xFF2A2412),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('自动获取上游 DNS 失败（系统 DNS 取不到），先手动填一个再抓包。',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFFB45309), height: 1.5)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _editDns,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(8)),
                    child: const Text('填写上游 DNS', style: TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96, maxHeight: 210),
            child: shown.isEmpty
                ? Center(
                    child: Text(_needDns ? '填好上游 DNS 后，刷新一个网页就能看到记录' : '等待流量…',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF7886A0))),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shrinkWrap: true,
                    children: [for (final h in shown) _row(h)],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(children: [
              Expanded(
                child: _btn('停止', const Color(0xFF2A1A1A), const Color(0xFFDC2626), widget.onStop),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _btn('清空', const Color(0xFF1A2338), const Color(0xFFAEB9CC), _clear),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _btn('展开列表', AppColors.brand, Colors.white, () async => _expand()),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, Color bg, Color fg, Future<void> Function() onTap) {
    return InkWell(
      onTap: () => onTap(),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ),
    );
  }
}

class CaptureHit {
  final String time;
  final String host;
  final String ips;

  CaptureHit(this.time, this.host, this.ips);

  /// vpnLog 行格式：<毫秒时间戳> <域名> -> <ip,ip>
  static CaptureHit? parse(String line) {
    final idx = line.indexOf(' ');
    if (idx <= 0) return null;
    final ts = int.tryParse(line.substring(0, idx));
    final rest = line.substring(idx + 1);
    final arrow = rest.indexOf(' -> ');
    if (arrow <= 0) return null;
    final host = rest.substring(0, arrow).trim();
    final ipText = rest.substring(arrow + 4).trim();
    return CaptureHit(_fmt(ts), host, ipText == '?' ? '' : ipText);
  }

  static String _fmt(int? ms) {
    if (ms == null) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
