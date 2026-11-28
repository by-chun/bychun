import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../agent/audio_service.dart';
import '../native/native_bridge.dart';
import '../theme/app_theme.dart';
import '../util/text_extract.dart';
import 'catalog_sheet.dart';

String _fmtDur(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

/// 视频 / 音频 / 阅读 三类窗口卡片：都在对话里就地渲染，不跳页。
Widget _shell({required String title, String? subtitle, IconData? icon, required Widget child}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xB8FFFFFF), Color(0x85FFFFFF)],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
      boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 22, offset: Offset(0, 8))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
          child: Row(children: [
            if (icon != null) ...[
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: AppColors.brand),
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.text)),
            ),
            if (subtitle != null)
              Text(subtitle,
                  style: const TextStyle(fontSize: 9.5, color: AppColors.muted, fontFamily: 'monospace')),
          ]),
        ),
        child,
      ],
    ),
  );
}

class VideoViewCard extends StatefulWidget {
  final String title;
  final Map<String, dynamic> data;
  final void Function(String text)? onAction;
  const VideoViewCard({super.key, required this.title, required this.data, this.onAction});

  @override
  State<VideoViewCard> createState() => _VideoViewCardState();
}

class _VideoViewCardState extends State<VideoViewCard> {
  static const _speeds = [0.5, 1.0, 1.5, 2.0];
  static final Map<String, int> _savedMs = {};
  static final Map<String, int> _savedEp = {};      // title -> 集序号（0 起）
  static final Map<String, double> _savedSpeed = {}; // title -> 倍速
  static bool _posLoaded = false;
  int _lastPersist = 0;

  VideoPlayerController? _c;
  String? _err;
  double _speed = 1.0;
  bool _autoNext = true;
  bool _switching = false;

  late final List<Map<String, String>> _eps = _parseEpisodes(widget.data['episodes']);
  late int _index = ((widget.data['index'] as num?)?.toInt() ?? 1).clamp(1, _eps.isEmpty ? 1 : _eps.length).toInt() - 1;
  late String _url = (widget.data['url'] ?? '').toString();

