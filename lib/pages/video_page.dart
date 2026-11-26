import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 全局导航 key（AI 要求播视频时，从这里跳转全屏播放页）。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 全屏视频播放页（支持 http 直链 / 本地文件）。
class VideoPlayerPage extends StatefulWidget {
  final String url;
  final String? title;
  const VideoPlayerPage({super.key, required this.url, this.title});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _c;
  String? _err;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ctrl = widget.url.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(widget.url))
          : VideoPlayerController.file(File(widget.url));
      _c = ctrl;
      await ctrl.initialize();
      await ctrl.setLooping(false);
      await ctrl.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? '视频', style: const TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: _err != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text('播放失败：$_err',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
              )
            : (c == null || !c.value.isInitialized)
                ? const CircularProgressIndicator(color: Colors.white)
                : AspectRatio(
                    aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                    child: Stack(alignment: Alignment.bottomCenter, children: [
                      VideoPlayer(c),
                      VideoProgressIndicator(c, allowScrubbing: true),
                      Align(
                        alignment: Alignment.center,
                        child: IconButton(
                          iconSize: 48,
                          color: Colors.white70,
                          icon: Icon(c.value.isPlaying ? Icons.pause_circle : Icons.play_circle),
                          onPressed: () {
                            setState(() {
                              c.value.isPlaying ? c.pause() : c.play();
                            });
                          },
                        ),
                      ),
                    ]),
                  ),
      ),
    );
  }
}
