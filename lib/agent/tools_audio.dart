import 'dart:convert';

import 'audio_service.dart';
import 'tool.dart';
import 'tool_registry.dart';

/// 播放音频：单曲直链，或一个播放列表（会记住列表/循环模式/当前曲目）。
class PlayAudioTool extends AgentTool {
  @override
  String get name => 'playAudio';

  @override
  String get description =>
      '播放音频。单曲传 url（http 直链或本地文件）；有播放列表时传 playlist（JSON 数组 [{"url":"...","title":"..."}]）。'
      '会记住播放列表、循环模式与当前曲目，下次可用 audioControl 控制或直接继续。';

  @override
  Map<String, String> get parameters => {
        'url': '单曲：http 直链或本地文件路径（无 playlist 时必填）',
        'title': '可选：歌名',
        'playlist': '可选：JSON 数组，如 [{"url":"https://...","title":"歌名"}]',
        'index': '可选：从第几首开始，默认 1',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final raw = (args['playlist'] ?? '').trim();
    final tracks = <Map<String, String>>[];
    if (raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          final m = Map<String, dynamic>.from(e as Map);
          final u = (m['url'] ?? '').toString().trim();
          if (u.isEmpty) continue;
          tracks.add({'url': u, 'title': (m['title'] ?? u).toString().trim()});
        }
      } catch (_) {
        return const ToolResult(false, 'playlist 不是合法的 JSON 数组');
      }
    }
    if (tracks.isNotEmpty) {
      final index = ((int.tryParse((args['index'] ?? '1').trim()) ?? 1) - 1)
          .clamp(0, tracks.length - 1)
          .toInt();
      final t = tracks[index];
      final r = await AudioService.instance.playList(tracks, index: index);
      final ok = r.startsWith('开始播放');
      return ToolResult(
        ok,
        r,
        view: ok ? 'audio' : null,
        title: t['title'],
        viewData: ok ? {'url': t['url'], 'title': t['title']} : null,
      );
    }
    final url = (args['url'] ?? '').trim();
    if (url.isEmpty) return const ToolResult(false, 'url 和 playlist 至少传一个');
    if (!url.startsWith('http') && !url.startsWith('/')) {
      return const ToolResult(false, '需要 http(s) 直链或绝对路径');
    }
    final r = await AudioService.instance.play(url, title: args['title']?.trim());
    final ok = r.startsWith('开始播放');
    final t = (args['title'] ?? '').trim();
    final title = t.isNotEmpty ? t : (url.split('/').last.isEmpty ? url : url.split('/').last);
    return ToolResult(
      ok,
      r,
      view: ok ? 'audio' : null,
      title: title,
      viewData: ok ? {'url': url, 'title': title} : null,
    );
  }
}

/// 暂停 / 继续 / 停止 / 上一首 / 下一首 / 循环模式 / 查看状态。
class AudioControlTool extends AgentTool {
  @override
  String get name => 'audioControl';

  @override
  String get description => '控制播放：action = pause / resume / stop / status / next / prev / loop。loop 时用 mode 指定循环模式。';

  @override
  Map<String, String> get parameters => {
        'action': 'pause | resume | stop | status | next | prev | loop',
        'mode': 'loop 时用：none(不循环) | one(单曲) | all(列表)，默认 all',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final a = (args['action'] ?? '').trim().toLowerCase();
    final s = AudioService.instance;
    final r = switch (a) {
      'pause' => await s.pause(),
      'resume' => await s.resume(),
      'stop' => await s.stop(),
      'status' => await s.status(),
      'next' => await s.next(),
      'prev' => await s.prev(),
      'loop' => await s.setLoop(args['mode'] ?? 'all'),
      _ => '未知 action：$a（可用 pause/resume/stop/status/next/prev/loop）',
    };
    return ToolResult(!r.contains('失败') && !r.startsWith('未知'), r);
  }
}

void registerAudioTools(ToolRegistry reg) {
  reg.register(PlayAudioTool());
  reg.register(AudioControlTool());
}