  static List<Map<String, String>> _parseEpisodes(Object? raw) {
    final out = <Map<String, String>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final u = (e['url'] ?? '').toString();
          if (u.isEmpty) continue;
          out.add({'title': (e['title'] ?? u).toString(), 'url': u});
        }
      }
    }
    return out;
  }

  String get _playUrl => _eps.isEmpty ? _url : (_eps[_index]['url'] ?? _url);
  String get _epTitle => _eps.isEmpty ? widget.title : (_eps[_index]['title'] ?? '第 ${_index + 1} 集');

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// 先读完存档再初始化，避免「存档还没读出来就 seek」的竞态（进度/倍速恢复失败）。
  Future<void> _boot() async {
    await _loadPositions();
    if (!mounted) return;
    final savedSpeed = _savedSpeed[widget.title];
    if (savedSpeed != null && _speeds.contains(savedSpeed)) {
      _speed = savedSpeed;
    }
    _init();
  }

  Future<void> _loadPositions() async {
    if (_posLoaded) return;
    _posLoaded = true;
    try {
      final dir = await NativeBridge.appDataDir();
      if (dir.isEmpty) return;
      final f = File('$dir/video_progress.json');
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString());
      if (m is! Map) return;
      final hasSections = m.containsKey('pos') || m.containsKey('episode') || m.containsKey('speed');
      if (hasSections) {
        final pos = m['pos'];
        if (pos is Map) {
          pos.forEach((k, v) {
            final n = int.tryParse('$v');
            if (n != null) _savedMs['$k'] = n;
          });
        }
        final ep = m['episode'];
        if (ep is Map) {
          ep.forEach((k, v) {
            final n = int.tryParse('$v');
            if (n != null) _savedEp['$k'] = n;
          });
        }
        final sp = m['speed'];
        if (sp is Map) {
          sp.forEach((k, v) {
            final d = double.tryParse('$v');
            if (d != null) _savedSpeed['$k'] = d;
          });
        }
      } else {
        // 旧格式：{key: 毫秒}
        m.forEach((k, v) {
          final n = int.tryParse('$v');
          if (n != null) _savedMs['$k'] = n;
        });
      }
    } catch (_) {}
  }

  static void _persistPositions() {
    Future(() async {
      try {
        final dir = await NativeBridge.appDataDir();
        if (dir.isEmpty) return;
        await File('$dir/video_progress.json').writeAsString(jsonEncode({
          'pos': _savedMs,
          'episode': _savedEp,
          'speed': _savedSpeed,
        }));
      } catch (_) {}
    });
  }

  Future<void> _init() async {
    final url = _playUrl;
    try {
      final ctrl = url.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(url))
          : VideoPlayerController.file(File(url));
      _c = ctrl;
      await ctrl.initialize();
      ctrl.addListener(_onTick);
      await ctrl.setPlaybackSpeed(_speed);
      final saved = _savedMs['${widget.title}|$_epTitle'];
      if (saved != null && saved > 3000) await ctrl.seekTo(Duration(milliseconds: saved));
      await ctrl.play();
      if (mounted) setState(() => _err = null);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  void _onTick() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      _savedMs['${widget.title}|$_epTitle'] = c.value.position.inMilliseconds;
      _savedEp[widget.title] = _index;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPersist > 5000) {
        _lastPersist = now;
        _persistPositions();
      }
    }
    final d = c.value.duration;
    if (d.inMilliseconds <= 0) return;
    if (_autoNext && !_switching && !c.value.isPlaying && c.value.position >= d - const Duration(milliseconds: 400)) {
      _switching = true;
      if (_index + 1 < _eps.length) {
        _playEpisode(_index + 1);
      } else {
        _switching = false;
      }
    }
  }

  Future<void> _playEpisode(int i) async {
    if (_eps.isEmpty || i < 0 || i >= _eps.length) return;
    final old = _c;
    if (old != null && old.value.isInitialized && old.value.position.inMilliseconds > 0) {
      _savedMs['${widget.title}|$_epTitle'] = old.value.position.inMilliseconds;
    }
    _c = null;
    await old?.dispose();
    if (!mounted) return;
    setState(() {
      _index = i;
      _err = null;
      _switching = false;
    });
    _savedEp[widget.title] = i;
    _persistPositions();
    await _init();
  }

  void _askRefresh() {
    final t = '视频链接失效：$_epTitle（原地址 ${_playUrl}），请重新解析这一集的最新直链，解析好后重新调用 playVideo 并带上完整 episodes';
    widget.onAction?.call(t);
  }

  @override
  void dispose() {
    final c = _c;
    if (c != null && c.value.isInitialized && c.value.position.inMilliseconds > 0) {
      _savedMs['${widget.title}|$_epTitle'] = c.value.position.inMilliseconds;
    }
    _savedEp[widget.title] = _index;
    _savedSpeed[widget.title] = _speed;
    _persistPositions();
    c?.dispose();
    super.dispose();
  }

  void _cycleSpeed(VideoPlayerController c) {
    final i = _speeds.indexOf(_speed);
    _speed = _speeds[(i + 1) % _speeds.length];
    c.setPlaybackSpeed(_speed);
    _savedSpeed[widget.title] = _speed;
    _persistPositions();
    setState(() {});
  }

  Future<void> _openFullscreen() async {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    final url = _playUrl;
    final pos = c.value.position;
    final speed = _speed;
    final wasPlaying = c.value.isPlaying;
    await c.pause();
    await c.dispose();
    _c = null;
    if (!mounted) return;
    setState(() {});
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FullscreenVideo(
        title: widget.title,
        url: url,
        startAt: pos,
        speed: speed,
        autoplay: wasPlaying,
        episodes: _eps,
        index: _index,
      ),
    ));
    if (!mounted) return;
    _speed = speed;
    // 全屏里可能切了集/倍速，回来同步一下
    final finalIdx = _VideoViewCardState._savedEp[widget.title];
    if (finalIdx != null && _eps.isNotEmpty && finalIdx >= 0 && finalIdx < _eps.length) {
      _index = finalIdx;
    }
    final finalSpeed = _VideoViewCardState._savedSpeed[widget.title];
    if (finalSpeed != null && _speeds.contains(finalSpeed)) {
      _speed = finalSpeed;
    }
    _init();
  }

  Widget _player() {
    final c = _c;
    if (_err != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141B2E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('播放失败，链接可能已失效', style: TextStyle(fontSize: 11, color: Color(0xFFB91C1C))),
          const SizedBox(height: 6),
          Row(children: [
            GestureDetector(
              onTap: () => _playEpisode(_index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(7)),
                child: const Text('重试', style: TextStyle(fontSize: 10, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _askRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2A45),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text('让 AI 重新解析这一集', style: TextStyle(fontSize: 10, color: AppColors.brand)),
              ),
            ),
          ]),
        ]),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () {
            if (c.value.isPlaying) {
              c.pause();
            } else {
              c.play();
            }
            setState(() {});
          },
          icon: Icon(c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 20, color: AppColors.brand),
        ),
        Text(_fmtDur(c.value.position),
            style: const TextStyle(fontSize: 9.5, color: AppColors.muted, fontFamily: 'monospace')),
        Expanded(
          child: VideoProgressIndicator(
            c,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
        ),
        Text(_fmtDur(c.value.duration),
            style: const TextStyle(fontSize: 9.5, color: AppColors.muted, fontFamily: 'monospace')),
        TextButton(
          onPressed: () => _cycleSpeed(c),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
          child: Text('${_speed}x',
              style: const TextStyle(fontSize: 10.5, color: AppColors.brand, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '全屏',
          onPressed: _openFullscreen,
          icon: const Icon(Icons.fullscreen_rounded, size: 20, color: AppColors.brand),
        ),
      ]),
    ]);
  }

  Widget _episodes() {
    if (_eps.length <= 1) return const SizedBox.shrink();
    return Column(children: [
      Container(
        height: 132,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF141B2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1A2338)),
        ),
        child: ListView.builder(
          itemCount: _eps.length,
          itemBuilder: (_, i) {
            final on = i == _index;
            return GestureDetector(
              onTap: () => _playEpisode(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                color: on ? const Color(0xFF1E2A45) : Colors.transparent,
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? AppColors.brand : const Color(0xFF1A2338),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('EP${(i + 1).toString().padLeft(2, '0')}',
                        style: TextStyle(
                            fontSize: 8,
                            fontFamily: 'monospace',
                            color: on ? Colors.white : const Color(0xFF7886A0))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_eps[i]['title'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5,
                            color: on ? const Color(0xFF1D4ED8) : const Color(0xFFAEB9CC),
                            fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
                  ),
                  if (on) const Icon(Icons.play_arrow_rounded, size: 14, color: AppColors.brand),
                ]),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          const Text('自动连播', style: TextStyle(fontSize: 10, color: Color(0xFF9AA7C0))),
          const SizedBox(width: 6),
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: _autoNext,
              activeColor: AppColors.brand,
              onChanged: (v) => setState(() => _autoNext = v),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              if (_index + 1 < _eps.length) _playEpisode(_index + 1);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(8)),
              child: const Text('下一集', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return _shell(
      icon: Icons.videocam_rounded,
      title: widget.title,
      subtitle: _eps.length > 1 ? '共 ${_eps.length} 集' : '视频',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(children: [
          if (_eps.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_epTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD4DBE8))),
              ),
            ),
          _player(),
          _episodes(),
        ]),
      ),
    );
  }
}

