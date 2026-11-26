import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../theme/toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';
import '../agent/agent_engine.dart';

/// 消息列表的一项：单条消息，或一组连续的工具调用。
sealed class ChatItem {}

class UserItem extends ChatItem {
  final ChatMsg msg;
  final int index;
  UserItem(this.msg, this.index);
}

class AssistantItem extends ChatItem {
  final ChatMsg msg;
  final int index;
  final bool typing; // 是否用打字机效果
  AssistantItem(this.msg, this.index, {this.typing = false});
}

class ToolGroupItem extends ChatItem {
  final List<ChatMsg> tools;
  /// 与 tools 按顺序对应的输出卡片（stream 视图）；数量可能少于 tools。
  final List<ChatMsg> outputs;
  ToolGroupItem(this.tools, {this.outputs = const []});
}

/// 工具返回的可视化卡片（由通用渲染器画）。
class ViewItem extends ChatItem {
  final ChatMsg msg;
  ViewItem(this.msg);
}

/// 把原始消息合并成渲染项：连续 tool 折叠成一组。
List<ChatItem> buildChatItems(List<ChatMsg> msgs, {bool typingLast = false}) {
  final out = <ChatItem>[];
  var i = 0;
  var lastAssistantIndex = -1;
  for (var k = 0; k < msgs.length; k++) {
    if (msgs[k].role != 'tool' && msgs[k].role != 'user') lastAssistantIndex = k;
  }
  while (i < msgs.length) {
    final m = msgs[i];
    if (m.role == 'tool') {
      // 一次请求里的工具调用与它们的终端输出合并成同一组：
      // 否则 tool / stream 交替会把分组切成好几段
      final group = <ChatMsg>[];
      final outputs = <ChatMsg>[];
      while (i < msgs.length) {
        final mm = msgs[i];
        if (mm.role == 'tool') {
          group.add(mm);
          i++;
          continue;
        }
        if (mm.role == 'view' && mm.view == 'stream') {
          outputs.add(mm);
          i++;
          continue;
        }
        break;
      }
      out.add(ToolGroupItem(group, outputs: outputs));
      continue;
    }
    if (m.role == 'view') {
      out.add(ViewItem(m));
      i++;
      continue;
    }
    if (m.role == 'user') {
      out.add(UserItem(m, i));
    } else {
      out.add(AssistantItem(m, i, typing: typingLast && i == lastAssistantIndex));
    }
    i++;
  }
  return out;
}

// ---------------- 用户消息 ----------------
class UserBubble extends StatelessWidget {
  final String text;
  final DateTime? time;
  const UserBubble({super.key, required this.text, this.time});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 290),
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: GlassContainer.card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(text,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.55)),
                ),
              ),
            ),
          ),
        ),
        if (time != null)
          Padding(
            padding: const EdgeInsets.only(right: 2, bottom: 4),
            child: Text(_hhmm(time!),
                style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
          ),
      ],
    );
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// ---------------- 助手消息（含代码块 / 打字机） ----------------
class AssistantBubble extends StatelessWidget {
  final String text;
  final bool typing;
  final int? elapsedMs;
  final DateTime? time;
  const AssistantBubble({super.key, required this.text, this.typing = false, this.elapsedMs, this.time});

  @override
  Widget build(BuildContext context) {
    return TypingFade(text: text, active: typing, child: _body(context));
  }

