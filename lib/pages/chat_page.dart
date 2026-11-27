import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../theme/liquid_glass.dart';
import '../theme/glass.dart';
import '../state/theme_controller.dart';
import '../theme/glass_dialog.dart';
import '../theme/toast.dart';
import '../widgets/choose_sheet.dart';
import '../state/agent_controller.dart';
import '../state/active_session.dart';
import '../state/ui_state.dart';
import '../state/chat_refs.dart';
import '../state/workspace.dart';
import '../data/db_provider.dart';
import '../agent/agent_engine.dart';
import '../agent/provider_store.dart';
import '../agent/llm.dart';
import '../native/native_bridge.dart';
import 'chat_message.dart';
import '../widgets/view_cards.dart';
import '../widgets/capture_card.dart';
import 'permission_panel.dart';
import 'reverse_page.dart';
import 'files_page.dart';
import 'memory_page.dart';
import 'overlay_page.dart';
import 'memories_page.dart';

class ChatPage extends ConsumerStatefulWidget {
  final int? sessionId;
  const ChatPage({super.key, this.sessionId});
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ContextRingPainter extends CustomPainter {
  final double ratio;
  final Color color;
  const _ContextRingPainter({required this.ratio, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1.5;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFEEF2F7),
    );
    if (ratio <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * ratio.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ContextRingPainter old) => old.ratio != ratio || old.color != color;
}

Color _contextColor(double ratio) {
  if (ratio >= 0.9) return const Color(0xFFEF4444);
  if (ratio >= 0.7) return const Color(0xFFF59E0B);
  return const Color(0xFF22C55E);
}

class _ChatPageState extends ConsumerState<ChatPage> {

