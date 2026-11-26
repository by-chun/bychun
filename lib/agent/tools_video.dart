import 'dart:convert';

import 'tool.dart';
import 'tool_registry.dart';

/// 播放视频（http 直链或本地文件）：在对话里的窗口卡片中播放，不跳全屏页。
class PlayVideoTool extends AgentTool {
  @override
  String get name => 'playVideo';

  @override
  String get description =>
      '播放视频：传 http(s) 直链或本地文件绝对路径；有剧集时传 episodes（JSON 数组，每项 {title,url}），'
      '卡片会列选集、自动连播。';

  @override
  Map<String, String> get parameters => {
        'url': 'http 直链或本地路径（无 episodes 时必填）',
        'title': '可选：标题',
        'episodes': '可选：JSON 数组，如 [{"title":"第1集","url":"https://..."}]',
        'index': '可选：从第几集开始，默认 1',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final raw = (args['episodes'] ?? '').trim();
    final episodes = <Map<String, String>>[];
    if (raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          final m = Map<String, dynamic>.from(e as Map);
          final u = (m['url'] ?? '').toString().trim();
          if (u.isEmpty) continue;
          episodes.add({'title': (m['title'] ?? u).toString(), 'url': u});
        }
      } catch (_) {
        return const ToolResult(false, 'episodes 不是合法的 JSON 数组');
      }
    }
    var url = (args['url'] ?? '').trim();
    var title = (args['title'] ?? '').trim();
    var index = int.tryParse((args['index'] ?? '1').trim()) ?? 1;
    if (episodes.isNotEmpty) {
      index = index.clamp(1, episodes.length).toInt();
      url = url.isEmpty ? episodes[index - 1]['url']! : url;
      if (title.isEmpty) title = episodes[index - 1]['title']!;
    }
    if (url.isEmpty) return const ToolResult(false, 'url 不能为空');
    if (!url.startsWith('http') && !url.startsWith('/')) {
      return const ToolResult(false, '需要 http(s) 直链或绝对路径');
    }
    if (title.isEmpty) {
      title = url.split('/').last.isEmpty ? url : url.split('/').last;
    }
    return ToolResult(
      true,
      episodes.isEmpty ? '已在对话里播放：$title' : '已在对话里播放：$title（共 ${episodes.length} 集）',
      view: 'video',
      title: title,
      viewData: {
        'url': url,
        'title': title,
        'episodes': episodes,
        'index': index,
      },
    );
  }
}

void registerVideoTools(ToolRegistry reg) {
  reg.register(PlayVideoTool());
}