  Widget _body(BuildContext context) {
    final blocks = _split(text);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GlassContainer.card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (typing && text.trim().isEmpty)
            const _ThinkingDots()
          else
          for (var i = 0; i < blocks.length; i++)
            if (blocks[i].code == null)
              Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: MarkdownBody(
                        data: blocks[i].text,
                        selectable: false,
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(fontSize: 13, color: AppColors.text, height: 1.62),
                          h1: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.45),
                          h2: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.45),
                          h3: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.4),
                          strong: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text),
                          em: const TextStyle(fontStyle: FontStyle.italic),
                          listBullet: const TextStyle(fontSize: 12.5, color: AppColors.text, height: 1.6),
                          blockquote: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.6),
                          blockquoteDecoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(9),
                            border: const Border(left: BorderSide(color: AppColors.brand, width: 2)),
                          ),
                          blockquotePadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          code: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            backgroundColor: Color(0xFFF1F4F8),
                            color: Color(0xFF334155),
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE6EAF0)),
                          ),
                          codeblockPadding: const EdgeInsets.all(10),
                          horizontalRuleDecoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: Color(0xFFE6EAF0))),
                          ),
                          tableHead: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          tableBody: const TextStyle(fontSize: 12),
                          tableBorder: TableBorder.all(color: const Color(0xFFE6EAF0), width: 1),
                          blockSpacing: 7,
                          listIndent: 14,
                        ),
                      ),
                    )
            else
              CodeCard(code: blocks[i].text, lang: blocks[i].code!),
          if (elapsedMs != null || time != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [
                  if (time != null) _hhmm(time!),
                  if (elapsedMs != null)
                    '用时 ${(elapsedMs! / 1000).toStringAsFixed(elapsedMs! >= 10000 ? 0 : 1)}s',
                ].join(' · '),
                style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
              ),
            ),
        ],
        ),
      ),
    ),
  );
  }

  /// 拆成「普通文本 / 代码块」段。
  List<_Seg> _split(String s) {
    final re = RegExp(r'```([A-Za-z0-9_+-]*)\n?([\s\S]*?)```');
    final segs = <_Seg>[];
    var last = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > last) segs.add(_Seg(s.substring(last, m.start).trimRight()));
      segs.add(_Seg((m.group(2) ?? '').trimRight(), code: (m.group(1) ?? '').isEmpty ? 'code' : m.group(1)!));
      last = m.end;
    }
    if (last < s.length) segs.add(_Seg(s.substring(last).trimRight()));
    if (segs.isEmpty) segs.add(_Seg(s));
    return segs;
  }
}

class _Seg {
  final String text;
  final String? code;
  _Seg(this.text, {this.code});
}

