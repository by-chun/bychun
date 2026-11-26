import 'audio_service.dart';
import 'tool.dart';
import 'tool_registry.dart';

/// 播放一个音频直链（AI 点歌用：先调音乐 API 拿直链，再调这个）。
class PlayAudioTool extends AgentTool {
  @override
  String get name => 'playAudio';

  @override
  String get description => '播放音频：可传 http(s) 直链，也可传本地文件绝对路径（如抓到的音乐包解密后的 mp3）。';

  @override
  Map<String, String> get parameters => {'url': 'http 直链或本地文件路径', 'title': '可选：歌名'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final url = (args['url'] ?? '').trim();
    if (url.isEmpty) return const ToolResult(false, 'url 不能为空');
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

/// 暂停 / 继续 / 停止 / 查看状态。
class AudioControlTool extends AgentTool {
  @override
  String get name => 'audioControl';

  @override
  String get description => '控制播放：action = pause / resume / stop / status。';

  @override
  Map<String, String> get parameters => {'action': 'pause | resume | stop | status'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final a = (args['action'] ?? '').trim().toLowerCase();
    final s = AudioService.instance;
    final r = switch (a) {
      'pause' => await s.pause(),
      'resume' => await s.resume(),
      'stop' => await s.stop(),
      'status' => await s.status(),
      _ => '未知 action：$a（可用 pause/resume/stop/status）',
    };
    return ToolResult(!r.contains('失败') && !r.startsWith('未知'), r);
  }
}

void registerAudioTools(ToolRegistry reg) {
  reg.register(PlayAudioTool());
  reg.register(AudioControlTool());
}
