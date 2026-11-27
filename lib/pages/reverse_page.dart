import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../theme/glass_dialog.dart';
import '../theme/toast.dart';
import '../native/gmem.dart';
import '../theme/ref_draggable.dart';
import '../state/chat_refs.dart';
import '../native/native_bridge.dart';

/// 逆向：应用列表 → 文件树 → SO；内存按值搜索。
class ReversePage extends StatefulWidget {
  const ReversePage({super.key});
  @override
  State<ReversePage> createState() => _ReversePageState();
}

class _ReversePageState extends State<ReversePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: const Text('逆向', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                for (var i = 0; i < 2; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(['应用', '文件'][i], style: const TextStyle(fontSize: 12)),
                      selected: _tab == i,
                      onSelected: (_) => setState(() => _tab = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: const [_AppsTab(), _FilesTab()],
      ),
    );
  }
}

// ——— 应用列表 ———
class _AppsTab extends StatefulWidget {
  const _AppsTab();
  @override
  State<_AppsTab> createState() => _AppsTabState();
}

class _AppsTabState extends State<_AppsTab> {
  List<Map<String, dynamic>>? _apps;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _ensureStorage();
    final l = await NativeBridge.listApps();
    if (mounted) setState(() => _apps = l);
  }

  /// 没有「所有文件访问」时先弹说明再跳设置（Android 11+ 不会弹允许框）。
  Future<void> _ensureStorage() async {
    final st = await NativeBridge.permStatus();
    if (st['allFiles'] == true) return;
    if (!mounted) return;
    final go = await showGlassDialog<bool>(
      context: context,
      title: '需要文件访问权限',
      confirmText: '去开启',
      content: const Text(
        '读取已安装应用的 APK、浏览文件都需要「所有文件访问」权限。\n\n点击「去开启」后在系统设置里把「允许管理所有文件」打开，返回即可。',
        style: TextStyle(fontSize: 12.5, height: 1.6),
      ),
    );
    if (go == true) {
      await NativeBridge.requestStorage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    if (apps == null) return const Center(child: CircularProgressIndicator());
    if (apps.isEmpty) {
      return const EmptyState(icon: Icons.apps_rounded, text: '没有读到应用\n去「工具授权/软件权限」授予存储与查询权限');
    }
    final q = _q.toLowerCase();
    final filtered = q.isEmpty
        ? apps
        : apps.where((a) {
            final label = (a['label'] ?? '').toString().toLowerCase();
            final pkg = (a['package'] ?? a['pkg'] ?? '').toString().toLowerCase();
            return label.contains(q) || pkg.contains(q);
          }).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(
            hintText: '搜索应用名 / 包名',
            prefixIcon: Icon(Icons.search_rounded, size: 18),
          ),
        ),
      ),
      Expanded(
        child: filtered.isEmpty
            ? const Center(child: Text('没有匹配的应用', style: TextStyle(fontSize: 12, color: AppColors.muted)))
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                children: [
                  for (final a in filtered)
                    GlassCard(
                      margin: const EdgeInsets.only(bottom: 6),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _ApkFilesPage(apk: (a['apk'] ?? '').toString(), title: (a['label'] ?? '').toString()),
                      )),
                      child: RefDraggable(
                        ref: ChatRef(
                          type: 'app',
                          name: (a['label'] ?? '').toString(),
                          detail: (a['package'] ?? a['pkg'] ?? '').toString(),
                        ),
                        child: Row(children: [
                        const Icon(Icons.android_rounded, size: 20, color: Color(0xFF3DDC84)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((a['label'] ?? '').toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text((a['package'] ?? a['pkg'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                          ]),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFCBD5E1)),
                      ]),
                      ),
                    ),
                ],
              ),
      ),
    ]);
  }
}

// ——— APK / 文件树 ———
class _ApkFilesPage extends StatefulWidget {
  final String apk;
  final String title;
  const _ApkFilesPage({required this.apk, required this.title});
  @override
  State<_ApkFilesPage> createState() => _ApkFilesPageState();
}