// ---------------- 代码块卡片 ----------------
class CodeCard extends StatelessWidget {
  final String code;
  final String lang;
  const CodeCard({super.key, required this.code, required this.lang});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFEFF2F7))),
            ),
            child: Row(children: [
              Text(lang, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  showToast(context, '已复制代码');
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                  child: Row(children: [
                    Icon(Icons.copy_rounded, size: 12, color: Color(0xFFB6C2D1)),
                    SizedBox(width: 3),
                    Text('复制', style: TextStyle(fontSize: 10.5, color: Color(0xFFB6C2D1))),
                  ]),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(code,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.5, color: Color(0xFF1F2937))),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 打字机 ----------------
/// 思考中：三个点循环微跳动，避免看起来像卡住。
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('思考中',
            style: TextStyle(
                fontSize: 12.5,
                color: AppColors.muted.withValues(alpha: 0.7 + 0.3 * math.sin(_c.value * 2 * math.pi).abs()))),
        const SizedBox(width: 6),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Transform.translate(
              offset: Offset(0, -2.2 * math.sin((_c.value * 2 * math.pi) - i * 0.7)),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.3 + 0.6 * i / 3),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ---------------- 工具调用分组 ----------------
class ToolGroupTile extends StatefulWidget {
  final List<ChatMsg> tools;
  final List<ChatMsg> outputs;
  const ToolGroupTile({super.key, required this.tools, this.outputs = const []});
  @override
  State<ToolGroupTile> createState() => _ToolGroupTileState();
}

class _ToolGroupTileState extends State<ToolGroupTile> {
  late bool _open = widget.tools.any((t) => !t.ok) && widget.tools.length <= 8;
  final Set<int> _expanded = {};

  /// 把「调用 shell {cmd: xxx}」压成 xxx
  static String _cmdOf(ChatMsg t) {
    var s = t.text.trim();
    final name = t.toolName ?? '';
    if (name.isNotEmpty && s.startsWith('调用 $name')) s = s.substring(('调用 $name').length).trim();
    final m = RegExp(r'cmd:\s*(.*)\}\s*$', dotAll: true).firstMatch(s);
    if (m != null) s = m.group(1)!.trim();
    return s.replaceAll('\n', ' ');
  }

  static List<String> _linesOf(ChatMsg? out) =>
      ((out?.viewData?['lines'] as List?) ?? const []).map((e) => '$e').toList();

  @override
  Widget build(BuildContext context) {
    final n = widget.tools.length;
    if (n == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _rowCard(0),
      );
    }

    final failed = widget.tools.any((t) => !t.ok);
    final fails = widget.tools.where((t) => !t.ok).toList();
    String errLine = '';
    for (final t in widget.tools) {
      if (t.ok) continue;
      final s = t.text.trim();
      if (s.isEmpty || s.startsWith('调用 ')) continue;
      errLine = s.split('\n').first;
      break;
    }
    if (errLine.isEmpty && fails.isNotEmpty) errLine = fails.first.text.trim();
    final counts = <String, int>{};
    for (final t in widget.tools) {
      final k = t.toolName ?? 'tool';
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final stat = '${counts.entries.map((e) => '${e.key}×${e.value}').join(' · ')}'
        '${fails.isEmpty ? '' : ' · 失败 ${fails.length}'}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1),
        boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 12, 11),
              child: Row(children: [
                Icon(failed ? Icons.cancel_rounded : Icons.check_circle_rounded,
                    size: 14, color: failed ? AppColors.red : const Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text('$n 次工具调用',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 9.5, color: Color(0xFFB6C2D3), fontFamily: 'monospace')),
                      if (errLine.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '失败：${errLine.length > 90 ? '${errLine.substring(0, 90)}…' : errLine}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9, color: Color(0xFFDC2626)),
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: const Icon(Icons.expand_more_rounded, size: 16, color: Color(0xFFCBD5E1)),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (var k = 0; k < widget.tools.length; k++) _rowCard(k)],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _rowCard(int k) {
    final t = widget.tools[k];
    final out = k < widget.outputs.length ? widget.outputs[k] : null;
    final lines = _linesOf(out);
    final open = _expanded.contains(k);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFD),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFF0F4FA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: lines.isEmpty ? null : () => setState(() {
                    if (open) {
                      _expanded.remove(k);
                    } else {
                      _expanded.add(k);
                    }
                  }),
              borderRadius: BorderRadius.circular(11),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                child: Row(children: [
                  Icon(t.ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 12, color: t.ok ? const Color(0xFF10B981) : AppColors.red),
                  const SizedBox(width: 6),
                  Text(t.toolName ?? 'tool',
                      style: const TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_cmdOf(t),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF64748B), fontFamily: 'monospace')),
                  ),
                  if (lines.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${lines.length} 行',
                          style: const TextStyle(
                              fontSize: 9, color: Color(0xFF94A3B8), fontFamily: 'monospace')),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.expand_more_rounded, size: 13, color: Color(0xFFCBD5E1)),
                    ),
                  ],
                ]),
              ),
            ),
            if (open && lines.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E293B),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                      ),
                      child: Row(children: [
                        for (final c in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)])
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                          ),
                        const Spacer(),
                        const Text('输出',
                            style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.all(9),
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: SingleChildScrollView(
                        child: Text(
                          lines.length > 40 ? lines.sublist(lines.length - 40).join('\n') : lines.join('\n'),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 9.5, color: Color(0xFFCBD5E1), height: 1.55),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 轻量 Markdown：**粗体** / *斜体* / `行内代码` / 行首 - 列表 / # 标题。


/// 消息入场：从下方 8px 淡入，只播一次。
class EnterFade extends StatefulWidget {
  final Widget child;
  final Duration duration;
  const EnterFade({super.key, required this.child, this.duration = const Duration(milliseconds: 190)});

  @override
  State<EnterFade> createState() => _EnterFadeState();
}

class _EnterFadeState extends State<EnterFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.05),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}


/// 流式输出时，新到的内容短促淡入，避免整块跳动。
class TypingFade extends StatefulWidget {
  final String text;
  final bool active;
  final Widget child;
  const TypingFade({super.key, required this.text, required this.active, required this.child});

  @override
  State<TypingFade> createState() => _TypingFadeState();
}

class _TypingFadeState extends State<TypingFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    value: 1,
  );
  late final Animation<double> _o =
      Tween<double>(begin: 0.82, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant TypingFade old) {
    super.didUpdateWidget(old);
    if (widget.active && widget.text != old.text) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _o, child: widget.child);
}