class _FullscreenVideo extends StatefulWidget {
  final String title;
  final String url;
  final Duration startAt;
  final double speed;
  final bool autoplay;
  final List<Map<String, String>> episodes;
  final int index;
  const _FullscreenVideo({
    required this.title,
    required this.url,
    required this.startAt,
    required this.speed,
    required this.autoplay,
    this.episodes = const [],
    this.index = 0,
  });

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  VideoPlayerController? _c;
  String? _err;
  double _speed = 1.0;
  bool _controls = true;
  bool _autoNext = true;
  bool _epOpen = false;
  bool _switching = false;
  late int _idx = widget.index;
  Timer? _hideTimer;
  static const _speeds = [0.5, 1.0, 1.5, 2.0];

  List<Map<String, String>> get _eps => widget.episodes;
  String get _playUrl => _eps.isEmpty ? widget.url : (_eps[_idx]['url'] ?? widget.url);
  String get _title => _eps.isEmpty ? '视频' : (_eps[_idx]['title'] ?? '第 ${_idx + 1} 集');

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _open(_idx, widget.startAt);
    _scheduleHide();
  }

  Future<void> _open(int i, Duration startAt) async {
    final old = _c;
    _c = null;
    await old?.dispose();
    if (!mounted) return;
    final url = _eps.isEmpty ? widget.url : (_eps[i.clamp(0, _eps.length - 1).toInt()]['url'] ?? widget.url);
    try {
      final ctrl = url.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(url))
          : VideoPlayerController.file(File(url));
      _c = ctrl;
      await ctrl.initialize();
      if (startAt > Duration.zero) await ctrl.seekTo(startAt);
      await ctrl.setPlaybackSpeed(_speed);
      ctrl.addListener(_onTick);
      await ctrl.play();
      if (mounted) setState(() => _err = null);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  void _onTick() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      _VideoViewCardState._savedMs['${widget.title}|$_title'] = c.value.position.inMilliseconds;
      _VideoViewCardState._savedEp[widget.title] = _idx;
    }
    final d = c.value.duration;
    if (d.inMilliseconds <= 0) return;
    if (_autoNext &&
        !_switching &&
        !c.value.isPlaying &&
        c.value.position >= d - const Duration(milliseconds: 400) &&
        _idx + 1 < _eps.length) {
      _switching = true;
      _switchTo(_idx + 1);
    }
  }

  Future<void> _switchTo(int i) async {
    if (_eps.isEmpty) return;
    final idx = i.clamp(0, _eps.length - 1).toInt();
    setState(() {
      _idx = idx;
      _switching = false;
      _epOpen = false;
    });
    _VideoViewCardState._savedEp[widget.title] = idx;
    await _open(idx, Duration.zero);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _c?.value.isPlaying == true) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    final c = _c;
    if (c != null && c.value.isInitialized && c.value.position.inMilliseconds > 0) {
      _VideoViewCardState._savedMs['${widget.title}|$_title'] = c.value.position.inMilliseconds;
    }
    _VideoViewCardState._savedEp[widget.title] = _idx;
    _VideoViewCardState._savedSpeed[widget.title] = _speed;
    _VideoViewCardState._persistPositions();
    c?.dispose();
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _cycleSpeed(VideoPlayerController c) {
    final i = _speeds.indexOf(_speed);
    _speed = _speeds[(i + 1) % _speeds.length];
    c.setPlaybackSpeed(_speed);
    _VideoViewCardState._savedSpeed[widget.title] = _speed;
    _VideoViewCardState._persistPositions();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(children: [
          Center(
            child: c == null || !c.value.isInitialized
                ? (_err != null
                    ? Text('播放失败：$_err', style: const TextStyle(color: Colors.white70, fontSize: 12))
                    : const CircularProgressIndicator(strokeWidth: 2))
                : AspectRatio(
                    aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                    child: VideoPlayer(c),
                  ),
          ),
          if (_controls)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(_idx),
                  ),
                  Expanded(
                    child: Text(_title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                  ),
                  if (_eps.length > 1) ...[
                    TextButton(
                      onPressed: () => setState(() => _epOpen = !_epOpen),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text('选集', style: TextStyle(color: Colors.white, fontSize: 11.5)),
                    ),
                    Row(children: [
                      const Text('自动', style: TextStyle(color: Colors.white70, fontSize: 10)),
                      Transform.scale(
                        scale: 0.65,
                        child: Switch(
                          value: _autoNext,
                          activeColor: const Color(0xFF2563EB),
                          onChanged: (v) => setState(() => _autoNext = v),
                        ),
                      ),
                    ]),
                  ],
                ]),
              ),
            ),
          if (_controls)
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Row(children: [
                IconButton(
                  icon: Icon(c?.value.isPlaying == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white),
                  onPressed: () {
                    final cc = _c;
                    if (cc == null) return;
                    if (cc.value.isPlaying) {
                      cc.pause();
                    } else {
                      cc.play();
                    }
                    setState(() {});
                    _scheduleHide();
                  },
                ),
                Text(_fmtDur(c?.value.position ?? Duration.zero),
                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace')),
                Expanded(
                  child: c == null
                      ? const SizedBox()
                      : VideoProgressIndicator(c,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                ),
                Text(_fmtDur(c?.value.duration ?? Duration.zero),
                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace')),
                TextButton(
                  onPressed: c == null ? null : () => _cycleSpeed(c),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: Text('${_speed}x',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          if (_epOpen)
            Positioned(
              right: 8,
              top: 52,
              bottom: 54,
              width: 230,
              child: Material(
                color: const Color(0xE60F172A),
                borderRadius: BorderRadius.circular(12),
                child: ListView.builder(
                  itemCount: _eps.length,
                  itemBuilder: (_, i) {
                    final on = i == _idx;
                    return GestureDetector(
                      onTap: () => _switchTo(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        color: on ? const Color(0x332563EB) : Colors.transparent,
                        child: Row(children: [
                          Text('EP${(i + 1).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontFamily: 'monospace',
                                  color: on ? const Color(0xFF60A5FA) : const Color(0xFF7886A0))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_eps[i]['title'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: on ? Colors.white : const Color(0xFFCBD5E1))),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class AudioViewCard extends StatefulWidget {
  final String title;
  final Map<String, dynamic> data;
  const AudioViewCard({super.key, required this.title, required this.data});

  @override
  State<AudioViewCard> createState() => _AudioViewCardState();
}

class _AudioViewCardState extends State<AudioViewCard> {
  Timer? _timer;
  String _state = '';

  @override
  void initState() {
    super.initState();
    _sync();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sync());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sync() async {
    try {
      final s = await AudioService.instance.status();
      if (mounted && s != _state) setState(() => _state = s);
    } catch (_) {}
  }

  Widget _btn(IconData icon, Future<String> Function() act) => IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          await act();
          await _sync();
        },
        icon: Icon(icon, size: 20, color: AppColors.brand),
      );

  @override
  Widget build(BuildContext context) {
    return _shell(
      icon: Icons.music_note_rounded,
      title: widget.title,
      subtitle: '音乐',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.brandSoft,
              child: const Icon(Icons.music_note_rounded, size: 17, color: AppColors.brand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                if (_state.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_state,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                  ),
              ]),
            ),
          ]),
          StreamBuilder<Duration>(
            stream: AudioService.instance.positionStream,
            builder: (_, snap) {
              final total = AudioService.instance.duration ?? Duration.zero;
              final pos = snap.data ?? AudioService.instance.position;
              final max = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
              final val = pos.inMilliseconds.toDouble().clamp(0.0, max);
              return Column(children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: val,
                    max: max,
                    activeColor: AppColors.brand,
                    inactiveColor: const Color(0xFF2A3550),
                    onChanged: (v) =>
                        AudioService.instance.seek(Duration(milliseconds: v.round())),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(children: [
                    Text(_fmtDur(pos),
                        style: const TextStyle(fontSize: 9.5, color: AppColors.muted, fontFamily: 'monospace')),
                    const Spacer(),
                    Text(total == Duration.zero ? '--:--' : _fmtDur(total),
                        style: const TextStyle(fontSize: 9.5, color: AppColors.muted, fontFamily: 'monospace')),
                  ]),
                ),
              ]);
            },
          ),
          Row(children: [
            _btn(Icons.play_arrow_rounded, () => AudioService.instance.resume()),
            _btn(Icons.pause_rounded, () => AudioService.instance.pause()),
            _btn(Icons.stop_rounded, () => AudioService.instance.stop()),
          ]),
        ]),
      ),
    );
  }
}

class ReaderViewCard extends StatefulWidget {
  final String title;
  final Map<String, dynamic> data;
  final bool fullscreen;
  const ReaderViewCard({super.key, required this.title, required this.data, this.fullscreen = false});

  @override
  State<ReaderViewCard> createState() => _ReaderViewCardState();
}

List<Map<String, String>> _parseChapters(Object? raw) {
  final out = <Map<String, String>>[];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        out.add({
          'title': (e['title'] ?? '').toString(),
          'url': (e['url'] ?? '').toString(),
          'content': (e['content'] ?? '').toString(),
        });
      }
    }
  }
  return out;
}

