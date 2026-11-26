import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../agent/permission.dart';

/// AI 请求使用工具时的内联授权卡片。
class PermissionPanel extends StatefulWidget {
  final String tool;
  final Map<String, String> args;
  final void Function(String choice) onChoice; // once / always / deny
  final bool dimmed;
  final String mode; // build / plan / auto
  const PermissionPanel({
    super.key,
    required this.tool,
    required this.args,
    required this.onChoice,
    this.dimmed = false,
    this.mode = 'build',
  });

  @override
  State<PermissionPanel> createState() => _PermissionPanelState();
}

class _PermissionPanelState extends State<PermissionPanel> {
  bool _expanded = true;

  bool get _hr => PermissionPolicy.isHighRisk(widget.tool);

  @override
  Widget build(BuildContext context) {
    final cmd = widget.args['cmd'] ?? '';
    final rest = widget.args.entries
        .where((e) => e.key != 'cmd')
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
    final modeLabel = widget.mode == 'auto' ? '自动模式' : '执行模式';

    return AnimatedOpacity(
      opacity: widget.dimmed ? 0.4 : 1,
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hr ? const Color(0xFFFECACA) : const Color(0xFFE6EAF0)),
          boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  Icon(
                    _hr ? Icons.warning_amber_rounded : Icons.shield_outlined,
                    size: 17,
                    color: _hr ? const Color(0xFFDC2626) : AppColors.brand,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _hr ? '高危操作' : '允许执行？',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: _hr ? const Color(0xFFB91C1C) : AppColors.text,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _hr ? const Color(0xFFFEF2F2) : const Color(0xFFEAF1FE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _hr ? '高危' : modeLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: _hr ? const Color(0xFFDC2626) : AppColors.brand,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18, color: const Color(0xFFCBD5E1)),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 25),
                child: Text('工具  ${widget.tool}',
                    style: const TextStyle(
                        fontSize: 10.5, fontFamily: 'monospace', color: AppColors.muted)),
              ),
              if (cmd.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1220),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    cmd,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 10.5, color: Color(0xFF7DD3FC), height: 1.6),
                  ),
                ),
              ],
              if (rest.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    rest,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 10.5, color: Color(0xFF475569), height: 1.5),
                  ),
                ),
              ],
              if (_hr) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text(
                    '这一步无法撤销，请确认命令内容后再允许。',
                    style: TextStyle(fontSize: 10, color: Color(0xFFB91C1C), height: 1.5),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _btn('拒绝', const Color(0xFFF1F4F8), const Color(0xFF475569),
                      () => widget.onChoice('deny')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _btn(
                    '允许一次',
                    _hr ? const Color(0xFFDC2626) : AppColors.brand,
                    Colors.white,
                    () => widget.onChoice('once'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _btn('始终允许', const Color(0xFFEAF1FE), AppColors.brand,
                      () => widget.onChoice('always')),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ),
      ),
    );
  }
}
