import 'music_handler.dart';

/// 全局音频播放（AI 点歌 / 播 URL / 播本地文件），底层走 audio_service 后台播放。
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  MusicHandler get _h => audioHandler as MusicHandler;

  String? currentUrl;
  String? currentTitle;

  Stream<Duration> get positionStream => _h.positionStream;
  Duration get position => _h.position;
  Duration? get duration => _h.duration;
  Future<void> seek(Duration d) => _h.seekTo(d);

  Future<String> play(String url, {String? title}) async {
    final r = await _h.playUrl(url, title: title);
    if (r.startsWith('开始播放')) {
      currentUrl = url;
      currentTitle = title;
    }
    return r;
  }

  Future<String> pause() async {
    await _h.pause();
    return '已暂停';
  }

  Future<String> resume() async {
    await _h.play();
    return '已继续';
  }

  Future<String> stop() async {
    await _h.stop();
    currentUrl = null;
    currentTitle = null;
    return '已停止';
  }

  Future<String> status() async => _h.statusText();
}