class _ReaderViewCardState extends State<ReaderViewCard> {
  static final Map<String, int> _savedChapter = {};
  static bool _stateLoaded = false;

  late final List<Map<String, String>> _chapters = _parseChapters(widget.data['chapters']);
  late int _index = ((widget.data['index'] as num?)?.toInt() ?? 1).clamp(1, _chapters.isEmpty ? 1 : _chapters.length).toInt() - 1;
  late String _content = (widget.data['content'] ?? '').toString();
  bool _loading = false;
  String? _err;

  String get _book => widget.title;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadState();
    if (!mounted) return;
    if (_chapters.isNotEmpty && _content.trim().isEmpty) await _load(_index);
  }

  Future<void> _loadState() async {
    if (_stateLoaded) return;
    _stateLoaded = true;
    try {
      final dir = await NativeBridge.appDataDir();
      if (dir.isEmpty) return;
      final f = File('$dir/reader_chapters.json');
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map;
      _savedChapter.clear();
      m.forEach((k, v) {
        final n = int.tryParse('$v');
        if (n != null) _savedChapter['$k'] = n;
      });
      if (!mounted) return;
      if (_chapters.isNotEmpty) {
        final saved = _savedChapter[_book];
        if (saved != null && saved >= 0 && saved < _chapters.length) {
          setState(() => _index = saved);
        }
      }
    } catch (_) {}
  }

  void _persistChapter() {
    _savedChapter[_book] = _index;
    Future(() async {
      try {
        final dir = await NativeBridge.appDataDir();
        if (dir.isEmpty) return;
        await File('$dir/reader_chapters.json').writeAsString(jsonEncode(_savedChapter));
      } catch (_) {}
    });
  }

  Future<void> _load(int i) async {
    if (_chapters.isEmpty) return;
    final idx = i.clamp(0, _chapters.length - 1);
    setState(() {
      _index = idx;
      _loading = true;
      _err = null;
    });
    _persistChapter();
    final c = _chapters[idx];
    var text = c['content'] ?? '';
    if (text.trim().isEmpty) {
      final url = c['url'] ?? '';
      if (url.isNotEmpty) text = await fetchChapterText(url) ?? '';
    }
    if (!mounted) return;
    setState(() {
      _content = text;
      _loading = false;
      _err = text.trim().isEmpty ? '正文加载失败，可能是链接失效' : null;
    });
  }

  void _openCatalog() {
    if (_chapters.isEmpty) return;
    showCatalogSheet(
      context,
      titles: [for (final c in _chapters) c['title'] ?? ''],
      current: _index,
      onPick: _load,
    );
  }

  void _openFullscreen() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ReaderFullscreen(
        title: _book,
        chapters: _chapters,
        index: _index,
        content: _content,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_chapters.isEmpty) {
      return _shell(
        icon: Icons.menu_book_rounded,
        title: widget.title,
        subtitle: '${_content.length} 字',
        child: PaginatedReader(
          text: _content,
          title: widget.title,
          height: widget.fullscreen ? null : 320,
          onFullscreen: widget.fullscreen ? null : _openFullscreen,
        ),
      );
    }
    final chapterTitle = _chapters[_index]['title'] ?? '第 ${_index + 1} 章';
    final Widget body;
    if (_loading) {
      body = const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (_err != null) {
      body = Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_err!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _load(_index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(8)),
              child: const Text('重新加载', style: TextStyle(fontSize: 10.5, color: Colors.white)),
            ),
          ),
        ]),
      );
    } else {
      body = PaginatedReader(
        text: _content,
        title: '$_book · $chapterTitle',
        height: widget.fullscreen ? null : 320,
        onCatalog: _openCatalog,
        onFullscreen: widget.fullscreen ? null : _openFullscreen,
      );
    }
    return _shell(
      icon: Icons.menu_book_rounded,
      title: widget.title,
      subtitle: chapterTitle,
      child: body,
    );
  }
}