  final _input = TextEditingController();
  final _scroll = ScrollController();
  String _mode = 'BUILD';
  bool _atBottom = true;
  final Set<String> _chooseShown = {};
  bool _chooseOpen = false;
  bool _jumpedToBottom = false;
  int? _lastSid;
  Timer? _draftTimer;
  String _draftKey = 'new';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // 草稿：输入后防抖保存，切会话/重启都能恢复
    _input.addListener(() {
      _draftTimer?.cancel();
      _draftTimer = Timer(const Duration(milliseconds: 400), () {
        UiStateStore.saveDraft(_draftKey, _input.text);
      });
    });
    UiStateStore.draft(_draftKey).then((d) {
      if (!mounted || d.isEmpty || _input.text.isNotEmpty) return;
      _input.text = d;
      _input.selection = TextSelection.collapsed(offset: d.length);
    });
    // 恢复上次选择的模式（执行 / 规划 / 自动），不要让重启后回到默认
    UiStateStore.mode().then((m) {
      if (!mounted || m == null) return;
      if (!_modeLabels.containsKey(m)) return;
      setState(() => _mode = m);
      ref.read(agentEngineProvider).mode = m.toLowerCase();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ws = ref.read(workspaceProvider).value;
      if (ws != null) ref.read(agentEngineProvider).setWorkspace(ws);
    });
    final sid = widget.sessionId;
    if (sid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(agentEngineProvider).openSession(ref.read(appDbProvider), sid);
      });
    } else {
      // 主页启动：回到上次打开的会话
      final last = ref.read(activeSessionProvider);
      if (last != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final db = ref.read(appDbProvider);
          final exists = await db.sessionExists(last);
          if (!exists) {
            ref.read(activeSessionProvider.notifier).reset();
            return;
          }
          ref.read(agentEngineProvider).openSession(db, last);
        });
      }
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final at = pos.pixels >= pos.maxScrollExtent - 24;
    if (at != _atBottom) setState(() => _atBottom = at);
  }

  Widget _renderItem(ChatItem item, AgentEngine engine) {
    final w = switch (item) {
      UserItem u => UserBubble(text: u.msg.text, time: u.msg.time),
      AssistantItem a => AssistantBubble(
          text: a.msg.text, typing: a.typing, elapsedMs: a.msg.elapsedMs, time: a.msg.time),
      ToolGroupItem g => ToolGroupTile(tools: g.tools, outputs: g.outputs),
      ViewItem v => v.msg.view == 'capture'
          ? CaptureCard(onStop: () => engine.stopCapture())
          : ViewCard(
          view: v.msg.view ?? '',
          title: v.msg.viewTitle ?? v.msg.toolName ?? '',
          data: v.msg.viewData ?? const {},
          onAction: (text) {
            if (engine.running) {
              showToast(context, 'AI 还在处理上一条，稍后再提交');
              return;
            }
            engine.send(text);
          },
        ),
      _ => const SizedBox.shrink(),
    };
    final idx = switch (item) {
      UserItem u => u.index,
      AssistantItem a => a.index,
      _ => -1,
    };
    final animated = EnterFade(child: w);
    if (idx < 0) return animated;
    return GestureDetector(
      onLongPress: () => _messageMenu(engine, idx, item),
      child: animated,
    );
  }

  Widget _menuBtn(BuildContext ctx, IconData icon, String label, Color color, String value) {
    return Material(
      color: const Color(0xFFF4F6FA),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.pop(ctx, value),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }

  Future<void> _messageMenu(AgentEngine engine, int index, ChatItem item) async {
    final text = switch (item) {
      UserItem u => u.msg.text,
      AssistantItem a => a.msg.text,
      _ => '',
    };
    final choice = await showDialog<String>(
      context: context,
      barrierColor: const Color(0x330F172A),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white),
            boxShadow: const [BoxShadow(color: Color(0x1F0F172A), blurRadius: 30, offset: Offset(0, 12))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('消息操作',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)),
            const SizedBox(height: 12),
            _menuBtn(ctx, Icons.copy_rounded, '复制', AppColors.brand, 'copy'),
            const SizedBox(height: 8),
            _menuBtn(ctx, Icons.edit_outlined, '编辑', AppColors.brand, 'edit'),
            const SizedBox(height: 8),
            _menuBtn(ctx, Icons.delete_outline_rounded, '删除', AppColors.red, 'delete'),
          ]),
        ),
      ),
    );
    if (choice == 'copy') {
      Clipboard.setData(ClipboardData(text: text));
      if (mounted) showToast(context, '已复制');
    } else if (choice == 'edit') {
      final c = TextEditingController(text: text);
      final ok = await showGlassDialog<bool>(
        context: context,
        title: '编辑消息',
        confirmText: '保存',
        content: TextField(
          controller: c,
          minLines: 8,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 13, height: 1.6),
          decoration: const InputDecoration(hintText: '消息内容'),
        ),
      );
      if (ok == true) engine.updateMessageAt(index, c.text.trim());
    } else if (choice == 'delete') {
      engine.removeMessageAt(index);
      if (mounted) showToast(context, '已删除');
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(AgentEngine engine) async {
    final t = _input.text.trim();
    // 只拖了引用、没打字时也要能发出去
    if (t.isEmpty && ref.read(chatRefsProvider).isEmpty) return;
    // 还没有会话就先建一个，否则消息不入库、重启就没了
    if (engine.sessionId == null) {
      final db = ref.read(appDbProvider);
      final title = t.isEmpty ? '新对话' : (t.length > 18 ? t.substring(0, 18) : t);
      final id = await db.createSession(title);
      await engine.openSession(db, id);
      ref.read(activeSessionProvider.notifier).open(id);
      if (!mounted) return;
    }
    final refs = ref.read(chatRefsProvider);
    // 拖入的文件夹 = 设为工作区
    for (final r in refs.where((e) => e.type == 'workspace')) {
      if (r.detail.isNotEmpty) {
        ref.read(workspaceProvider.notifier).set(r.detail);
        engine.setWorkspace(r.detail);
      }
    }
    final prefix = refs.map((e) => e.toPrompt()).join('\n');
    final text = prefix.isEmpty ? t : '$prefix\n\n$t';
    _input.clear();
    _draftTimer?.cancel();
    UiStateStore.saveDraft(_draftKey, '');
    ref.read(chatRefsProvider.notifier).clear();
    engine.send(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _atBottom) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.read(agentEngineProvider);
    engine.mode = _mode.toLowerCase();
    // 会话页选中时，主页直接切换到该会话（不再另开页面）。
    ref.listen<int?>(activeSessionProvider, (prev, next) {
      if (next == prev) return;
      if (next == null) {
        engine.newConversation();
      } else {
        engine.openSession(ref.read(appDbProvider), next);
      }
    });
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  GlassIconButton(
                    icon: Icons.menu_rounded,
                    onTap: () => Scaffold.of(context).openDrawer(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Rowan',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        ListenableBuilder(
                          listenable: engine,
                          builder: (_, __) => Text(
                            engine.messages.isEmpty ? '新对话' : '${engine.messages.length} 条消息',
                            style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GlassIconButton(
                    icon: Icons.terminal_rounded,
                    onTap: () => _openTerminal(context),
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: Icons.article_outlined,
                    onTap: () => _showLogs(engine),
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: Icons.add_rounded,
                    onTap: () async {
                      final id = await ref.read(appDbProvider).createSession('新会话');
                      if (context.mounted) {
                        ref.read(activeSessionProvider.notifier).open(id);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: Icons.picture_in_picture_alt_rounded,
                    onTap: () => NativeBridge.chatOverlayMinimize(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: engine,
                builder: (_, __) {
                  final empty = engine.messages.isEmpty && !engine.running && !engine.liveActive;
                  if (empty) {
                    return Stack(children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 22, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('想做什么？',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                            SizedBox(height: 6),
                            Text('直接说，或者把文件、应用拖进来',
                                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
                          ],
                        ),
                      ),
                    ]);
                  }
                  final msgs = List<ChatMsg>.from(engine.messages);
                  if (engine.liveActive) {
                    msgs.add(ChatMsg('view', '',
                        view: 'stream',
                        viewTitle: '${engine.livePrefix} · ${engine.liveTitle}',
                        viewData: {
                          'lines': List<String>.from(engine.liveLines),
                          'running': true,
                          'elapsed': engine.liveElapsed,
                        }));
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scroll.hasClients && _atBottom) {
                        _scroll.jumpTo(_scroll.position.maxScrollExtent);
                      }
                    });
                  }
                  if (engine.captureActive) {
                    msgs.add(ChatMsg('view', '', view: 'capture', viewTitle: '抓包'));
                  }
                  if (engine.streaming) {
                    msgs.add(ChatMsg('assistant',
                        engine.streamingText));
                    // 流式过程中保持贴底
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scroll.hasClients && _atBottom) {
                        _scroll.jumpTo(_scroll.position.maxScrollExtent);
                      }
                    });
                  }
                  // 新的选项目卡 → 自动弹底部选择窗（不再在聊天里堆卡片）
                  if (engine.sessionId != _lastSid) {
                    _lastSid = engine.sessionId;
                    _jumpedToBottom = false;
                    final key = engine.sessionId?.toString() ?? 'new';
                    if (key != _draftKey) {
                      _draftKey = key;
                      UiStateStore.draft(key).then((d) {
                        if (!mounted) return;
                        _input.text = d;
                        _input.selection = TextSelection.collapsed(offset: d.length);
                      });
                    }
                  }
                  // 选项目卡 → 弹层（同一时间只弹一个，按消息自身 key 去重，流式增删不会重弹）
                  if (!_chooseOpen) {
                    for (final mm in msgs) {
                      if (mm.role != 'view' || mm.view != 'choose') continue;
                      final key = '${mm.time?.microsecondsSinceEpoch}-${mm.viewTitle}';
                      if (!_chooseShown.add(key)) continue;
                      _chooseOpen = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!mounted) {
                          _chooseOpen = false;
                          return;
                        }
                        final d = mm.viewData ?? const <String, dynamic>{};
                        final opts = ((d['options'] as List?) ?? const [])
                            .map((e) => Map<String, dynamic>.from(e as Map))
                            .toList();
                        await showChooseSheet(
                          context,
                          title: mm.viewTitle ?? '选一个',
                          options: opts,
                          multi: d['multi'] == true,
                          cancel: '${d['cancel'] ?? '都别用'}',
                          onDone: (t) => engine.send(t),
                        );
                        _chooseOpen = false;
                        // 同一轮里后续的选项卡一律丢弃，不再连续弹窗
                        for (final m2 in engine.messages) {
                          if (m2.role == 'view' && m2.view == 'choose') {
                            _chooseShown.add('${m2.time?.microsecondsSinceEpoch}-${m2.viewTitle}');
                          }
                        }
                        if (mounted) setState(() {});
                      });
                      break;
                    }
                  }
                  final items = buildChatItems(msgs, typingLast: engine.streaming);
                  // 打开会话/重启后直接停在最新一条，不要回到开头
                  if (!_jumpedToBottom && items.isNotEmpty) {
                    _jumpedToBottom = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
                    });
                  }
                  return Stack(children: [
                    SelectionArea(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _renderItem(items[i], engine),
                      ),
                    ),
                    if (!_atBottom && items.isNotEmpty)
                      Positioned(
                        right: 16,
                        bottom: 8,
                        child: ScaleOnTap(
                          onTap: () {
                            if (_scroll.hasClients) {
                              _scroll.jumpTo(_scroll.position.maxScrollExtent);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.brand,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [BoxShadow(color: Color(0x332563EB), blurRadius: 14, offset: Offset(0, 6))],
                            ),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.arrow_downward_rounded, size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text('新消息', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
                  ]);
                },
              ),
            ),
            ListenableBuilder(
              listenable: engine,
              builder: (_, __) {
                final p = engine.pendingPermission;
                if (p == null) return const SizedBox.shrink();
                return PermissionPanel(
                  tool: p.tool,
                  args: p.args,
                  mode: engine.mode,
                  onChoice: (c) => engine.resolvePermission(c),
                );
              },
            ),
            ListenableBuilder(
              listenable: engine,
              builder: (_, __) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _refChips(),
                    DragTarget<ChatRef>(
                      onAcceptWithDetails: (d) => ref.read(chatRefsProvider.notifier).add(d.data),
                      builder: (context, candidate, rejected) => AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: candidate.isNotEmpty ? const Color(0xFFEAF1FE) : Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: _inputRow(engine),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openTerminal(BuildContext context) {
    // 直接开原生终端窗口，不在 Flutter 侧压占位页
    NativeBridge.openTerminal();
  }

  /// 运行日志：实时跟随本次会话的工具调用。
  void _showLogs(AgentEngine engine) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ListenableBuilder(
        listenable: engine,
        builder: (ctx, __) {
          final logs = engine.messages.where((m) => m.role == 'tool').toList();
          return SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Row(children: [
                  const Text('运行日志', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Text('${logs.length} 条',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                  const Spacer(),
                  if (engine.running)
                    const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.6)),
                      SizedBox(width: 5),
                      Text('进行中', style: TextStyle(fontSize: 10, color: Color(0xFF2563EB))),
                    ]),
                ]),
              ),
              Expanded(
                child: logs.isEmpty
                    ? const Center(
                        child: Text('还没有工具调用',
                            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                        itemCount: logs.length,
                        itemBuilder: (_, i) {
                          final m = logs[logs.length - 1 - i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  m.ok == false ? Icons.error_outline_rounded : Icons.check_rounded,
                                  size: 13,
                                  color: m.ok == false ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${m.toolName ?? 'tool'}  ${m.text}',
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10.5, fontFamily: 'monospace', height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
          );
        },
      ),
    );
  }

  Future<void> _showAttachSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white.withValues(alpha: 0.7),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('添加内容',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _attachCell(ctx, Icons.image_outlined, '照片', '从相册选', 'photo'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _attachCell(ctx, Icons.folder_outlined, '文件', '任意文件', 'file'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _attachCell(ctx, Icons.layers_outlined, '切换模型', '选这次用哪个', 'model'),
                ),
              ]),
              const SizedBox(height: 12),
              const Text('点空白处或下滑关闭',
                  style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'photo') {
      await _pickPhoto();
    } else if (action == 'file') {
      await _pickFile();
    } else if (action == 'model') {
      await _pickModel();
    }
  }

  Widget _attachCell(BuildContext ctx, IconData icon, String title, String desc, String value) {
    return InkWell(
      onTap: () => Navigator.of(ctx).pop(value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        ),
        child: Column(children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF5FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: AppColors.brand),
          ),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 3),
          Text(desc, style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
        ]),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    ref.read(chatRefsProvider.notifier).add(
          ChatRef(type: 'file', name: x.name, detail: x.path),
        );
  }

  Future<void> _pickFile() async {
    final p = await NativeBridge.pickFile();
    if (p == null) return;
    ref.read(chatRefsProvider.notifier).add(
          ChatRef(type: 'file', name: p.split('/').last, detail: p),
        );
  }

  Future<void> _pickModel() async {
    final cfg = await ProviderStore.load();
    final models = cfg?.models ?? const <String>[];
    if (!mounted) return;

    // 余额异步加载，不阻塞弹窗
    final balText = ValueNotifier<String?>(null);
    if (cfg != null) {
      final (list, active) = await ProviderStore.loadAllWithActive();
      ProviderConfig? match;
      for (final p in list) {
        if (p.baseUrl == cfg.baseUrl) match = p;
      }
      if (match == null && list.isNotEmpty) match = list.firstWhere((p) => p.name == active, orElse: () => list.first);
      if (match != null) {
        BalanceFetcher.fetch(match).then((v) => balText.value = v);
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('切换模型', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const Spacer(),
              ValueListenableBuilder<String?>(
                valueListenable: balText,
                builder: (_, v, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 13, color: v == null ? AppColors.muted : AppColors.brand),
                  const SizedBox(width: 4),
                  Text(
                    v ?? '—',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: v == null ? AppColors.muted : AppColors.brand,
                    ),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            if (models.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('还没有模型。请到「设置 → AI 供应商」里拉取模型列表。',
                    style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.6)),
              )
            else
              for (final m in models)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(m, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  trailing: cfg?.model == m
                      ? const Icon(Icons.check_rounded, size: 18, color: AppColors.brand)
                      : null,
                  onTap: () async {
                    await ProviderStore.save(LlmConfig(
                        baseUrl: cfg!.baseUrl, apiKey: cfg.apiKey, model: m, models: models));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
          ],
        ),
      ),
    );
  }

  Widget _roundKey(IconData icon, VoidCallback onTap, {Color bg = const Color(0xFFF1F4F8), Color fg = const Color(0xFF64748B)}) {
    return ScaleOnTap(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: fg),
      ),
    );
  }

  Widget _refChips() {
    final refs = ref.watch(chatRefsProvider);
    if (refs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < refs.length; i++)
              InputChip(
                label: Text('${refs[i].label}·${refs[i].name}',
                    style: const TextStyle(fontSize: 10.5)),
                onDeleted: () => ref.read(chatRefsProvider.notifier).removeAt(i),
                deleteIconColor: const Color(0xFF94A3B8),
                backgroundColor: const Color(0xFFEAF1FE),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  Widget _inputRow(AgentEngine engine) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: lg.GlassContainer.card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(fontSize: 13.5, height: 1.45),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  hintText: '发消息，或把文件拖进来…',
                  hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF9AA4B2)),
                ),
                onSubmitted: (_) => _send(engine),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _roundKey(Icons.add_rounded, _showAttachSheet),
                const Spacer(),
                _modeChip(),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: engine,
                  builder: (_, __) => SizedBox(
                    width: 38,
                    height: 38,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _ContextRingPainter(
                              ratio: engine.contextRatio,
                              color: _contextColor(engine.contextRatio),
                            ),
                          ),
                        ),
                        engine.running
                            ? ScaleOnTap(
                                onTap: () => engine.stop(),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFFEF4444), shape: BoxShape.circle),
                                  child: engine.stopping
                                      ? const Center(
                                          child: SizedBox(
                                            width: 13,
                                            height: 13,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation(Colors.white)),
                                          ),
                                        )
                                      : const Icon(Icons.stop_rounded, size: 17, color: Colors.white),
                                ),
                              )
                            : ScaleOnTap(
                                onTap: () => _send(engine),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                      gradient: ref.watch(themeColorProvider).gradient, shape: BoxShape.circle),
                                  child: const Icon(Icons.arrow_upward_rounded, size: 17, color: Colors.white),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  }

  static const Map<String, String> _modeLabels = {'BUILD': '执行', 'PLAN': '规划', 'AUTO': '自动'};

  Widget _modeChip() {
    return ScaleOnTap(
      onTap: _pickMode,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF1FE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(_modeLabels[_mode] ?? _mode,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
        ]),
      ),
    );
  }

  Future<void> _pickMode() async {
    final m = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('执行模式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
          for (final e in const [
            ('BUILD', '每次操作都先问你，包括读文件'),
            ('PLAN', '只看不动：读文件、搜代码，不跑写操作'),
            ('AUTO', '一路做完不打断，只有高危操作才问'),
          ])
            ListTile(
              title: Row(children: [
                Text(_modeLabels[e.$1]!,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _mode == e.$1 ? AppColors.brand : const Color(0xFF0F172A))),
                if (_mode == e.$1) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_rounded, size: 15, color: AppColors.brand),
                ],
              ]),
              subtitle: Text(e.$2, style: const TextStyle(fontSize: 10.5)),
              onTap: () => Navigator.pop(ctx, e.$1),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (m != null) {
      setState(() => _mode = m);
      ref.read(agentEngineProvider).mode = m.toLowerCase();
      UiStateStore.saveMode(m);
    }
  }

  Widget _bubble(ChatMsg m) {
    if (m.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          constraints: const BoxConstraints(maxWidth: 286),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE3EDFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC9DCFF), width: 0.9),
            ),
            child: Text(m.text,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF1B3A78), height: 1.55)),
          ),
        ),
      );
    }
    if (m.role == 'tool') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border), bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(m.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                size: 14, color: m.ok ? AppColors.green : AppColors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(m.text,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.text, height: 1.5)),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 0.9),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(m.text,
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B), height: 1.7)),
          if (m.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.text));
                  showToast(context, '已复制', error: false);
                },
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.copy_rounded, size: 12, color: Color(0xFFB6C2D1)),
                    SizedBox(width: 4),
                    Text('复制', style: TextStyle(fontSize: 10.5, color: Color(0xFFB6C2D1))),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
