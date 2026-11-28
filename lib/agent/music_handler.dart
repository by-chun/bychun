import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../native/native_bridge.dart';

late AudioHandler audioHandler;

/// 一首曲目。
class MusicTrack {
  final String url;
  final String title;
  const MusicTrack(this.url, this.title);
  Map<String, dynamic> toJson() => {'url': url, 'title': title};
  static MusicTrack fromJson(Map<String, dynamic> m) =>
      MusicTrack((m['url'] ?? '').toString(), (m['title'] ?? '').toString());
}

/// 后台播放 + 通知栏控制 + 播放列表/循环模式，进度与列表落盘下次恢复。
class MusicHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();

  final List<MusicTrack> _queue = [];
  int _curIndex = -1;
  String _loop = 'all'; // none | one | all

  MusicHandler() {
    _player.playbackEventStream.listen(_broadcast, onError: (_, __) {});
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.completed,
          playing: false,
        ));
        _onCompleted();
      }
    });
    unawaited(_restoreState());
  }

  void _broadcast(PlaybackEvent event) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.skipToNext,
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

  String get _loopName => switch (_loop) {
        'none' => '不循环',
        'one' => '单曲循环',
        _ => '列表循环',
      };

  /// 当前循环模式（none/one/all），供 UI 显示。
  String get loopMode => _loop;

  /// 播 URL 或本地文件（单曲，不进播放列表）。
  Future<String> playUrl(String url, {String? title}) async {
    try {
      final same = mediaItem.value?.id == url;
      final t = title ?? url.split('/').last;
      mediaItem.add(MediaItem(id: url, title: t));
      // 先同步构造 source（能立刻发现非法 URL/本地文件），再后台加载播放，避免拖慢对话
      final source = url.startsWith('http')
          ? AudioSource.uri(Uri.parse(url))
          : AudioSource.file(url);
      unawaited(() async {
        try {
          if (!same) {
            final d = await _player.setAudioSource(source);
            final cur = mediaItem.value;
            if (cur != null) mediaItem.add(cur.copyWith(duration: d));
          }
          await _player.play();
        } catch (e) {
          playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.idle,
            playing: false,
          ));
        }
      }());
      return '开始播放${title == null ? '' : '：$title'}';
    } catch (e) {
      return '播放失败：$e';
    }
  }

  /// 播放一个播放列表（从 index 起）。
  Future<String> playPlaylist(List<MusicTrack> tracks, {int index = 0}) async {
    if (tracks.isEmpty) return '播放列表为空';
    _queue
      ..clear()
      ..addAll(tracks);
    _curIndex = index.clamp(0, _queue.length - 1).toInt();
    await _persist();
    return _playCurrent();
  }

  Future<String> _playCurrent() async {
    if (_queue.isEmpty || _curIndex < 0 || _curIndex >= _queue.length) {
      return '播放列表为空';
    }
    final t = _queue[_curIndex];
    return playUrl(t.url, title: t.title);
  }

  Future<String> next() async {
    if (_queue.isEmpty) return '没有播放列表';
    _curIndex = (_curIndex + 1) % _queue.length;
    await _persist();
    return _playCurrent();
  }

  Future<String> prev() async {
    if (_queue.isEmpty) return '没有播放列表';
    _curIndex = (_curIndex - 1 + _queue.length) % _queue.length;
    await _persist();
    return _playCurrent();
  }

  Future<String> setLoop(String mode) async {
    final m = mode.trim().toLowerCase();
    _loop = (m == 'none' || m == 'one' || m == 'all') ? m : 'all';
    await _persist();
    return '循环模式：$_loopName';
  }

  /// 单曲结束后的自动衔接：单曲循环重播；列表内自动下一首；列表尾按循环模式决定。
  void _onCompleted() {
    if (_queue.isEmpty) return;
    if (_loop == 'one') {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    if (_curIndex + 1 < _queue.length) {
      _curIndex += 1;
      _persist();
      _playCurrent();
    } else if (_loop == 'all') {
      _curIndex = 0;
      _persist();
      _playCurrent();
    }
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() async {
    await _player.stop();
    mediaItem.add(null);
    await super.stop();
  }
  @override
  Future<void> skipToNext() async {
    await next();
  }
  @override
  Future<void> skipToPrevious() async {
    await prev();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  Future<void> seekTo(Duration d) => _player.seek(d);

  Future<String> statusText() async {
    final item = mediaItem.value;
    if (item == null) {
      if (_queue.isNotEmpty) {
        return '已停止 · 列表 ${_curIndex + 1}/${_queue.length} · $_loopName';
      }
      return '当前没有在播放';
    }
    final s = _player.playing ? '播放中' : '已暂停';
    final pos = _queue.isEmpty ? '' : '（${_curIndex + 1}/${_queue.length} · $_loopName）';
    return '${item.title}｜$s$pos';
  }

  // ---------------- 落盘：播放列表 / 循环模式 / 当前曲目 ----------------

  Future<File?> _stateFile() async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return null;
    return File('$dir/music_state.json');
  }

  Future<void> _restoreState() async {
    try {
      final f = await _stateFile();
      if (f == null || !await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final q = (m['queue'] as List?) ?? const [];
      _queue
        ..clear()
        ..addAll(q.whereType<Map>().map((e) => MusicTrack.fromJson(Map<String, dynamic>.from(e))));
      _curIndex = (m['index'] as num?)?.toInt() ?? -1;
      _loop = (m['loop'] ?? 'all').toString();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final f = await _stateFile();
      if (f == null) return;
      await f.writeAsString(jsonEncode({
        'queue': [for (final t in _queue) t.toJson()],
        'index': _curIndex,
        'loop': _loop,
      }));
    } catch (_) {}
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
