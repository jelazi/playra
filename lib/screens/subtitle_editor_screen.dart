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
import '../services/srt_parser_service.dart';

/// Subtitle editor screen with video player, global shift controls,
/// and key-based subtitle synchronization.
class SubtitleEditorScreen extends StatefulWidget {
  final String videoPath;
  final String subtitlePath;

  const SubtitleEditorScreen({super.key, required this.videoPath, required this.subtitlePath});

  @override
  State<SubtitleEditorScreen> createState() => _SubtitleEditorScreenState();
}

class _SubtitleEditorScreenState extends State<SubtitleEditorScreen> with SingleTickerProviderStateMixin {
  Player? _player;
  VideoController? _videoController;
  bool _isVideoLoading = true;
  String? _videoError;
  late TabController _tabController;
  String? _tempSubtitlePath;

  // Current subtitle text displayed on top of the video
  String _currentSubtitleText = '';

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
        print('🔴 SubtitleEditor: Player error: $error');
      });

      final mediaUri = widget.videoPath.startsWith('file://') ? widget.videoPath : 'file://${widget.videoPath}';
      await _player!.open(Media(mediaUri));

      // Load subtitle track
      final subtitleUri = widget.subtitlePath.startsWith('file://') ? widget.subtitlePath : 'file://${widget.subtitlePath}';
      await _player!.setSubtitleTrack(SubtitleTrack.uri(subtitleUri));

      // Wait for video to load
      int attempts = 0;
      while (_player!.state.duration == Duration.zero && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      await _player!.play();

      // Listen to subtitle text updates
      _player!.stream.subtitle.listen((subtitleLines) {
        if (mounted) {
          setState(() {
            _currentSubtitleText = subtitleLines.join('\n');
          });
        }
      });

      setState(() {
        _isVideoLoading = false;
      });
    } catch (e) {
      setState(() {
        _isVideoLoading = false;
        _videoError = 'editor.video_load_error'.tr();
      });
    }
  }

  Future<void> _reloadSubtitleTrack(List<SubtitleEntry> entries) async {
    if (_player == null) return;

    try {
      // Write modified subtitles to a temp file
      final tempPath = '${widget.subtitlePath}.editor_temp.srt';
      await SrtParserService.writeFile(tempPath, entries);
      _tempSubtitlePath = tempPath;

      // Reload subtitle track
      await _player!.setSubtitleTrack(SubtitleTrack.no());
      await Future.delayed(const Duration(milliseconds: 50));
      final subtitleUri = tempPath.startsWith('file://') ? tempPath : 'file://$tempPath';
      await _player!.setSubtitleTrack(SubtitleTrack.uri(subtitleUri));
    } catch (e) {
      print('🔴 SubtitleEditor: Error reloading subtitles: $e');
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _tabController.dispose();
    // Clean up temp file
    if (_tempSubtitlePath != null) {
      File(_tempSubtitlePath!).delete().catchError((_) => File(_tempSubtitlePath!));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SubtitleEditorBloc()..add(LoadSubtitleFile(subtitlePath: widget.subtitlePath, videoPath: widget.videoPath)),
      child: BlocConsumer<SubtitleEditorBloc, SubtitleEditorState>(
        listener: (context, state) {
          if (state is SubtitleEditorLoaded) {
            // Reload subtitle in player when modified entries change
            _reloadSubtitleTrack(state.modifiedEntries);
          } else if (state is SubtitleEditorSaved) {
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
              actions: [if (state is SubtitleEditorLoaded) IconButton(icon: const Icon(Icons.save), tooltip: 'editor.save'.tr(), onPressed: () => _showSaveDialog(context, state))],
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
                // Video player section
                _buildVideoSection(state),
                // Tab content
                Expanded(
                  child: TabBarView(controller: _tabController, children: [_buildGlobalShiftTab(context, state), _buildKeySyncTab(context, state)]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoSection(SubtitleEditorState state) {
    return Container(
      height: 280,
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
                    child: Video(controller: _videoController!, controls: NoVideoControls),
                  ),
                // Subtitle overlay
                Positioned(
                  bottom: 50,
                  left: 16,
                  right: 16,
                  child: _currentSubtitleText.isNotEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            _currentSubtitleText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // Playback controls overlay
                Positioned(bottom: 0, left: 0, right: 0, child: _buildCompactControls()),
              ],
            ),
    );
  }

  Widget _buildCompactControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent]),
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
              final duration = _player?.state.duration ?? Duration.zero;
              return Row(
                children: [
                  Text(_formatDuration(position), style: const TextStyle(color: Colors.white, fontSize: 11)),
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
                        onChanged: (value) {
                          _player?.seek(Duration(milliseconds: value.toInt()));
                        },
                      ),
                    ),
                  ),
                  Text(_formatDuration(duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              );
            },
          ),
          // Playback buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_5, color: Colors.white),
                iconSize: 24,
                onPressed: () {
                  final pos = _player?.state.position ?? Duration.zero;
                  _player?.seek(pos - const Duration(seconds: 5));
                },
              ),
              StreamBuilder<bool>(
                stream: _player?.stream.playing,
                initialData: _player?.state.playing ?? false,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data ?? false;
                  return IconButton(
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                    iconSize: 32,
                    onPressed: () {
                      if (isPlaying) {
                        _player?.pause();
                      } else {
                        _player?.play();
                      }
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.forward_5, color: Colors.white),
                iconSize: 24,
                onPressed: () {
                  final pos = _player?.state.position ?? Duration.zero;
                  _player?.seek(pos + const Duration(seconds: 5));
                },
              ),
            ],
          ),
        ],
      ),
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
    final shiftSign = shiftMs >= 0 ? '+' : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current shift info
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('editor.current_shift'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '$shiftSign${shiftMs}ms (${(shiftMs / 1000).toStringAsFixed(1)}s)',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(color: shiftMs == 0 ? Colors.grey : (shiftMs > 0 ? Colors.green : Colors.red), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Shift buttons
          Text('editor.shift_earlier'.tr(), style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildShiftButton(context, '-1s', const Duration(seconds: -1), Colors.red.shade700),
              const SizedBox(width: 8),
              _buildShiftButton(context, '-500ms', const Duration(milliseconds: -500), Colors.red.shade400),
              const SizedBox(width: 8),
              _buildShiftButton(context, '-100ms', const Duration(milliseconds: -100), Colors.red.shade300),
            ],
          ),
          const SizedBox(height: 16),

          Text('editor.shift_later'.tr(), style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildShiftButton(context, '+100ms', const Duration(milliseconds: 100), Colors.green.shade300),
              const SizedBox(width: 8),
              _buildShiftButton(context, '+500ms', const Duration(milliseconds: 500), Colors.green.shade400),
              const SizedBox(width: 8),
              _buildShiftButton(context, '+1s', const Duration(seconds: 1), Colors.green.shade700),
            ],
          ),
          const SizedBox(height: 16),

          // Reset button
          OutlinedButton.icon(
            onPressed: () {
              context.read<SubtitleEditorBloc>().add(ResetGlobalShift());
            },
            icon: const Icon(Icons.restart_alt),
            label: Text('editor.reset_shift'.tr()),
          ),
          const SizedBox(height: 24),

          // Preview of first few subtitles
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

  Widget _buildShiftButton(BuildContext context, String label, Duration offset, Color color) {
    return Expanded(
      child: ElevatedButton(
        onPressed: () {
          context.read<SubtitleEditorBloc>().add(ApplyGlobalShift(offset));
        },
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSubtitlePreviewTile(SubtitleEntry entry, SubtitleEditorLoaded state) {
    // Find original entry for comparison
    final original = state.originalEntries.firstWhere((e) => e.index == entry.index, orElse: () => entry);
    final shifted = entry.startTime != original.startTime;

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
          '${SrtParserService.formatDuration(entry.startTime)} → ${SrtParserService.formatDuration(entry.endTime)}',
          style: TextStyle(fontSize: 11, color: shifted ? Colors.orange : Colors.grey),
        ),
        onTap: () {
          _player?.seek(entry.startTime);
        },
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

    return Column(
      children: [
        // Key point info & controls
        _buildKeySyncHeader(context, state),
        // Subtitle list
        Expanded(
          child: ListView.builder(
            itemCount: state.originalEntries.length,
            itemBuilder: (context, index) {
              final entry = state.originalEntries[index];
              return _buildKeySyncSubtitleCard(context, entry, state);
            },
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
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text('editor.key_sync_info'.tr(), style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
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
                ElevatedButton.icon(
                  onPressed: () {
                    context.read<SubtitleEditorBloc>().add(RecalculateFromKeyPoints());
                  },
                  icon: const Icon(Icons.calculate, size: 18),
                  label: Text('editor.recalculate'.tr()),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                ),
            ],
          ),
          if (state.keyRecalculated)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text('editor.recalculated_success'.tr(), style: const TextStyle(color: Colors.green, fontSize: 12)),
                ],
              ),
            ),
          // Selected subtitle adjustment controls
          if (state.selectedEntryIndex >= 0) ...[const Divider(), _buildSelectedSubtitleControls(context, state)],
        ],
      ),
    );
  }

  Widget _buildSelectedSubtitleControls(BuildContext context, SubtitleEditorLoaded state) {
    final srtIndex = state.selectedEntryIndex;
    final entry = state.originalEntries.firstWhere((e) => e.index == srtIndex, orElse: () => state.originalEntries.first);
    final currentOffset = state.individualOffsets[srtIndex] ?? Duration.zero;
    final offsetMs = currentOffset.inMilliseconds;
    final sign = offsetMs >= 0 ? '+' : '';
    final isKey = state.keyPoints.containsKey(srtIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'editor.adjusting_subtitle'.tr(args: ['$srtIndex']),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        Text(
          entry.text.replaceAll('\n', ' '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 4),
        Text(
          'editor.individual_offset'.tr(args: ['$sign${offsetMs}ms']),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: offsetMs == 0 ? Colors.grey : (offsetMs > 0 ? Colors.green : Colors.red)),
        ),
        const SizedBox(height: 8),
        // Adjustment buttons
        Row(
          children: [
            _buildKeyAdjustButton(context, '-1s', const Duration(seconds: -1), Colors.red.shade700),
            const SizedBox(width: 4),
            _buildKeyAdjustButton(context, '-500', const Duration(milliseconds: -500), Colors.red.shade400),
            const SizedBox(width: 4),
            _buildKeyAdjustButton(context, '-100', const Duration(milliseconds: -100), Colors.red.shade300),
            const SizedBox(width: 4),
            _buildKeyAdjustButton(context, '+100', const Duration(milliseconds: 100), Colors.green.shade300),
            const SizedBox(width: 4),
            _buildKeyAdjustButton(context, '+500', const Duration(milliseconds: 500), Colors.green.shade400),
            const SizedBox(width: 4),
            _buildKeyAdjustButton(context, '+1s', const Duration(seconds: 1), Colors.green.shade700),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  context.read<SubtitleEditorBloc>().add(MarkAsKeyPoint(entryIndex: srtIndex, offset: currentOffset));
                },
                icon: Icon(isKey ? Icons.vpn_key : Icons.vpn_key_outlined, size: 16),
                label: Text(isKey ? 'editor.update_key'.tr() : 'editor.save_as_key'.tr()),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black87),
              ),
            ),
            if (isKey) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  context.read<SubtitleEditorBloc>().add(RemoveKeyPoint(entryIndex: srtIndex));
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'editor.remove_key'.tr(),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildKeyAdjustButton(BuildContext context, String label, Duration delta, Color color) {
    return Expanded(
      child: SizedBox(
        height: 36,
        child: ElevatedButton(
          onPressed: () {
            context.read<SubtitleEditorBloc>().add(AdjustSelectedKeyOffset(delta));
            // Also seek video to show the adjusted position
            final state = context.read<SubtitleEditorBloc>().state;
            if (state is SubtitleEditorLoaded && state.selectedEntryIndex >= 0) {
              final entry = state.originalEntries.firstWhere((e) => e.index == state.selectedEntryIndex, orElse: () => state.originalEntries.first);
              final newOffset = (state.individualOffsets[state.selectedEntryIndex] ?? Duration.zero) + delta;
              _player?.seek(entry.startTime + newOffset);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: EdgeInsets.zero),
          child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildKeySyncSubtitleCard(BuildContext context, SubtitleEntry entry, SubtitleEditorLoaded state) {
    final isSelected = state.selectedEntryIndex == entry.index;
    final isKey = state.keyPoints.containsKey(entry.index);
    final keyOffset = state.keyPoints[entry.index];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: isSelected
          ? Colors.blue.shade50
          : isKey
          ? Colors.amber.shade50
          : null,
      elevation: isSelected ? 3 : 1,
      child: InkWell(
        onTap: () {
          // Select this subtitle and seek video to its start time
          context.read<SubtitleEditorBloc>().add(SelectSubtitleEntry(entryIndex: entry.index));
          // Seek taking into account any individual offset
          final offset = state.individualOffsets[entry.index] ?? Duration.zero;
          _player?.seek(entry.startTime + offset);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Index badge
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isKey
                      ? Colors.amber
                      : isSelected
                      ? Colors.blue
                      : Colors.grey.shade300,
                ),
                child: Center(
                  child: isKey
                      ? const Icon(Icons.vpn_key, size: 16, color: Colors.white)
                      : Text(
                          '${entry.index}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade700),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Entry info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.text.replaceAll('\n', ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${SrtParserService.formatDuration(entry.startTime)} → ${SrtParserService.formatDuration(entry.endTime)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              // Key offset info
              if (isKey && keyOffset != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text('${keyOffset.inMilliseconds >= 0 ? '+' : ''}${keyOffset.inMilliseconds}ms', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
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
                // Save as new file
                final newName = originalName.replaceAll('.srt', '_synced.srt');
                bloc.add(SaveSubtitles(targetPath: '$directory/$newName'));
              },
              icon: const Icon(Icons.file_copy),
              label: Text('editor.save_as_new'.tr()),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                // Overwrite original
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
