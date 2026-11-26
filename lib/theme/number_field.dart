import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_theme.dart';

/// 数字输入行（替代滑块）：标签 + 右侧可填写数值 + 单位。
class NumberFieldRow extends StatefulWidget {
  final String label;
  final String suffix;
  final double value;
  final double min;
  final double max;
  final bool integer;
  final ValueChanged<double> onChanged;

  const NumberFieldRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix = '',
    this.min = 0,
    this.max = 1000000,
    this.integer = true,
  });

  @override
  State<NumberFieldRow> createState() => _NumberFieldRowState();
}

class _NumberFieldRowState extends State<NumberFieldRow> {
  late TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(covariant NumberFieldRow old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && _c.text != _fmt(widget.value)) {
      _c.text = _fmt(widget.value);
    }
  }

  String _fmt(double v) =>
      widget.integer ? v.round().toString() : v.toStringAsFixed(1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null) return;
    widget.onChanged(v.clamp(widget.min, widget.max));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: Text(widget.label, style: const TextStyle(fontSize: 12.5))),
        SizedBox(
          width: 96,
          child: TextField(
            controller: _c,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.numberWithOptions(decimal: !widget.integer),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(widget.integer ? r'[0-9]' : r'[0-9.]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              suffixText: widget.suffix.isEmpty ? null : widget.suffix,
              suffixStyle: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            onSubmitted: _commit,
            onEditingComplete: () => _commit(_c.text),
            onTapOutside: (_) {
              _commit(_c.text);
              FocusManager.instance.primaryFocus?.unfocus();
            },
          ),
        ),
      ]),
    );
  }
}
