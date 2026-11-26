import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../theme/ref_draggable.dart';
import '../theme/glass_dialog.dart';
import '../agent/mcp.dart';
import 'settings_page.dart' show embedShell;

class McpPage extends StatefulWidget {
  final bool embedded;
  const McpPage({super.key, this.embedded = false});
  @override
  State<McpPage> createState() => _McpPageState();
}

class _McpPageState extends State<McpPage> {
  List<McpServer> _list = [];
  String _msg = '';
  final Map<String, String> _status = {}; // name -> '' / 'ok:N' / 'fail:原因'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await McpStore.load();
    if (mounted) setState(() => _list = l);
  }

  Future<void> _persist() => McpStore.save(_list);

  Future<void> _edit([McpServer? s]) async {
    final name = TextEditingController(text: s?.name ?? '');
    final url = TextEditingController(text: s?.url ?? '');
    final headers = TextEditingController(text: s == null ? '' : s.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'));
    final ok = await showGlassDialog<bool>(
      context: context,
      title: s == null ? '添加 MCP 服务器' : '编辑 MCP 服务器',
      confirmText: '保存',
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
        const SizedBox(height: 8),
        TextField(controller: url, decoration: const InputDecoration(labelText: 'HTTP URL')),
        const SizedBox(height: 8),
        TextField(controller: headers, maxLines: 3, decoration: const InputDecoration(labelText: '请求头')),
      ]),
    );
    if (ok == true && name.text.trim().isNotEmpty && url.text.trim().isNotEmpty) {
      final h = <String, String>{};
      for (final line in headers.text.split('\n')) {
        final i = line.indexOf(':');
        if (i > 0) h[line.substring(0, i).trim()] = line.substring(i + 1).trim();
      }
      final sv = McpServer(name: name.text.trim(), url: url.text.trim(), headers: h);
      final idx = s == null ? -1 : _list.indexOf(s);
      if (idx >= 0) {
        _list[idx] = sv;
      } else {
        _list.add(sv);
      }
      await _persist();
      await _load();
    }
  }

  Future<void> _test(McpServer s) async {
    setState(() => _status[s.name] = '测试中…');
    try {
      final tools = await McpClient.listTools(s);
      setState(() => _status[s.name] = '正常 · ${tools.length} 个工具');
    } catch (e) {
      setState(() => _status[s.name] = '失败：${e.toString().split('\n').first}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('MCP 服务器', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          if (_list.isEmpty)
            const EmptyState(icon: Icons.hub_outlined, text: '还没有 MCP 服务器\n点右上角 ＋ 添加（URL + 请求头）')
          else
            for (final s in _list)
              RefSwipeDelete(
                itemKey: 'mcp-${s.name}',
                onDelete: () async {
                  _list.remove(s);
                  await _persist();
                  await _load();
                },
                child: GlassCard(
                margin: const EdgeInsets.only(bottom: 8),
                onTap: () => _test(s),
                child: Row(children: [
                  const Icon(Icons.hub_outlined, size: 20, color: AppColors.brand),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                    if (_status[s.name] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _status[s.name]!,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: _status[s.name]!.startsWith('正常')
                                ? AppColors.green
                                : _status[s.name]!.startsWith('测试')
                                    ? AppColors.muted
                                    : AppColors.red,
                          ),
                        ),
                      ),
                  ])),
                  Transform.scale(
                    scale: 0.72,
                    child: Switch(
                      value: s.enabled,
                      activeThumbColor: AppColors.brand,
                      onChanged: (v) async {
                        setState(() => s.enabled = v);
                        await _persist();
                      },
                    ),
                  ),
                  IconButton(onPressed: () => _edit(s), icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF94A3B8))),
                ]),
                ),
              ),
          if (_msg.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg, style: const TextStyle(fontSize: 11.5, color: AppColors.muted))),
        ],
      );
    final addButton = IconButton(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add_rounded, color: Color(0xFF334155)),
    );
    if (widget.embedded) {
      return embedShell(title: 'MCP', actions: [addButton], body: body);
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('MCP', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [addButton],
      ),
      body: body,
    );
  }
}
