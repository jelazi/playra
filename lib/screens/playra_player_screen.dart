import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../bloc/settings/playra_settings_cubit.dart';
import '../models/subtitle_style_settings.dart';
import '../models/video_info.dart';
import '../models/video_item.dart';
import '../services/playra_storage.dart';
import 'subtitle_search_screen.dart';

/// Main video player screen. Receives a [VideoItem] and a fully-prepared
/// playback URL (already passed through SMB proxy if needed).
class PlayraPlayerScreen extends StatefulWidget {
  final VideoItem video;
  final String playUrl;

  const PlayraPlayerScreen({super.key, required this.video, required this.playUrl});

  @override
  State<PlayraPlayerScreen> createState() => _PlayraPlayerScreenState();
}

class _PlayraPlayerScreenState extends State<PlayraPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  bool _showControls = true;
  bool _isReady = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  Timer? _hideTimer;
  Timer? _resumeSaveTimer;

  // Gesture overlay
  String? _overlayText;
  IconData? _overlayIcon;
  Timer? _overlayTimer;
  double _gestureStartBrightness = 0.5;
  double _gestureStartVolume = 0.5;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _player.stream.position.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
    _player.stream.buffer.listen((_) {
      if (!_isReady && mounted) setState(() => _isReady = true);
    });

    _resumeSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _persistResume());

    _open();
    _startHideTimer();
  }

  Future<void> _open() async {
    final settings = PlayraStorage.getPlayerSettings();
    final resumeMs = settings.resumePlayback ? PlayraStorage.getResume(widget.video.id) : null;

    await _player.open(Media(widget.playUrl));

    if (resumeMs != null && resumeMs > 5000) {
      // wait briefly for duration to be known
      var attempts = 0;
      while (_duration == Duration.zero && attempts < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      if (resumeMs < (_duration.inMilliseconds - 5000)) {
        await _player.seek(Duration(milliseconds: resumeMs));
      }
    }

    // remember initial brightness/volume for gesture deltas
    try {
      _gestureStartBrightness = await ScreenBrightness().current;
    } catch (_) {}
    try {
      _gestureStartVolume = await FlutterVolumeController.getVolume() ?? 0.5;
    } catch (_) {}
  }

  Future<void> _persistResume() async {
    if (_duration.inMilliseconds == 0) return;
    final settings = PlayraStorage.getPlayerSettings();
    if (!settings.resumePlayback) return;
    // if near end, clear
    if (_position.inMilliseconds > _duration.inMilliseconds - 10000) {
      await PlayraStorage.clearResume(widget.video.id);
    } else {
      await PlayraStorage.setResume(widget.video.id, _position.inMilliseconds);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _overlayTimer?.cancel();
    _resumeSaveTimer?.cancel();
    _persistResume();
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _flashOverlay(IconData icon, String text) {
    setState(() {
      _overlayIcon = icon;
      _overlayText = text;
    });
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _overlayText = null);
    });
  }

  Future<void> _onVerticalDrag(DragUpdateDetails d, bool isLeft) async {
    final settings = PlayraStorage.getPlayerSettings();
    if (!settings.gesturesEnabled) return;
    final size = MediaQuery.of(context).size;
    final delta = -d.delta.dy / (size.height * 0.6); // full swipe = ~60% of screen height
    if (isLeft) {
      try {
        final current = await ScreenBrightness().current;
        var newVal = (current + delta).clamp(0.0, 1.0);
        await ScreenBrightness().setScreenBrightness(newVal);
        _flashOverlay(Icons.brightness_6, '${(newVal * 100).round()}%');
      } catch (_) {}
    } else {
      try {
        final current = await FlutterVolumeController.getVolume() ?? 0.5;
        var newVal = (current + delta).clamp(0.0, 1.0);
        await FlutterVolumeController.setVolume(newVal);
        _flashOverlay(Icons.volume_up, '${(newVal * 100).round()}%');
      } catch (_) {}
    }
  }

  void _onHorizontalDrag(DragUpdateDetails d) {
    final delta = Duration(milliseconds: (d.primaryDelta ?? 0).toInt() * 1000 ~/ 5);
    final target = _position + delta;
    final clamped = Duration(milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds));
    _player.seek(clamped);
    _flashOverlay(delta.isNegative ? Icons.fast_rewind : Icons.fast_forward, _formatDuration(clamped));
  }

  Future<void> _seekRelative(Duration d) async {
    final target = _position + d;
    final clamped = Duration(milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds));
    await _player.seek(clamped);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;

    return BlocBuilder<PlayraSettingsCubit, PlayraSettingsState>(
      builder: (context, settings) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: Video(controller: _controller, controls: NoVideoControls, subtitleViewConfiguration: _subtitleConfig(settings.subtitleStyle)),
              ),

              // Tap & gesture layer
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggleControls,
                        onDoubleTap: () => _seekRelative(Duration(seconds: -PlayraStorage.getPlayerSettings().seekStepSeconds.toInt())),
                        onVerticalDragUpdate: (d) => _onVerticalDrag(d, true),
                        onHorizontalDragUpdate: _onHorizontalDrag,
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggleControls,
                        onDoubleTap: () => _seekRelative(Duration(seconds: PlayraStorage.getPlayerSettings().seekStepSeconds.toInt())),
                        onVerticalDragUpdate: (d) => _onVerticalDrag(d, false),
                        onHorizontalDragUpdate: _onHorizontalDrag,
                      ),
                    ),
                  ],
                ),
              ),

              // Centered overlay flash (volume / brightness / seek)
              if (_overlayText != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_overlayIcon != null) ...[Icon(_overlayIcon, color: Colors.white, size: 28), const SizedBox(width: 10)],
                        Text(_overlayText!, style: const TextStyle(color: Colors.white, fontSize: 18)),
                      ],
                    ),
                  ),
                ),

              // Top bar
              if (_showControls) Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

              // Bottom controls
              if (_showControls) Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar(mediaSize)),

              if (!_isReady) const Center(child: CircularProgressIndicator(color: Colors.white)),
            ],
          ),
        );
      },
    );
  }

  SubtitleViewConfiguration _subtitleConfig(SubtitleStyleSettings s) {
    if (!s.enabled) {
      return const SubtitleViewConfiguration(visible: false);
    }
    return SubtitleViewConfiguration(
      visible: true,
      style: TextStyle(
        height: 1.4,
        fontSize: s.fontSize,
        fontFamily: s.fontFamily,
        color: Color(s.textColor),
        fontWeight: s.bold ? FontWeight.bold : FontWeight.normal,
        backgroundColor: Color(s.backgroundColor),
        shadows: s.outlineWidth > 0
            ? [
                for (final dx in [-s.outlineWidth, 0.0, s.outlineWidth])
                  for (final dy in [-s.outlineWidth, 0.0, s.outlineWidth])
                    if (dx != 0 || dy != 0) Shadow(offset: Offset(dx, dy), color: Color(s.outlineColor), blurRadius: 0),
              ]
            : null,
      ),
      textAlign: TextAlign.center,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent]),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              widget.video.displayName,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.subtitles, color: Colors.white),
            tooltip: 'player.subtitle_track'.tr(),
            onPressed: _showSubtitleOptions,
          ),
          IconButton(
            icon: const Icon(Icons.audiotrack, color: Colors.white),
            tooltip: 'player.audio_track'.tr(),
            onPressed: _pickAudioTrack,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(Size size) {
    final dur = _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_formatDuration(_position), style: const TextStyle(color: Colors.white, fontSize: 12)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7), activeTrackColor: Colors.redAccent),
                  child: Slider(
                    value: _position.inMilliseconds.clamp(0, dur).toDouble(),
                    max: dur.toDouble(),
                    min: 0,
                    onChanged: (v) {
                      setState(() => _position = Duration(milliseconds: v.toInt()));
                    },
                    onChangeEnd: (v) => _player.seek(Duration(milliseconds: v.toInt())),
                  ),
                ),
              ),
              Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white, size: 32),
                onPressed: () => _seekRelative(const Duration(seconds: -10)),
              ),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 56,
                icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
                onPressed: () {
                  _playing ? _player.pause() : _player.play();
                  _startHideTimer();
                },
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white, size: 32),
                onPressed: () => _seekRelative(const Duration(seconds: 10)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAudioTrack() async {
    final tracks = _player.state.tracks.audio;
    final current = _player.state.track.audio;
    final picked = await _showTrackPicker<AudioTrack>(title: 'player.audio_track'.tr(), tracks: tracks, current: current, label: (t) => t.title ?? t.language ?? t.id);
    if (picked != null) await _player.setAudioTrack(picked);
  }

  Future<void> _pickSubtitleTrack() async {
    final tracks = _player.state.tracks.subtitle;
    final current = _player.state.track.subtitle;
    final picked = await _showTrackPicker<SubtitleTrack>(title: 'player.subtitle_track'.tr(), tracks: tracks, current: current, label: (t) => t.title ?? t.language ?? t.id);
    if (picked != null) await _player.setSubtitleTrack(picked);
  }

  /// Opens the full subtitle options bottom sheet (track selection, style
  /// settings, download link).
  Future<void> _showSubtitleOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _SubtitleOptionsSheet(player: _player, video: widget.video),
    );
  }

  Future<T?> _showTrackPicker<T>({required String title, required List<T> tracks, required T current, required String Function(T) label}) async {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...tracks.map(
              (t) => ListTile(
                leading: Icon(t == current ? Icons.radio_button_checked : Icons.radio_button_off, color: Colors.white),
                title: Text(label(t), style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(ctx).pop(t),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subtitle Options Sheet
// ---------------------------------------------------------------------------

/// Bottom sheet shown when the subtitle icon button is tapped in the player.
///
/// Sections:
///   1. Subtitle tracks (embedded in the video)
///   2. Load external subtitle file
///   3. Style settings (font size, outline, bold, font, colours)
///   4. Download subtitles from titulky.com
class _SubtitleOptionsSheet extends StatefulWidget {
  final Player player;
  final VideoItem video;

  const _SubtitleOptionsSheet({required this.player, required this.video});

  @override
  State<_SubtitleOptionsSheet> createState() => _SubtitleOptionsSheetState();
}

class _SubtitleOptionsSheetState extends State<_SubtitleOptionsSheet> {
  // Style palette reused from SettingsScreen
  static const List<int> _palette = [0xFFFFFFFF, 0xFFFFEB3B, 0xFFFF5252, 0xFF40C4FF, 0xFF69F0AE, 0xFFFFA726, 0xFFE040FB, 0xFFB0BEC5, 0xFF000000];
  static const List<int> _paletteWithTransparent = [
    0xFFFFFFFF,
    0xFFFFEB3B,
    0xFFFF5252,
    0xFF40C4FF,
    0xFF69F0AE,
    0xFFFFA726,
    0xFFE040FB,
    0xFFB0BEC5,
    0xFF000000,
    0x00000000,
    0x80000000,
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayraSettingsCubit, PlayraSettingsState>(
      builder: (context, settings) {
        final s = settings.subtitleStyle;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                ),
              ),

              // --- Embedded tracks ---
              _sectionHeader('player.subtitle_track'.tr()),
              ..._buildTrackTiles(s),

              const Divider(color: Colors.grey),

              // --- Load external file ---
              ListTile(
                leading: const Icon(Icons.folder_open, color: Colors.white),
                title: Text('player.load_subtitle_file'.tr(), style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  final res = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['srt', 'ass', 'ssa', 'vtt', 'sub'],
                    dialogTitle: 'player.load_subtitle_file'.tr(),
                  );
                  if (res != null && res.files.isNotEmpty && res.files.first.path != null) {
                    final path = res.files.first.path!;
                    await widget.player.setSubtitleTrack(SubtitleTrack.uri(Uri.file(path).toString(), title: res.files.first.name));
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
              ),

              const Divider(color: Colors.grey),

              // --- Style settings ---
              _sectionHeader('settings.section_subtitles'.tr()),
              SwitchListTile(
                tileColor: Colors.transparent,
                title: Text('settings.subtitles_enabled'.tr(), style: const TextStyle(color: Colors.white)),
                value: s.enabled,
                onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(enabled: v)),
              ),
              // Font size
              ListTile(
                title: Text('settings.subtitle_size'.tr(), style: const TextStyle(color: Colors.white)),
                subtitle: Slider(
                  min: 10,
                  max: 48,
                  divisions: 38,
                  value: s.fontSize,
                  label: s.fontSize.toStringAsFixed(0),
                  onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(fontSize: v)),
                ),
              ),
              // Outline width
              ListTile(
                title: Text('settings.subtitle_outline'.tr(), style: const TextStyle(color: Colors.white)),
                subtitle: Slider(
                  min: 0,
                  max: 5,
                  divisions: 10,
                  value: s.outlineWidth,
                  label: s.outlineWidth.toStringAsFixed(1),
                  onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(outlineWidth: v)),
                ),
              ),
              // Bold
              SwitchListTile(
                tileColor: Colors.transparent,
                title: Text('settings.subtitle_bold'.tr(), style: const TextStyle(color: Colors.white)),
                value: s.bold,
                onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(bold: v)),
              ),
              // Font family
              ListTile(
                title: Text('settings.subtitle_font'.tr(), style: const TextStyle(color: Colors.white)),
                trailing: DropdownButton<String>(
                  dropdownColor: Colors.grey[850],
                  value: s.fontFamily,
                  style: const TextStyle(color: Colors.white),
                  items: kAvailableSubtitleFonts.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(fontFamily: v));
                    }
                  },
                ),
              ),
              // Text colour
              _colourTile(context, 'settings.subtitle_text_color'.tr(), s.textColor, _palette, (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(textColor: c))),
              // Background colour
              _colourTile(
                context,
                'settings.subtitle_bg_color'.tr(),
                s.backgroundColor,
                _paletteWithTransparent,
                (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(backgroundColor: c)),
              ),
              // Outline colour
              _colourTile(
                context,
                'settings.subtitle_outline_color'.tr(),
                s.outlineColor,
                _palette,
                (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(outlineColor: c)),
              ),

              const Divider(color: Colors.grey),

              // --- Download subtitles ---
              if (widget.video.source == VideoSource.local)
                ListTile(
                  leading: const Icon(Icons.cloud_download, color: Colors.white),
                  title: Text('player.download_subtitles'.tr(), style: const TextStyle(color: Colors.white)),
                  subtitle: Text('player.download_subtitles_hint'.tr(), style: const TextStyle(color: Colors.grey)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white),
                  onTap: () {
                    Navigator.of(context).pop(); // close sheet
                    final videoInfo = VideoInfo(path: widget.video.uri, name: widget.video.name, directory: _dirOf(widget.video.uri));
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SubtitleSearchScreen(videoInfo: videoInfo)));
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildTrackTiles(SubtitleStyleSettings s) {
    final tracks = widget.player.state.tracks.subtitle;
    final current = widget.player.state.track.subtitle;
    if (tracks.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('player.no_subtitle_tracks'.tr(), style: const TextStyle(color: Colors.grey)),
        ),
      ];
    }
    return tracks.map((t) {
      final label = t.title ?? t.language ?? t.id;
      return ListTile(
        leading: Icon(t == current ? Icons.radio_button_checked : Icons.radio_button_off, color: Colors.white),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        onTap: () async {
          await widget.player.setSubtitleTrack(t);
          if (mounted) setState(() {}); // refresh the check-mark
        },
      );
    }).toList();
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[400], letterSpacing: 0.8),
      ),
    );
  }

  Widget _colourTile(BuildContext context, String title, int current, List<int> palette, ValueChanged<int> onChanged) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Color(current),
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: current == 0x00000000 ? const Icon(Icons.block, size: 16) : null,
      ),
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: palette
                  .map(
                    (c) => GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c),
                          border: Border.all(color: c == current ? Colors.blue : Colors.grey, width: c == current ? 3 : 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: c == 0x00000000 ? const Icon(Icons.block, size: 20) : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }

  String _dirOf(String path) {
    final slash = path.lastIndexOf(Platform.pathSeparator);
    return slash > 0 ? path.substring(0, slash) : '';
  }
}
