import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../bloc/subtitle_editor/subtitle_editor_bloc.dart';
import '../bloc/subtitle_editor/subtitle_editor_event.dart';
import '../bloc/subtitle_editor/subtitle_editor_state.dart';
import '../models/subtitle_entry.dart';

/// Subtitle editor screen with video player, global shift controls,
/// and key-based subtitle synchronization.
///
/// Pops with the path of the last saved file, or null when nothing was saved.
class SubtitleEditorScreen extends StatefulWidget {
  final String videoPath;
  final String subtitlePath;

  const SubtitleEditorScreen({super.key, required this.videoPath, required this.subtitlePath});

  @override
  State<SubtitleEditorScreen> createState() => _SubtitleEditorScreenState();
}

class _SubtitleEditorScreenState extends State<SubtitleEditorScreen> with SingleTickerProviderStateMixin {
  static const _verifyLeadIn = Duration(seconds: 2);

  Player? _player;
  VideoController? _videoController;
  bool _isVideoLoading = true;
  String? _videoError;
  late TabController _tabController;

  /// Where the video was when the user started placing the selected subtitle.
  Duration _pickAnchor = Duration.zero;

  String? _savedPath;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final fileExists = await File(widget.videoPath).exists();
      if (!fileExists) {
        setState(() {
          _isVideoLoading = false;
          _videoError = 'editor.video_not_found'.tr();
        });
        return;
      }

      _player = Player();
      _videoController = VideoController(_player!);

      _player!.stream.error.listen((error) {
        debugPrint('🔴 SubtitleEditor: Player error: $error');
      });

      final mediaUri = widget.videoPath.startsWith('file://') ? widget.videoPath : 'file://${widget.videoPath}';
      await _player!.open(Media(mediaUri), play: false);

      // The editor draws the edited timings itself; mpv would otherwise auto-load a sibling .srt.
      await _player!.setSubtitleTrack(SubtitleTrack.no());

