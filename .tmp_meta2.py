import io

p = 'lib/pages/scripts_page.dart'
s = io.open(p, encoding='utf-8').read()

# 1) slider 空值兜底
old = """  Widget _sliderField(String key, String label, double min, double max, String unit) {
    final c = _meta[key] ??= TextEditingController(
        text: widget.script.meta[key] ?? (key == 'opacity' ? '100' : (key == 'width' ? '320' : '520')));
    final v = (double.tryParse(c.text) ?? min).clamp(min, max);"""
new = """  Widget _sliderField(String key, String label, double min, double max, String unit) {
    final def = key == 'opacity' ? '100' : (key == 'width' ? '320' : '520');
    var c = _meta[key];
    if (c == null || c.text.trim().isEmpty) {
      final text = (widget.script.meta[key]?.trim().isNotEmpty ?? false)
          ? widget.script.meta[key]!
          : def;
      c?.dispose();
      c = TextEditingController(text: text);
      _meta[key] = c;
      widget.script.meta[key] = text;
    }
    final v = (double.tryParse(c.text) ?? double.parse(def)).clamp(min, max);"""
assert old in s, 'slider'
s = s.replace(old, new, 1)

# 2) 返回时自动保存（不用必须点右上角保存）
if 'PopScope' not in s:
    # 找到 _ScriptEditPageState 的 build 里的 Scaffold
    idx = s.find('class _ScriptEditPageState')
    b = s.find('  Widget build(BuildContext context) {\n    return Scaffold(', idx)
    if b > 0:
        s = s[:b] + """  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(""" + s[b + len('  Widget build(BuildContext context) {\n    return Scaffold('):]
        # 关闭 PopScope：需在 Scaffold 结束处加 )，找到该 build 的结尾 —— 用标志位近似处理
        # 简化：在文件末尾的 _ScriptEditPageState 类中，Scaffold 的 ");\n  }\n}" 处补一个 )
        target = """      ),
    );
  }

  static List<String> _metaKeys"""
        if target in s:
            s = s.replace(target, """      ),
    ));
  }

  static List<String> _metaKeys""", 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('ok:', 'PopScope' in s)
