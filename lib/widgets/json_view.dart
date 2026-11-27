import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 把 JSON 组件树渲染成 Flutter Widget（给 JS 插件自定义 UI 用）。
///
/// 组件：stack / row / text / metric / list / keyValue / table / actions /
/// options / confirm / progress / callout / divider / spacer / chart(bar|hbar)。
class JsonView extends StatelessWidget {
  final dynamic json;
  final void Function(String action, Map<String, dynamic> args)? onAction;

  const JsonView(this.json, {super.key, this.onAction});

  @override
  Widget build(BuildContext context) {
    return _render(json, onAction);
  }
}

Widget _render(dynamic node, void Function(String, Map<String, dynamic>)? onAction) {
  if (node is List) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final c in node) _render(c, onAction)],
    );
  }
  if (node is! Map) {
    return Text('${node ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.text));
  }
  final type = (node['type'] ?? '').toString();
  final m = Map<String, dynamic>.from(node);

  switch (type) {
    case 'stack':
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final c in (m['children'] as List? ?? const [])) _render(c, onAction)],
      );
    case 'row':
      return Row(
        children: [for (final c in (m['children'] as List? ?? const [])) _render(c, onAction)],
      );
    case 'divider':
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 1, color: Color(0xFF1A2338)),
      );
    case 'spacer':
      return SizedBox(height: ((m['h'] as num?)?.toDouble() ?? 8));
    case 'text':
      return _text(m);
    case 'metric':
      return _metric(m);
    case 'list':
      return _list(m, onAction);
    case 'keyValue':
      return _keyValue(m);
    case 'table':
      return _table(m);
    case 'actions':
      return _actions(m, onAction);
    case 'options':
      return _options(m, onAction);
    case 'confirm':
      return _confirm(m, onAction);
    case 'progress':
      return _progress(m);
    case 'callout':
      return _callout(m);
    case 'chart':
      return _chart(m);
    default:
      return Text('${m['text'] ?? type}',
          style: const TextStyle(fontSize: 12, color: AppColors.text));
  }
}

Widget _text(Map m) {
  final tone = (m['tone'] ?? '').toString();
  final size = (m['size'] ?? '').toString();
  final weight = (m['weight'] ?? '').toString();
  final color = tone == 'muted'
      ? AppColors.muted
      : (tone == 'bad'
          ? AppColors.red
          : (tone == 'good' ? AppColors.green : AppColors.text));
  final fontSize = size == 'title'
      ? 15.0
      : (size == 'subtitle' ? 13.0 : 12.0);
  final fw = weight == 'bold'
      ? FontWeight.w800
      : (weight == 'semibold' ? FontWeight.w600 : FontWeight.w400);
  return Text('${m['text'] ?? ''}',
      style: TextStyle(fontSize: fontSize, fontWeight: fw, color: color));
}

Widget _metric(Map m) {
  final value = '${m['value'] ?? '—'}';
  final label = '${m['label'] ?? ''}';
  final caption = (m['caption'] ?? '').toString();
  final tone = (m['tone'] ?? '').toString();
  final vColor = tone == 'good'
      ? AppColors.green
      : (tone == 'warn' ? const Color(0xFFD97706) : (tone == 'bad' ? AppColors.red : AppColors.text));
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: vColor)),
        if (caption.isNotEmpty)
          Text(caption, style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
      ],
    ),
  );
}

Widget _list(Map m, onAction) {
  final items = (m['items'] as List? ?? const []);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final raw in items)
        _listTile(raw is Map ? Map<String, dynamic>.from(raw) : {'title': '$raw'}, onAction),
    ],
  );
}

Widget _listTile(Map it, onAction) {
  final action = it['action'];
  final trailing = (it['trailing'] ?? '').toString();
  final tone = (it['tone'] ?? '').toString();
  final leading = tone == 'good'
      ? Icons.check_circle_rounded
      : (tone == 'bad' ? Icons.error_rounded : (tone == 'warn' ? Icons.warning_rounded : null));
  final row = Row(
    children: [
      if (leading != null)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Icon(leading, size: 15, color: tone == 'good' ? AppColors.green : (tone == 'bad' ? AppColors.red : const Color(0xFFD97706))),
        ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${it['title'] ?? ''}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text)),
            if (it['subtitle'] != null)
              Text('${it['subtitle']}',
                  style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
          ],
        ),
      ),
      if (trailing.isNotEmpty)
        Text(trailing, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
    ],
  );
  final content = Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFF1A2338))),
    ),
    child: row,
  );
  if (action == null) return content;
  return InkWell(
    onTap: () => onAction?.call('$action', const {}),
    child: content,
  );
}

Widget _keyValue(Map m) {
  final items = (m['items'] as List? ?? const []);
  final rows = <(String, String)>[];
  for (final raw in items) {
    if (raw is List && raw.length >= 2) {
      rows.add(('${raw[0]}', '${raw[1]}'));
    } else if (raw is Map) {
      rows.add(('${raw['label'] ?? ''}', '${raw['value'] ?? ''}'));
    }
  }
  return Column(
    children: [
      for (final (k, v) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 72, child: Text(k, style: const TextStyle(fontSize: 10, color: AppColors.muted))),
              Expanded(child: Text(v, style: const TextStyle(fontSize: 11.5, color: AppColors.text))),
            ],
          ),
        ),
    ],
  );
}

