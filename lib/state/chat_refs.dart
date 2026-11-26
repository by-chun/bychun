import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 拖进对话框的引用：技能 / 子代理 / 人物 / 提示词 / 应用 / 文件 / SO / 脚本。
class ChatRef {
  final String type; // skill / subagent / persona / prompt / app / file / so / script
  final String name;
  final String detail; // 包名、路径、内容等
  const ChatRef({required this.type, required this.name, this.detail = ''});

  String get label => switch (type) {
        'skill' => '技能',
        'subagent' => '子代理',
        'persona' => '人物',
        'prompt' => '提示词',
        'app' => '应用',
        'file' => '文件',
        'so' => 'SO',
        'workspace' => '工作区',
        'script' => '脚本',
        _ => type,
      };

  /// 拼进消息的文本形式。
  String toPrompt() => detail.isEmpty ? '[$label: $name]' : '[$label: $name]\n$detail';
}

class ChatRefsNotifier extends Notifier<List<ChatRef>> {
  @override
  List<ChatRef> build() => const [];

  void add(ChatRef r) {
    if (state.any((e) => e.type == r.type && e.name == r.name)) return;
    state = [...state, r];
  }

  void removeAt(int i) {
    final l = [...state]..removeAt(i);
    state = l;
  }

  void clear() => state = const [];
}

final chatRefsProvider = NotifierProvider<ChatRefsNotifier, List<ChatRef>>(ChatRefsNotifier.new);

/// 拖拽时显示的小卡片。
const kRefDragFeedbackSize = 160.0;