      // Wait for video to load
      int attempts = 0;
      while (_player!.state.duration == Duration.zero && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      await _player!.play();

      if (!mounted) return;
      setState(() {
        _isVideoLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVideoLoading = false;
        _videoError = 'editor.video_load_error'.tr();
      });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Duration get _position => _player?.state.position ?? Duration.zero;

  void _seek(Duration position) {
    _player?.seek(position < Duration.zero ? Duration.zero : position);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<String>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_savedPath);
      },
      child: BlocProvider(
        create: (_) => SubtitleEditorBloc()..add(LoadSubtitleFile(subtitlePath: widget.subtitlePath, videoPath: widget.videoPath)),
        child: _buildEditor(),
      ),
    );
  }

  Widget _buildEditor() {
    return BlocConsumer<SubtitleEditorBloc, SubtitleEditorState>(
      listener: (context, state) {
        if (state is SubtitleEditorSaved) {
          _savedPath = state.savedPath;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('editor.saved_success'.tr(args: [state.savedPath])),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is SubtitleEditorError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: Colors.red));
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Text('editor.title'.tr()),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              if (state is SubtitleEditorLoaded)
                IconButton(icon: const Icon(Icons.save), tooltip: 'editor.save'.tr(), onPressed: () => _showSaveDialog(context, state)),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: [
                Tab(icon: const Icon(Icons.timer), text: 'editor.global_shift'.tr()),
                Tab(icon: const Icon(Icons.tune), text: 'editor.key_sync'.tr()),
              ],
            ),
          ),
          body: Column(
            children: [
              _buildVideoSection(context, state),
              Expanded(
                child: TabBarView(controller: _tabController, children: [_buildGlobalShiftTab(context, state), _buildKeySyncTab(context, state)]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoSection(BuildContext context, SubtitleEditorState state) {
    final height = (MediaQuery.sizeOf(context).height * 0.32).clamp(180.0, 320.0);
    return Container(
      height: height,
      color: Colors.black,
      child: _isVideoLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _videoError != null
          ? Center(
              child: Text(_videoError!, style: const TextStyle(color: Colors.red)),
            )
          : Stack(
              children: [
                if (_videoController != null)
                  Center(
                    child: Video(
                      controller: _videoController!,
                      controls: NoVideoControls,
                      subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                    ),
                  ),
                if (state is SubtitleEditorLoaded) Positioned(bottom: 64, left: 16, right: 16, child: _buildSubtitleOverlay(state)),
                Positioned(bottom: 0, left: 0, right: 0, child: _buildCompactControls()),
              ],
            ),
    );
  }

  Widget _buildSubtitleOverlay(SubtitleEditorLoaded state) {
    if (state.isPickingKey) {
      final target = state.originalEntry(state.selectedEntryIndex);
      if (target == null) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'editor.target_subtitle'.tr(),
              style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
            ),
            Text(
              target.text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<Duration>(
      stream: _player?.stream.position,
      initialData: _position,
      builder: (context, snapshot) {
        final active = state.activeAt(snapshot.data ?? Duration.zero);
        if (active.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
          child: Text(
            active.map((e) => e.text).join('\n'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }

  Widget _buildCompactControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent]),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration>(
            stream: _player?.stream.position,
            initialData: Duration.zero,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final duration = _player?.state.duration ?? Duration.zero;
              return Row(
                children: [
                  Text(_formatClock(position), style: const TextStyle(color: Colors.white, fontSize: 11)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: duration.inMilliseconds > 0 ? position.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble()) : 0,
                        max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white38,
                        onChanged: (value) => _seek(Duration(milliseconds: value.toInt())),
                      ),
                    ),
                  ),
                  Text(_formatClock(duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_5, color: Colors.white),
                iconSize: 24,
                onPressed: () => _seek(_position - const Duration(seconds: 5)),
              ),
              _buildPlayPauseButton(color: Colors.white, size: 32),
              IconButton(
                icon: const Icon(Icons.forward_5, color: Colors.white),
                iconSize: 24,
                onPressed: () => _seek(_position + const Duration(seconds: 5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton({Color? color, double size = 24}) {
    return StreamBuilder<bool>(
      stream: _player?.stream.playing,
      initialData: _player?.state.playing ?? false,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;
        return IconButton(
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: color),
          iconSize: size,
          onPressed: () => isPlaying ? _player?.pause() : _player?.play(),
        );
      },
    );
  }

  // ──────────────────────────────────────────
  // TAB 1: Global Shift
  // ──────────────────────────────────────────

  Widget _buildGlobalShiftTab(BuildContext context, SubtitleEditorState state) {
    if (state is! SubtitleEditorLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final shiftMs = state.globalShift.inMilliseconds;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('editor.current_shift'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    _formatShift(context, state.globalShift),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: _shiftColor(shiftMs), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          if (state.keyPoints.isNotEmpty) ...[const SizedBox(height: 8), _buildHint(context, 'editor.global_shift_with_keys'.tr())],
          const SizedBox(height: 16),

          Text('editor.shift_earlier'.tr(), style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildShiftButton(context, const Duration(seconds: -1), Colors.red.shade700),
              const SizedBox(width: 8),
              _buildShiftButton(context, const Duration(milliseconds: -500), Colors.red.shade400),
              const SizedBox(width: 8),
              _buildShiftButton(context, const Duration(milliseconds: -100), Colors.red.shade300),
            ],
          ),
          const SizedBox(height: 16),

          Text('editor.shift_later'.tr(), style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildShiftButton(context, const Duration(milliseconds: 100), Colors.green.shade300),
              const SizedBox(width: 8),
              _buildShiftButton(context, const Duration(milliseconds: 500), Colors.green.shade400),
              const SizedBox(width: 8),
              _buildShiftButton(context, const Duration(seconds: 1), Colors.green.shade700),
            ],
          ),
          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed: () => context.read<SubtitleEditorBloc>().add(ResetGlobalShift()),
            icon: const Icon(Icons.restart_alt),
            label: Text('editor.reset_shift'.tr()),
          ),
          const SizedBox(height: 24),

          Text('editor.preview'.tr(), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...state.modifiedEntries.take(5).map((entry) => _buildSubtitlePreviewTile(entry, state)),
          if (state.modifiedEntries.length > 5)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'editor.and_more'.tr(args: ['${state.modifiedEntries.length - 5}']),
                style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShiftButton(BuildContext context, Duration offset, Color color) {
    return Expanded(
      child: ElevatedButton(
        onPressed: () => context.read<SubtitleEditorBloc>().add(ApplyGlobalShift(offset)),
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
        child: Text(_formatShift(context, offset, decimals: 1), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSubtitlePreviewTile(SubtitleEntry entry, SubtitleEditorLoaded state) {
    final shifted = state.totalShiftOf(entry.index) != Duration.zero;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: shifted ? Colors.orange.shade100 : Colors.grey.shade200,
          child: Text('${entry.index}', style: TextStyle(fontSize: 10, color: shifted ? Colors.orange.shade800 : Colors.grey.shade700)),
        ),
        title: Text(entry.text.replaceAll('\n', ' '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          '${_formatTime(context, entry.startTime)} → ${_formatTime(context, entry.endTime)}',
          style: TextStyle(fontSize: 11, color: shifted ? Colors.orange : Colors.grey),
        ),
        onTap: () => _seek(entry.startTime),
      ),
    );
  }

  // ──────────────────────────────────────────
  // TAB 2: Key-Based Sync
  // ──────────────────────────────────────────

  Widget _buildKeySyncTab(BuildContext context, SubtitleEditorState state) {
    if (state is! SubtitleEditorLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.isPickingKey) {
      return _buildKeyPickPanel(context, state);
    }

    return Column(
      children: [
        _buildKeySyncHeader(context, state),
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey('key-sync-list'),
            itemCount: state.originalEntries.length,
            itemBuilder: (context, index) => _buildKeySyncSubtitleCard(context, state.originalEntries[index], state),
          ),
        ),
      ],
    );
  }

  Widget _buildKeySyncHeader(BuildContext context, SubtitleEditorLoaded state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(bottom: BorderSide(color: Colors.blue.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text('editor.key_sync_steps'.tr(), style: TextStyle(fontSize: 12, color: Colors.blue.shade900)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Chip(
                avatar: const Icon(Icons.vpn_key, size: 16),
                label: Text('editor.key_points_count'.tr(args: ['${state.keyPoints.length}'])),
                backgroundColor: state.keyPoints.isNotEmpty ? Colors.amber.shade100 : Colors.grey.shade200,
              ),
              const Spacer(),
              if (state.keyPoints.isNotEmpty)
                TextButton.icon(
                  onPressed: () => context.read<SubtitleEditorBloc>().add(ClearKeyPoints()),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text('editor.clear_keys'.tr()),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeySyncSubtitleCard(BuildContext context, SubtitleEntry entry, SubtitleEditorLoaded state) {
    final isKey = state.keyPoints.containsKey(entry.index);
    final current = state.modifiedEntry(entry.index) ?? entry;
    final shift = current.startTime - entry.startTime;

    return Card(
      key: ValueKey(entry.index),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: isKey ? Colors.amber.shade50 : null,
      child: InkWell(
        onTap: () => _startPicking(context, entry.index, current.startTime),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(shape: BoxShape.circle, color: isKey ? Colors.amber : Colors.grey.shade300),
                child: Center(
                  child: isKey
                      ? const Icon(Icons.vpn_key, size: 16, color: Colors.white)
                      : Text(
                          '${entry.index}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.text.replaceAll('\n', ' '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      shift == Duration.zero
                          ? _formatTime(context, current.startTime)
                          : '${_formatTime(context, current.startTime)}  ·  ${'editor.original_time'.tr(args: [_formatTime(context, entry.startTime)])}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (isKey)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text(_formatShift(context, shift), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                )
              else
                Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  void _startPicking(BuildContext context, int srtIndex, Duration currentStart) {
    context.read<SubtitleEditorBloc>().add(SelectSubtitleEntry(entryIndex: srtIndex));
    _pickAnchor = currentStart;
    _player?.pause();
    _seek(currentStart);
  }

  Widget _buildKeyPickPanel(BuildContext context, SubtitleEditorLoaded state) {
    final srtIndex = state.selectedEntryIndex;
    final original = state.originalEntry(srtIndex)!;
    final isKey = state.keyPoints.containsKey(srtIndex);
    final bloc = context.read<SubtitleEditorBloc>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.gps_fixed, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text('editor.pick_title'.tr(args: ['$srtIndex']), style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton(onPressed: () => bloc.add(ClearSubtitleSelection()), child: Text('common.cancel'.tr())),
            ],
          ),
          Text(
            '„${original.text.replaceAll('\n', ' ')}“',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildHint(context, 'editor.pick_steps'.tr()),
          const SizedBox(height: 12),
          StreamBuilder<Duration>(
            stream: _player?.stream.position,
            initialData: _position,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final shift = position - original.startTime;
              return Card(
                elevation: 0,
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text('editor.pick_starts_at'.tr(), style: Theme.of(context).textTheme.labelMedium),
                      Text(
                        _formatTime(context, position),
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'editor.pick_shift'.tr(args: [_formatShift(context, shift)]),
                        style: TextStyle(fontWeight: FontWeight.bold, color: _shiftColor(shift.inMilliseconds)),
                      ),
                      Text(
                        'editor.pick_original'.tr(args: [_formatTime(context, original.startTime)]),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNudgeButton(context, const Duration(seconds: -1)),
              _buildNudgeButton(context, const Duration(milliseconds: -100)),
              _buildPlayPauseButton(size: 36),
              _buildNudgeButton(context, const Duration(milliseconds: 100)),
              _buildNudgeButton(context, const Duration(seconds: 1)),
            ],
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => _seek(_pickAnchor),
            icon: const Icon(Icons.replay),
            label: Text('editor.back_to_start'.tr(args: [_formatTime(context, _pickAnchor)])),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _saveKeyHere(context, original),
            icon: const Icon(Icons.vpn_key),
            label: Text('editor.save_key_here'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          if (isKey) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => bloc
                ..add(RemoveKeyPoint(entryIndex: srtIndex))
                ..add(ClearSubtitleSelection()),
              icon: const Icon(Icons.delete_outline),
              label: Text('editor.remove_key'.tr()),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNudgeButton(BuildContext context, Duration delta) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: OutlinedButton(
        onPressed: () => _seek(_position + delta),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(56, 40)),
        child: Text(_formatShift(context, delta, decimals: 1), style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  void _saveKeyHere(BuildContext context, SubtitleEntry original) {
    final position = _position;
    _player?.pause();
    context.read<SubtitleEditorBloc>().add(SetKeyPoint(entryIndex: original.index, startTime: position));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('editor.key_saved'.tr(args: ['${original.index}', _formatTime(context, position), _formatShift(context, position - original.startTime)])),
        backgroundColor: Colors.green.shade700,
      ),
    );

    _seek(position - _verifyLeadIn);
    _player?.play();
  }

  Widget _buildHint(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: Colors.blue.shade900)),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  // Save Dialog
  // ──────────────────────────────────────────

  void _showSaveDialog(BuildContext context, SubtitleEditorLoaded state) {
    final bloc = context.read<SubtitleEditorBloc>();
    final originalName = widget.subtitlePath.split('/').last;
    final directory = widget.subtitlePath.substring(0, widget.subtitlePath.lastIndexOf('/'));

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('editor.save_dialog_title'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('editor.save_dialog_message'.tr()),
              const SizedBox(height: 16),
              Text('editor.original_file'.tr(args: [originalName]), style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('common.cancel'.tr())),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                final newName = originalName.replaceAll('.srt', '_synced.srt');
                bloc.add(SaveSubtitles(targetPath: '$directory/$newName'));
              },
              icon: const Icon(Icons.file_copy),
              label: Text('editor.save_as_new'.tr()),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                bloc.add(SaveSubtitles());
              },
              icon: const Icon(Icons.save),
              label: Text('editor.overwrite'.tr()),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            ),
          ],
        );
      },
    );
  }

  // ──────────────────────────────────────────
  // Formatting
  // ──────────────────────────────────────────

  Color _shiftColor(int shiftMs) => shiftMs == 0 ? Colors.grey : (shiftMs > 0 ? Colors.green : Colors.red);

  String _localizeDecimal(BuildContext context, String value) => context.locale.languageCode == 'cs' ? value.replaceAll('.', ',') : value;

  String _formatShift(BuildContext context, Duration shift, {int decimals = 2}) {
    final seconds = shift.inMilliseconds / 1000;
    final sign = shift.inMilliseconds > 0 ? '+' : (shift.inMilliseconds < 0 ? '−' : '');
    return _localizeDecimal(context, '$sign${seconds.abs().toStringAsFixed(decimals)} s');
  }

  String _formatTime(BuildContext context, Duration time) {
    final centis = (time.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return _localizeDecimal(context, '${_formatClock(time)}.$centis');
  }

  String _formatClock(Duration duration) {
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
