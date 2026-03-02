import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../bloc/subtitle/subtitle_bloc.dart';
import '../bloc/subtitle/subtitle_event.dart';
import '../bloc/subtitle/subtitle_state.dart';
import '../models/subtitle.dart';
import '../models/video_info.dart';
import 'subtitle_editor_screen.dart';

class VideoPlayerScreen extends StatefulWidget {
  final VideoInfo videoInfo;
  final String? subtitlePath;
  final List<Subtitle>? availableSubtitles;
  final List<Subtitle>? alternativeSubtitles;
  final Subtitle? currentSubtitle;
  final Subtitle? selectedSubtitle;

  const VideoPlayerScreen({super.key, required this.videoInfo, this.subtitlePath, this.availableSubtitles, this.alternativeSubtitles, this.currentSubtitle, this.selectedSubtitle});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  Player? _player;
  VideoController? _videoController;
  bool _isLoading = true;
  String? _errorMessage;
  Duration _duration = Duration.zero;
  bool _showSubtitleSelector = false;
  String? _currentSubtitlePath;
  Subtitle? _currentSubtitle;

  @override
  void initState() {
    super.initState();
    _currentSubtitlePath = widget.subtitlePath;
    _currentSubtitle = widget.currentSubtitle;
    print('🎬 VideoPlayerScreen: Available subtitles: ${widget.availableSubtitles?.length ?? 0}');
    print('🎬 VideoPlayerScreen: Alternative subtitles: ${widget.alternativeSubtitles?.length ?? 0}');
    print('🎬 VideoPlayerScreen: Current subtitle: ${widget.currentSubtitle?.title}');
    print('🎬 VideoPlayerScreen: Selected subtitle: ${widget.selectedSubtitle?.title}');
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
    final hasSubtitlesToSelect =
        (widget.availableSubtitles != null && widget.availableSubtitles!.isNotEmpty) || (widget.alternativeSubtitles != null && widget.alternativeSubtitles!.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Text('player.title'.tr()),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (hasSubtitlesToSelect)
            IconButton(
              icon: const Icon(Icons.subtitles),
              tooltip: 'Vybrat titulky',
              onPressed: () {
                setState(() {
                  _showSubtitleSelector = !_showSubtitleSelector;
                });
              },
            ),
        ],
      ),
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
        if (_currentSubtitlePath != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('player.testing_subtitles'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SelectableText(_currentSubtitle?.title ?? _currentSubtitlePath!.split('/').last),
                      const SizedBox(height: 4),
                      SelectableText('player.check_timing'.tr(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    // Pause video before navigating
                    _pause();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SubtitleEditorScreen(
                          videoPath: widget.videoInfo.path,
                          subtitlePath: _currentSubtitlePath!,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: Text('player.edit_subtitles'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

        // Subtitle selector panel
        if (_showSubtitleSelector) _buildSubtitleSelectorPanel(),

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

  Widget _buildSubtitleSelectorPanel() {
    // Combine all subtitles and alternatives
    final allSubtitles = <Subtitle>[];
    if (widget.availableSubtitles != null) {
      allSubtitles.addAll(widget.availableSubtitles!);
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Vybrat titulky', style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showSubtitleSelector = false;
                    });
                  },
                  child: const Text('Zavřít'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                // Main subtitles section
                if (widget.availableSubtitles != null && widget.availableSubtitles!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      'Hlavní titulky',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                    ),
                  ),
                  ...widget.availableSubtitles!.map((subtitle) => _buildSubtitleTile(subtitle)),
                ],

                // Alternative subtitles section
                if (widget.alternativeSubtitles != null && widget.alternativeSubtitles!.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: [
                        const Icon(Icons.list_alt, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Alternativní titulky (${widget.alternativeSubtitles!.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                  ...widget.alternativeSubtitles!.map((subtitle) => _buildSubtitleTile(subtitle)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitleTile(Subtitle subtitle) {
    final isSelected = _currentSubtitle?.id == subtitle.id;
    final isOriginallySelected = widget.selectedSubtitle?.id == subtitle.id;

    return ListTile(
      selected: isSelected,
      leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isOriginallySelected ? Colors.blue.shade300 : null),
      title: Text(subtitle.title, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : (isOriginallySelected ? FontWeight.w500 : FontWeight.normal))),
      subtitle: Text('${subtitle.format.toUpperCase()} • ${subtitle.language.toUpperCase()}', style: const TextStyle(fontSize: 12)),
      trailing: isOriginallySelected && !isSelected ? const Icon(Icons.check_circle_outline, size: 20, color: Colors.grey) : null,
      onTap: () => _loadSubtitle(subtitle),
    );
  }

  Future<void> _loadSubtitle(Subtitle subtitle) async {
    // Save current playback position
    final currentPosition = _player?.state.position ?? Duration.zero;
    final wasPlaying = _player?.state.playing ?? false;

    // Show loading
    setState(() {
      _isLoading = true;
    });

    try {
      // Download the subtitle
      context.read<SubtitleBloc>().add(DownloadSubtitle(subtitle, widget.videoInfo));

      // Listen for download completion
      await for (final state in context.read<SubtitleBloc>().stream) {
        if (state is SubtitleDownloaded) {
          // Update subtitle in player
          await _reloadWithNewSubtitle(state.path, subtitle, currentPosition, wasPlaying);
          break;
        } else if (state is SubtitleError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: Colors.red));
          }
          setState(() {
            _isLoading = false;
          });
          break;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při načítání titulků: $e'), backgroundColor: Colors.red));
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _reloadWithNewSubtitle(String newSubtitlePath, Subtitle subtitle, Duration position, bool shouldPlay) async {
    try {
      // Remove current subtitle track
      await _player?.setSubtitleTrack(SubtitleTrack.no());

      // Set new subtitle track
      final subtitleUri = newSubtitlePath.startsWith('file://') ? newSubtitlePath : 'file://$newSubtitlePath';
      await _player?.setSubtitleTrack(SubtitleTrack.uri(subtitleUri));

      // Restore playback position
      await _player?.seek(position);

      // Resume playback if it was playing
      if (shouldPlay) {
        await _player?.play();
      }

      // Update state
      setState(() {
        _currentSubtitlePath = newSubtitlePath;
        _currentSubtitle = subtitle;
        _isLoading = false;
        _showSubtitleSelector = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Titulky změněny: ${subtitle.title}'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      print('🔴 Error reloading subtitle: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při přepnutí titulků'), backgroundColor: Colors.red));
      }
    }
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