class _ReaderFullscreen extends StatefulWidget {
  final String title;
  final List<Map<String, String>> chapters;
  final int index;
  final String content;
  const _ReaderFullscreen({
    required this.title,
    required this.chapters,
    required this.index,
    required this.content,
  });
  @override
  State<_ReaderFullscreen> createState() => _ReaderFullscreenState();
}

class _ReaderFullscreenState extends State<_ReaderFullscreen> {
  String _orient = 'auto';
  late int _index = widget.index;
  late String _content = widget.content;
  bool _loading = false;

  String get _chapterTitle =>
      widget.chapters.isEmpty ? widget.title : (widget.chapters[_index]['title'] ?? '第 ${_index + 1} 章');

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    super.dispose();
  }

  void _setOrient(String mode) {
    setState(() => _orient = mode);
    switch (mode) {
      case 'portrait':
        SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
        break;
      case 'landscape':
        SystemChrome.setPreferredOrientations(
            const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        break;
      default:
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    }
  }

  Widget _orientBtn(String mode, String label) {
    final on = _orient == mode;
    return GestureDetector(
      onTap: () => _setOrient(mode),
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.brand : const Color(0xFF1A2338),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: on ? Colors.white : const Color(0xFF9AA7C0))),
      ),
    );
  }

  Future<void> _load(int i) async {
    if (widget.chapters.isEmpty) return;
    final idx = i.clamp(0, widget.chapters.length - 1);
    setState(() {
      _index = idx;
      _loading = true;
    });
    _persistChapter();
    final c = widget.chapters[idx];
    var text = c['content'] ?? '';
    if (text.trim().isEmpty && (c['url'] ?? '').isNotEmpty) {
      text = await fetchChapterText(c['url']!) ?? '';
    }
    if (!mounted) return;
    setState(() {
      _content = text;
      _loading = false;
    });
  }

  void _persistChapter() {
    Future(() async {
      try {
        final dir = await NativeBridge.appDataDir();
        if (dir.isEmpty) return;
        final f = File('$dir/reader_chapters.json');
        Map<String, dynamic> m = {};
        if (await f.exists()) {
          m = Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
        }
        m[widget.title] = _index;
        await f.writeAsString(jsonEncode(m));
      } catch (_) {}
    });
  }

  void _openCatalog() {
    if (widget.chapters.isEmpty) return;
    showCatalogSheet(
      context,
      titles: [for (final c in widget.chapters) c['title'] ?? ''],
      current: _index,
      onPick: _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141B2E),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text('${widget.title} · $_chapterTitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                _orientBtn('auto', '自动'),
                _orientBtn('portrait', '竖'),
                _orientBtn('landscape', '横'),
              ]),
            ),
            const Divider(height: 1, color: Color(0xFF1A2338)),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : PaginatedReader(
                      text: _content,
                      title: '${widget.title} · $_chapterTitle',
                      height: null,
                      fontScale: 1.12,
                      onCatalog: widget.chapters.isEmpty ? null : _openCatalog,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 漫画：按话分页，左右滑动翻页，双指缩放，目录搜索/跳话。
class ComicViewCard extends StatefulWidget {
  final String title;
  final Map<String, dynamic> data;
  final bool fullscreen;
  const ComicViewCard({super.key, required this.title, required this.data, this.fullscreen = false});

  @override
  State<ComicViewCard> createState() => _ComicViewCardState();
}

class _ComicViewCardState extends State<ComicViewCard> {
  static final Map<String, int> _savedChapter = {};
  static final Map<String, int> _savedPage = {};
  static bool _progLoaded = false;

  late final List<Map<String, dynamic>> _chapters = _parse(widget.data['chapters']);
  late int _index = ((widget.data['index'] as num?)?.toInt() ?? 1).clamp(1, _chapters.isEmpty ? 1 : _chapters.length).toInt() - 1;
  final _pc = PageController();
  int _page = 0;
  bool _singlePage = false;

  static List<Map<String, dynamic>> _parse(Object? raw) {
    final out = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final pages = ((e['pages'] as List?) ?? const []).map((p) => p.toString()).where((p) => p.isNotEmpty).toList();
          if (pages.isNotEmpty) out.add({'title': (e['title'] ?? '').toString(), 'pages': pages});
        }
      }
    }
    return out;
  }

  List<String> get _pages => ((_chapters.isEmpty ? const [] : _chapters[_index]['pages']) as List).cast<String>();

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    if (_progLoaded) return;
    _progLoaded = true;
    try {
      final dir = await NativeBridge.appDataDir();
      if (dir.isEmpty) return;
      final f = File('$dir/comic_progress.json');
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map;
      final ch = (m['chapters'] as Map?) ?? const {};
      final pg = (m['pages'] as Map?) ?? const {};
      ch.forEach((k, v) {
        final n = int.tryParse('$v');
        if (n != null) _savedChapter['$k'] = n;
      });
      pg.forEach((k, v) {
        final n = int.tryParse('$v');
        if (n != null) _savedPage['$k'] = n;
      });
      if (!mounted) return;
      final savedCh = _savedChapter[widget.title];
      if (savedCh != null && savedCh >= 0 && savedCh < _chapters.length) {
        setState(() {
          _index = savedCh;
          _page = _savedPage['${widget.title}|$savedCh'] ?? 0;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pc.hasClients && _pages.isNotEmpty) {
            final doublePage = MediaQuery.of(context).orientation == Orientation.landscape && !_singlePage;
            final count = doublePage ? (_pages.length + 1) ~/ 2 : _pages.length;
            final target = (doublePage ? _page ~/ 2 : _page).clamp(0, count - 1).toInt();
            _pc.jumpToPage(target);
          }
        });
      }
    } catch (_) {}
  }

  void _persist() {
    Future(() async {
      try {
        final dir = await NativeBridge.appDataDir();
        if (dir.isEmpty) return;
        await File('$dir/comic_progress.json')
            .writeAsString(jsonEncode({'chapters': _savedChapter, 'pages': _savedPage}));
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _save() {
    _savedChapter[widget.title] = _index;
    _savedPage['${widget.title}|$_index'] = _page;
    _persist();
  }

  void _gotoChapter(int i) {
    if (_chapters.isEmpty) return;
    setState(() {
      _index = i.clamp(0, _chapters.length - 1).toInt();
      _page = _savedPage['${widget.title}|$_index'] ?? 0;
    });
    _save();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pc.hasClients) return;
      final pages = _pages;
      final doublePage = MediaQuery.of(context).orientation == Orientation.landscape;
      final count = doublePage ? (pages.length + 1) ~/ 2 : pages.length;
      final target = (doublePage ? _page ~/ 2 : _page).clamp(0, count - 1).toInt();
      _pc.jumpToPage(target);
    });
  }

  void _openCatalog() {
    if (_chapters.isEmpty) return;
    showCatalogSheet(
      context,
      titles: [for (final c in _chapters) (c['title'] ?? '') as String],
      current: _index,
      unit: '话',
      jumpLabel: '跳话',
      onPick: _gotoChapter,
    );
  }

  void _nextPage() {
    final pages = _pages;
    if (_page + 1 < pages.length) {
      _pc.nextPage(duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    } else if (_index + 1 < _chapters.length) {
      _gotoChapter(_index + 1);
    }
  }

  void _prevPage() {
    if (_page > 0) {
      _pc.previousPage(duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    } else if (_index > 0) {
      _gotoChapter(_index - 1);
    }
  }

  Widget _image(String path) {
    Widget err(_, __, ___) => const Center(
          child: Text('图片加载失败', style: TextStyle(fontSize: 11, color: Color(0xFF7886A0))),
        );
    if (path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.contain, errorBuilder: err);
    }
    return Image.file(File(path), fit: BoxFit.contain, errorBuilder: err);
  }

  @override
  Widget build(BuildContext context) {
    if (_chapters.isEmpty) {
      return _shell(icon: Icons.auto_stories_rounded, title: widget.title, child: const Padding(padding: EdgeInsets.all(14), child: Text('（没有图片页）')));
    }
    final pages = _pages;
    final h = widget.fullscreen ? MediaQuery.of(context).size.height * 0.6 : 360.0;
    final title = (_chapters[_index]['title'] ?? '').toString();
    final doublePage = MediaQuery.of(context).orientation == Orientation.landscape && !_singlePage;
    final count = doublePage ? (pages.length + 1) ~/ 2 : pages.length;
    Widget one(String p) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: _image(p)),
        );
    final viewer = SizedBox(
      height: h,
      child: Container(
        color: const Color(0xFF0B1220),
        child: PageView.builder(
          controller: _pc,
          itemCount: count,
          onPageChanged: (i) {
            setState(() => _page = doublePage ? i * 2 : i);
            _save();
          },
          itemBuilder: (_, i) {
            if (!doublePage) return one(pages[i]);
            final a = i * 2;
            final b = a + 1;
            return Row(children: [
              Expanded(child: one(pages[a])),
              Expanded(child: b < pages.length ? one(pages[b]) : const SizedBox()),
            ]);
          },
        ),
      ),
    );
    final footer = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF141B2E),
        border: Border(top: BorderSide(color: Color(0xFF1A2338))),
      ),
      child: Row(children: [
        _cbtn('<', _prevPage),
        Expanded(
          child: GestureDetector(
            onTap: _openCatalog,
            child: Column(children: [
              Text('第 ${_page + 1} / ${pages.length} 页',
                  style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Color(0xFF9AA7C0))),
              const SizedBox(height: 2),
              const Text('左右滑动翻页 · 双指缩放', style: TextStyle(fontSize: 8.5, color: Color(0xFFB6C0CD))),
            ]),
          ),
        ),
        _cbtn('>', _nextPage),
        const SizedBox(width: 6),
        _cbtn('目录', _openCatalog, width: 40),
        if (MediaQuery.of(context).orientation == Orientation.landscape) ...[
          const SizedBox(width: 6),
          _cbtn(_singlePage ? '双页' : '单页', () => setState(() => _singlePage = !_singlePage), width: 40),
        ],
      ]),
    );
    return _shell(icon: Icons.auto_stories_rounded, title: widget.title, subtitle: title, child: Column(children: [viewer, footer]));
  }

  Widget _cbtn(String label, VoidCallback onTap, {double width = 34}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1A2338)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFAEB9CC))),
      ),
    );
  }
}

