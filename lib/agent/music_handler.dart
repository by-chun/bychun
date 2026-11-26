import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

late AudioHandler audioHandler;

/// 后台播放 + 通知栏控制。
class MusicHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();

  MusicHandler() {
    _player.playbackEventStream.listen(_broadcast, onError: (_, __) {});
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.completed,
          playing: false,
        ));
      }
    });
  }

  void _broadcast(PlaybackEvent event) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }

  /// 播 URL 或本地文件。
  Future<String> playUrl(String url, {String? title}) async {
    try {
      final same = mediaItem.value?.id == url;
      final t = title ?? url.split('/').last;
      mediaItem.add(MediaItem(id: url, title: t));
      // 网络加载可能很慢：不要在工具里等它，否则对话窗口要等加载完才出现
      unawaited(() async {
        try {
          if (!same) {
            final d = await _player.setAudioSource(url.startsWith('http')
                ? AudioSource.uri(Uri.parse(url))
                : AudioSource.file(url));
            final cur = mediaItem.value;
            if (cur != null) mediaItem.add(cur.copyWith(duration: d));
          }
          await _player.play();
        } catch (_) {}
      }());
      return '开始播放${title == null ? '' : '：$title'}';
    } catch (e) {
      return '播放失败：$e';
    }
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  Future<void> seekTo(Duration d) => _player.seek(d);

  Future<String> statusText() async {
    final item = mediaItem.value;
    if (item == null) return '当前没有在播放';
    final s = _player.playing ? '播放中' : '已暂停';
    return '${item.title}｜$s';
  }
}

Future<void> initAudioService() async {
  audioHandler = await AudioService.init(
    builder: () => MusicHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.chun.by.audio',
      androidNotificationChannelName: 'Rowan 播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
}