class _ApkFilesPageState extends State<_ApkFilesPage> {
  List<Map<String, dynamic>>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await NativeBridge.zipList(widget.apk);
    if (mounted) setState(() => _entries = l);
  }

  @override
  Widget build(BuildContext context) {
    final e = _entries;
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: '解包导出到 Download',
            icon: const Icon(Icons.unarchive_outlined, size: 20, color: Color(0xFFD4DBE8)),
            onPressed: () async {
              final name = widget.title.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]+'), '_');
              final dir = '/sdcard/Download/g_unpack/$name';
              final r = await NativeBridge.exec(
                'mkdir -p "$dir" && unzip -o "${widget.apk}" -d "$dir" >/dev/null 2>&1 && echo OK',
                timeout: 120,
              );
              if (!context.mounted) return;
              showToast(context, r.ok ? '已解包到 Download/g_unpack/$name' : '解包失败：${r.stderr}', error: !r.ok);
            },
          ),
        ],
      ),
      body: e == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final x in e)
                  RefDraggable(
                    ref: ChatRef(
                      type: x['name'].toString().endsWith('.so') ? 'so' : 'file',
                      name: (x['name'] ?? '').toString(),
                      detail: '${widget.apk}!/${x['name']}',
                    ),
                    child: GlassCard(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    onTap: () {
                      final name = (x['name'] ?? '').toString();
                      if (name.endsWith('.so')) {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SoPage(path: widget.apk, entry: name)));
                      }
                    },
                    child: Row(children: [
                      Icon(
                        (x['dir'] == true) ? Icons.folder_outlined : (x['name'].toString().endsWith('.so') ? Icons.memory_rounded : Icons.insert_drive_file_outlined),
                        size: 16,
                        color: (x['name'].toString().endsWith('.so')) ? AppColors.brand : AppColors.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text((x['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'))),
                    ]),
                  ),
                  ),
              ],
            ),
    );
  }
}

class _SoPage extends StatefulWidget {
  final String path;
  final String entry;
  const _SoPage({required this.path, required this.entry});
  @override
  State<_SoPage> createState() => _SoPageState();
}

class _SoPageState extends State<_SoPage> with SingleTickerProviderStateMixin {
  final _sections = TextEditingController(text: '40');
  final _symbols = TextEditingController(text: '80');
  final _addr = TextEditingController(text: '0');
  final _cnt = TextEditingController(text: '200');
  final _asm = TextEditingController(text: 'mov x0, #0');
  final _pid = TextEditingController();

  late final TabController _tc = TabController(length: 7, vsync: this);

  Map<String, String> _parts = {};
  List<(String, String)> _symList = [];
  String _disasm = '';
  String _asmResult = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _tc.dispose();
    _sections.dispose();
    _symbols.dispose();
    _addr.dispose();
    _cnt.dispose();
    _asm.dispose();
    _pid.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    final sec = int.tryParse(_sections.text.trim()) ?? 40;
    final sym = int.tryParse(_symbols.text.trim()) ?? 80;
    final r = await NativeBridge.exec(
      'cd /data/local/tmp 2>/dev/null; '
      'unzip -p "${widget.path}" "${widget.entry}" > /data/local/tmp/x.so 2>/dev/null || '
      'cp "${widget.path}" /data/local/tmp/x.so 2>/dev/null; '
      'if command -v readelf >/dev/null 2>&1; then '
      'echo "###ELF"; readelf -h /data/local/tmp/x.so 2>/dev/null | head -20; '
      'echo "###SECTIONS"; readelf -S /data/local/tmp/x.so 2>/dev/null | head -$sec; '
      'echo "###SYMBOLS"; readelf --dyn-syms /data/local/tmp/x.so 2>/dev/null | head -$sym; '
      'echo "###JNI"; readelf --dyn-syms /data/local/tmp/x.so 2>/dev/null | grep -E "Java_|JNI_" | head -$sym; '
      'echo "###STRINGS"; (strings -n 6 /data/local/tmp/x.so 2>/dev/null || true) | head -$sym; '
      'echo "###NEEDED"; readelf -d /data/local/tmp/x.so 2>/dev/null | grep NEEDED; '
      'else echo "###ELF"; echo "环境无 readelf（可在 Alpine 里 apk add binutils）"; fi',
      timeout: 90,
    );
    final parts = <String, String>{};
    String cur = 'ELF';
    final buf = StringBuffer();
    for (final line in r.stdout.split('\n')) {
      if (line.startsWith('###')) {
        parts[cur] = buf.toString().trim();
        buf.clear();
        cur = line.substring(3).trim();
      } else {
        buf.writeln(line);
      }
    }
    parts[cur] = buf.toString().trim();