/// 分页阅读：按可视区域排版切页，支持左右滑动、按钮翻页、跳页、字号与记住进度。
class PaginatedReader extends StatefulWidget {
  final String text;
  final String title;
  final double? height;
  final double fontScale;
  final VoidCallback? onFullscreen;
  final VoidCallback? onCatalog;
  const PaginatedReader({
    super.key,
    required this.text,
    required this.title,
    this.height,
    this.fontScale = 1.0,
    this.onFullscreen,
    this.onCatalog,
  });

  @override
  State<PaginatedReader> createState() => _PaginatedReaderState();
}

class _PaginatedReaderState extends State<PaginatedReader> {
  static final Map<String, int> _savedOffsets = {};
  static bool _progressLoaded = false;
  final _pc = PageController();
  List<String> _pages = const [];
  List<int> _starts = const [];
  Size _layout = Size.zero;
  double _lastFont = 0;
  String _lastText = '';
  double _zoom = 1.0;
  int _page = 0;

  double get _fontSize => 13 * widget.fontScale * _zoom;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    if (_progressLoaded) return;
    _progressLoaded = true;
    try {
      final dir = await NativeBridge.appDataDir();
      if (dir.isEmpty) return;
      final f = File('$dir/reader_progress.json');
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map;
      _savedOffsets.clear();
      m.forEach((k, v) {
        final n = int.tryParse('$v');
        if (n != null) _savedOffsets['$k'] = n;
      });
      if (mounted) setState(() => _layout = Size.zero);
    } catch (_) {}
  }

  void _persist() {
    Future(() async {
      try {
        final dir = await NativeBridge.appDataDir();
        if (dir.isEmpty) return;
        await File('$dir/reader_progress.json').writeAsString(jsonEncode(_savedOffsets));
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  String get _key => '${widget.title}\u0000${widget.text.length}';

  void _paginate(double width, double height) {
    final style = TextStyle(fontSize: _fontSize, height: 1.85, color: AppColors.text);
    final text = widget.text.isEmpty ? '（没有正文）' : widget.text;
    final pages = <String>[];
    final starts = <int>[];
    var start = 0;
    while (start < text.length) {
      var lo = start + 1;
      var hi = text.length;
      var best = start + 1;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        final tp = TextPainter(
          text: TextSpan(text: text.substring(start, mid), style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width);
        if (tp.height <= height) {
          best = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      if (best < text.length) {
        final cu = text.codeUnitAt(best);
        if (cu >= 0xDC00 && cu <= 0xDFFF) best += 1;
        if (best < text.length && text[best] != '\n' && text[best - 1] != '\n') {
          final back = text.lastIndexOf(RegExp(r'\s'), best);
          if (back > start + 20) best = back + 1;
        }
      }
      if (best <= start) best = start + 1;
      pages.add(text.substring(start, best));
      starts.add(start);
      start = best;
    }
    _pages = pages;
    _starts = starts;
  }

  int _pageOfOffset(int offset) {
    var p = 0;
    for (var i = 0; i < _starts.length; i++) {
      if (_starts[i] <= offset) p = i;
    }
    return p;
  }

  void _save() {
    if (_page >= 0 && _page < _starts.length) {
      _savedOffsets[_key] = _starts[_page];
      _persist();
    }
  }

  void _goto(int page) {
    if (_pages.isEmpty) return;
    _pc.animateToPage(page.clamp(0, _pages.length - 1),
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _cycleFont() {
    final next = _zoom >= 1.3 ? 1.0 : (_zoom >= 1.15 ? 1.3 : 1.15);
    setState(() => _zoom = next);
  }

  Future<void> _jumpDialog() async {
    final c = TextEditingController(text: '${_page + 1}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳页', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(hintText: '1 - ${_pages.length}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('跳转')),
        ],
      ),
    );
    if (ok == true) _goto((int.tryParse(c.text.trim()) ?? 1) - 1);
    c.dispose();
  }

  Widget _buildSized(BoxConstraints cons) {
    final width = cons.maxWidth.isFinite ? cons.maxWidth : 320.0;
    final totalH = cons.maxHeight.isFinite ? cons.maxHeight : 360.0;
    final height = totalH > 140 ? totalH - 54.0 : (totalH * 0.72);
    final sizeChanged = (_layout.width - width).abs() > 0.5 ||
        (_layout.height - height).abs() > 0.5 ||
        (_lastFont - _fontSize).abs() > 0.01 ||
        _lastText != widget.text;
    if (sizeChanged) {
      final keep = _page < _starts.length ? _starts[_page] : 0;
      _lastText = widget.text;
      _layout = Size(width, height);
      _lastFont = _fontSize;
      _paginate(width, height);
      final saved = _savedOffsets[_key];
      _page = _pageOfOffset(saved != null && saved > keep ? saved : keep);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pc.hasClients) _pc.jumpToPage(_page);
      });
    }
    final total = _pages.isEmpty ? 1 : _pages.length;
    final footer = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF141B2E),
        border: Border(top: BorderSide(color: Color(0xFF1A2338))),
      ),
      child: Row(children: [
        _btn('<', _page > 0 ? () => _goto(_page - 1) : null),
        Expanded(
          child: GestureDetector(
            onTap: _jumpDialog,
            child: Column(children: [
              Text('第 ' + (_page + 1).toString() + ' / ' + total.toString() + ' 页',
                  style: const TextStyle(
                      fontSize: 10.5, fontFamily: 'monospace', color: Color(0xFF9AA7C0))),
              const SizedBox(height: 2),
              const Text('左右滑动翻页', style: TextStyle(fontSize: 8.5, color: Color(0xFFB6C0CD))),
            ]),
          ),
        ),
        _btn('>', _page < total - 1 ? () => _goto(_page + 1) : null),
        const SizedBox(width: 6),
        _btn('A', _cycleFont),
        if (widget.onCatalog != null) ...[
          const SizedBox(width: 6),
          _btn('目录', widget.onCatalog, width: 40),
        ],
        if (widget.onFullscreen != null) ...[
          const SizedBox(width: 6),
          _btn('⤢', widget.onFullscreen),
        ],
      ]),
    );
    final Widget pageView;
    if (_pages.isEmpty) {
      pageView = const Center(
        child: Text('（没有正文）', style: TextStyle(fontSize: 12, color: Color(0xFF7886A0))),
      );
    } else {
      pageView = PageView.builder(
        controller: _pc,
        itemCount: _pages.length,
        onPageChanged: (i) {
          setState(() => _page = i);
          _save();
        },
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Text(_pages[i.clamp(0, _pages.length - 1)],
              style: TextStyle(fontSize: _fontSize, height: 1.85, color: AppColors.text)),
        ),
      );
    }
    return Column(children: [Expanded(child: pageView), footer]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.height != null) {
      return SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (_, cons) => _buildSized(cons)),
      );
    }
    return LayoutBuilder(builder: (_, cons) => _buildSized(cons));
  }

  Widget _btn(String label, VoidCallback? onTap, {double width = 34}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1A2338)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: onTap == null ? const Color(0xFFCBD5E1) : const Color(0xFFAEB9CC))),
      ),
    );
  }
}