Widget _table(Map m) {
  final columns = (m['columns'] as List? ?? const []).map((c) => c is Map ? '${c['label'] ?? ''}' : '$c').toList();
  final rows = (m['rows'] as List? ?? const []);
  return Table(
    border: TableBorder(horizontalInside: BorderSide(color: const Color(0xFF1A2338), width: 0.5)),
    columnWidths: const {0: IntrinsicColumnWidth()},
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    children: [
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFF141B2E)),
        children: [for (final c in columns) Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Text(c, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.muted)),
        )],
      ),
      for (final row in rows)
        TableRow(
          children: [
            for (final cell in (row as List? ?? const []))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                child: Text('$cell', style: const TextStyle(fontSize: 10.5, color: AppColors.text)),
              ),
          ],
        ),
    ],
  );
}

Widget _actions(Map m, onAction) {
  final items = (m['items'] as List? ?? const []);
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final raw in items)
        if (raw is Map)
          _actionBtn(Map<String, dynamic>.from(raw), onAction),
    ],
  );
}

Widget _actionBtn(Map it, onAction) {
  final label = '${it['label'] ?? ''}';
  final action = it['action'];
  final primary = it['style'] == 'primary';
  return Material(
    color: primary ? AppColors.brand : const Color(0xFF1A2338),
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onAction?.call('$action', const {}),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: primary ? Colors.white : const Color(0xFFAEB9CC))),
      ),
    ),
  );
}

Widget _options(Map m, onAction) {
  final id = '${m['id'] ?? ''}';
  final options = (m['options'] as List? ?? const []);
  final selected = (m['selected'] ?? '').toString();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final raw in options)
        if (raw is Map)
          _optionRow(id, Map<String, dynamic>.from(raw), selected, onAction),
    ],
  );
}

Widget _optionRow(String id, Map it, String selected, onAction) {
  final label = '${it['label'] ?? ''}';
  final value = '${it['value'] ?? label}';
  final isSel = selected == value;
  return InkWell(
    onTap: () => onAction?.call('$id', {'value': value}),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: isSel ? AppColors.brand : const Color(0xFFCBD5E1), width: isSel ? 5 : 1.5),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text))),
        ],
      ),
    ),
  );
}

Widget _confirm(Map m, onAction) {
  final id = '${m['id'] ?? ''}';
  final confirmLabel = '${m['confirmLabel'] ?? '确定'}';
  final cancelLabel = '${m['cancelLabel'] ?? '取消'}';
  return Row(
    children: [
      Expanded(
        child: _actionBtn({'label': cancelLabel, 'action': '__cancel__', 'style': 'plain'}, onAction),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _actionBtn({'label': confirmLabel, 'action': id, 'style': 'primary'}, onAction),
      ),
    ],
  );
}

Widget _progress(Map m) {
  final value = ((m['value'] as num?)?.toDouble() ?? 0);
  final max = ((m['max'] as num?)?.toDouble() ?? 100);
  final pct = (max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0));
  final label = '${m['label'] ?? ''}';
  final caption = '${m['caption'] ?? ''}';
  final tone = '${m['tone'] ?? ''}';
  final color = tone == 'good' ? AppColors.green : (tone == 'bad' ? AppColors.red : AppColors.brand);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (label.isNotEmpty)
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.text, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LinearProgressIndicator(value: pct, minHeight: 8, color: color, backgroundColor: const Color(0xFF1A2338)),
      ),
      if (caption.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(caption, style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
        ),
    ],
  );
}

Widget _callout(Map m) {
  final text = '${m['text'] ?? ''}';
  final tone = '${m['tone'] ?? 'info'}';
  final (icon, color, bg) = switch (tone) {
    'good' => (Icons.check_circle_rounded, AppColors.green, const Color(0xFF12251C)),
    'bad' => (Icons.error_rounded, AppColors.red, const Color(0xFF2A1A1A)),
    'warn' => (Icons.warning_rounded, const Color(0xFFD97706), const Color(0xFF2A2012)),
    _ => (Icons.info_rounded, AppColors.brand, const Color(0xFF1E2A45)),
  };
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 7),
        Expanded(child: Text(text, style: TextStyle(fontSize: 11.5, color: color, height: 1.5))),
      ],
    ),
  );
}

Widget _chart(Map m) {
  final kind = '${m['kind'] ?? 'bar'}';
  final categories = (m['categories'] as List? ?? const []).map((e) => '$e').toList();
  final series = (m['series'] as List? ?? const []);
  final unit = '${m['unit'] ?? ''}';
  final caption = '${m['caption'] ?? ''}';
  final values = (series.isNotEmpty && series[0] is Map)
      ? ((series[0] as Map)['values'] as List? ?? const []).map((e) => (e is num) ? e.toDouble() : double.tryParse('$e') ?? 0).toList()
      : <double>[];
  if (values.isEmpty) return const SizedBox.shrink();
  final maxV = values.reduce(math.max);
  final isH = kind == 'hbar';

  Widget bar(int i) {
    final v = values[i];
    final frac = maxV <= 0 ? 0.0 : (v / maxV).clamp(0.0, 1.0);
    final label = categories.isEmpty ? '' : categories[i.clamp(0, categories.length - 1)];
    if (isH) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 48, child: Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 12,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: frac,
                child: Container(
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(4)),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 4),
                  child: Text('$v$unit', style: const TextStyle(fontSize: 8, color: Colors.white)),
                ),
              ),
            ),
          ),
        ]),
      );
    }
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('$v$unit', style: const TextStyle(fontSize: 8, color: AppColors.muted)),
          const SizedBox(height: 3),
          Container(height: 80 * frac, width: 16, decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 8, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (isH)
        Column(children: [for (var i = 0; i < values.length; i++) bar(i)])
      else
        SizedBox(height: 120, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [for (var i = 0; i < values.length; i++) bar(i)])),
      if (caption.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(caption, style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
        ),
    ],
  );
}