    // 解析符号（Value + Name）
    final syms = <(String, String)>[];
    final re = RegExp(r'^\s*\d+:\s+([0-9a-fA-F]{4,16})\s+\d+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)');
    for (final line in (parts['SYMBOLS'] ?? '').split('\n')) {
      final m = re.firstMatch(line);
      if (m != null) syms.add((m.group(1)!, m.group(2)!));
    }

    if (!mounted) return;
    setState(() {
      _parts = parts;
      _symList = syms;
      _loading = false;
    });
  }

  Future<void> _runDisasm() async {
    setState(() => _disasm = '反汇编中…');
    await NativeBridge.exec(
      'cd /data/local/tmp; unzip -p "${widget.path}" "${widget.entry}" > x.so 2>/dev/null || cp "${widget.path}" x.so 2>/dev/null',
      timeout: 60,
    );
    final json = await NativeBridge.disasmFile(
      '/data/local/tmp/x.so',
      _addr.text.trim().isEmpty ? '0' : _addr.text.trim(),
      count: int.tryParse(_cnt.text.trim()) ?? 200,
    );
    if (!mounted) return;
    if (json == null) {
      setState(() => _disasm = '反汇编失败（disasm 库未加载或地址不合法）');
      return;
    }
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      if (m['ok'] != true) {
        setState(() => _disasm = '失败：${m['msg']}');
        return;
      }
      final items = (m['items'] as List?) ?? const [];
      final sb = StringBuffer();
      for (final it in items) {
        final x = it as Map<String, dynamic>;
        final a = (x['addr'] ?? '').toString().padLeft(8, '0');
        sb.writeln('0x$a  ${(x['bytes'] ?? '').toString().padRight(10)}  ${x['mnemonic']} ${x['opStr']}');
      }
      setState(() => _disasm = items.isEmpty ? '（该地址无反汇编结果）' : sb.toString());
    } catch (e) {
      setState(() => _disasm = '解析失败：$e');
    }
  }

  /// 汇编 → 写入目标进程内存
  Future<void> _assembleAndWrite() async {
    setState(() => _asmResult = '汇编中…');
    final addr = _addr.text.trim().isEmpty ? '0' : _addr.text.trim();
    final r = await NativeBridge.assembleHex(_asm.text.trim(), addr: addr);
    if (!mounted) return;
    if (r == null) {
      setState(() => _asmResult = '汇编失败：引擎未加载');
      return;
    }
    if (r['ok'] != true) {
      setState(() => _asmResult = '汇编失败：${r['msg']}');
      return;
    }
    final hex = (r['hex'] ?? '').toString();
    final pid = int.tryParse(_pid.text.trim());
    if (pid == null) {
      setState(() => _asmResult = 'hex = $hex\n（填了 PID 才能写入内存）');
      return;
    }
    setState(() => _asmResult = 'hex = $hex\n写入中…');
    final ok = await Gmem.writeHex(pid, '0x${addr.replaceFirst('0x', '')}', hex);
    if (!mounted) return;
    setState(() => _asmResult = 'hex = $hex\n${ok ? '✓ 已写入 pid $pid @ $addr' : '✗ 写入失败（root 未授权？）'}');
  }

  Widget _mono(String text) => SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          text.isEmpty ? '（无数据）' : text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.55),
        ),
      );

  Widget _numRow(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          SizedBox(
            width: 90,
            child: TextField(
              controller: c,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: label, isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: _run, icon: const Icon(Icons.play_arrow_rounded, color: AppColors.brand)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final name = widget.entry.split('/').last;
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFF141B2E),
        elevation: 0,
        title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: _run, icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFFD4DBE8))),
        ],
        bottom: TabBar(
          controller: _tc,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.brand,
          unselectedLabelColor: const Color(0xFF7886A0),
          indicatorColor: AppColors.brand,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: const [
            Tab(text: 'ELF'),
            Tab(text: '节表'),
            Tab(text: '符号'),
            Tab(text: 'JNI'),
            Tab(text: '字符串'),
            Tab(text: '依赖'),
            Tab(text: '反汇编'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : TabBarView(controller: _tc, children: [
              _mono(_parts['ELF'] ?? ''),
              Column(children: [
                _numRow(_sections, '行数'),
                Expanded(child: _mono(_parts['SECTIONS'] ?? '')),
              ]),
              Column(children: [
                _numRow(_symbols, '行数'),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('点符号 → 跳转反汇编', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: _symList.length,
                    itemBuilder: (_, i) {
                      final (addr, sym) = _symList[i];
                      return GlassCard(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        onTap: () {
                          _addr.text = addr;
                          _tc.animateTo(6);
                          _runDisasm();
                        },
                        child: Row(children: [
                          Text('0x$addr',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: AppColors.brand)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(sym,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFFCBD5E1)),
                        ]),
                      );
                    },
                  ),
                ),
              ]),
              _mono(_parts['JNI'] ?? ''),
              _mono(_parts['STRINGS'] ?? ''),
              _mono(_parts['NEEDED'] ?? ''),
              Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _addr,
                        decoration: const InputDecoration(
                          labelText: '起始地址 (hex)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: _cnt,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '条数', isDense: true),
                      ),
                    ),
                    IconButton(
                      onPressed: _runDisasm,
                      icon: const Icon(Icons.memory_rounded, color: AppColors.brand),
                    ),
                  ]),
                ),
                const Divider(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _asm,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                        decoration: const InputDecoration(labelText: '汇编指令', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 76,
                      child: TextField(
                        controller: _pid,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'PID', isDense: true),
                      ),
                    ),
                    IconButton(
                      onPressed: _assembleAndWrite,
                      tooltip: '汇编并写入内存',
                      icon: const Icon(Icons.edit_note_rounded, color: AppColors.brand),
                    ),
                  ]),
                ),
                if (_asmResult.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(_asmResult,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: Color(0xFFAEB9CC))),
                    ),
                  ),
                Expanded(child: _mono(_disasm)),
              ]),
            ]),
    );
  }
}

// ——— 文件（设备目录）———
class _FilesTab extends StatefulWidget {
  const _FilesTab();
  @override
  State<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<_FilesTab> {
  String _path = '/storage/emulated/0';
  List<String> _items = [];

  @override
  void initState() {
    super.initState();
    _ls();
  }

  Future<void> _ls() async {
    final r = await NativeBridge.exec('ls -1 "$_path" 2>&1');
    if (mounted) setState(() => _items = (r.stdout).split('\n').where((e) => e.trim().isNotEmpty && !e.startsWith('total')).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Row(children: [
          IconButton(onPressed: () { _path = _path.replaceAll(RegExp(r'/[^/]+$'), ''); if (_path.isEmpty) _path = '/'; _ls(); }, icon: const Icon(Icons.arrow_upward_rounded, size: 18)),
          Expanded(child: Text(_path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
          IconButton(onPressed: _ls, icon: const Icon(Icons.refresh_rounded, size: 18)),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            for (final it in _items)
              RefDraggable(
                ref: ChatRef(type: 'file', name: it, detail: '$_path/$it'),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined, size: 18, color: AppColors.muted),
                  title: Text(it, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  onTap: () { _path = '$_path/$it'; _ls(); },
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}
