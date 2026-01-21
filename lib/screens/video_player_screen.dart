import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_info.dart';

class VideoPlayerScreen extends StatefulWidget {
  final VideoInfo videoInfo;
  final String? subtitlePath;

  const VideoPlayerScreen({super.key, required this.videoInfo, this.subtitlePath});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  Player? _player;
  VideoController? _videoController;
  bool _isLoading = true;
  String? _errorMessage;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    print('🎬 VideoPlayerScreen: Initializing video...');
    try {
      final videoPath = widget.videoInfo.path;
      print('🎬 VideoPlayerScreen: Loading video: $videoPath');

      // Zkontrolujeme zda soubor existuje
      final fileExists = await File(videoPath).exists();
      print('🎬 VideoPlayerScreen: File exists: $fileExists');

      if (!fileExists) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'video.load_error';
        });
        return;
      }

      _player = Player();
      _videoController = VideoController(_player!);

      // Nastavit callback pro chyby
      _player!.stream.error.listen((error) {
        print('🔴 VideoPlayerScreen: Player error: $error');
      });

      // Open video file - use file:// protocol for local files
      print('🎬 VideoPlayerScreen: Opening media...');
      final mediaUri = videoPath.startsWith('file://') ? videoPath : 'file://$videoPath';
      print('🎬 VideoPlayerScreen: Media URI: $mediaUri');
      await _player!.open(Media(mediaUri));

      // Add subtitles if available
      if (widget.subtitlePath != null) {
        print('🎬 VideoPlayerScreen: Setting subtitle: ${widget.subtitlePath}');
        final subtitleUri = widget.subtitlePath!.startsWith('file://') ? widget.subtitlePath! : 'file://${widget.subtitlePath}';
        await _player!.setSubtitleTrack(SubtitleTrack.uri(subtitleUri));
      }

      // Wait for video to load and get information
      print('🎬 VideoPlayerScreen: Waiting for video to load...');

      // Wait for first frame or timeout
      int attempts = 0;
      while (_player!.state.duration == Duration.zero && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      _duration = _player!.state.duration;
      final width = _player!.state.width;
      final height = _player!.state.height;
      print('🎬 VideoPlayerScreen: Video loaded, duration: $_duration, size: ${width}x$height');

      // Automatically start playback
      await _player!.play();
      print('🎬 VideoPlayerScreen: Playback started');

      setState(() {
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      print('🔴 VideoPlayerScreen: Error loading video: $e');
      print('🔴 Stack trace: $stackTrace');
      setState(() {
        _isLoading = false;
        _errorMessage = 'video.load_error';
      });
    }
  }

  @override
  void dispose() {
    print('🎬 VideoPlayerScreen: Disposing...');
    _player?.dispose();
    super.dispose();
  }

  void _play() {
    _player?.play();
  }

  void _pause() {
    _player?.pause();
  }

  void _seek(Duration position) {
    _player?.seek(position);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('player.title'.tr()), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text('video.loading'.tr())]),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: Text('player.back'.tr())),
          ],
        ),
      );
    }

    return _buildVideoPlayer();
  }

  Widget _buildVideoPlayer() {
    return Column(
      children: [
        // Info panel
        if (widget.subtitlePath != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('player.testing_subtitles'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText(widget.subtitlePath!.split('/').last),
                const SizedBox(height: 4),
                SelectableText('player.check_timing'.tr(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ),
          ),

        // Video player
        Expanded(
          child: Center(
            child: _videoController != null ? Video(controller: _videoController!, controls: NoVideoControls) : const CircularProgressIndicator(),
          ),
        ),

        // Control elements
        _buildControls(),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time slider
          StreamBuilder<Duration>(
            stream: _player?.stream.position,
            initialData: Duration.zero,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final duration = _player?.state.duration ?? _duration;

              return Column(
                children: [
                  Slider(
                    value: position.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble()),
                    max: duration.inMilliseconds.toDouble(),
                    onChanged: (value) {
                      _seek(Duration(milliseconds: value.toInt()));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_formatDuration(position)), Text(_formatDuration(duration))]),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),

          // Playback buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10),
                iconSize: 32,
                onPressed: () {
                  final currentPosition = _player?.state.position ?? Duration.zero;
                  _seek(currentPosition - const Duration(seconds: 10));
                },
              ),
              const SizedBox(width: 16),
              StreamBuilder<bool>(
                stream: _player?.stream.playing,
                initialData: _player?.state.playing ?? false,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data ?? false;
                  return IconButton(
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    iconSize: 48,
                    onPressed: () {
                      if (isPlaying) {
                        _pause();
                      } else {
                        _play();
                      }
                    },
                  );
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.forward_10),
                iconSize: 32,
                onPressed: () {
                  final currentPosition = _player?.state.position ?? Duration.zero;
                  _seek(currentPosition + const Duration(seconds: 10));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}
