import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';

import '../../../bloc/settings/playra_settings_cubit.dart';
import '../../../models/video_info.dart';
import '../../../models/video_item.dart';
import '../../../services/playra_storage.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/subtitle_style_controls.dart';
import '../../subtitle_search_screen.dart';
import '../track_keys.dart';

/// Bottom sheet with the subtitle track list and the appearance controls.
///
/// The appearance rows are [SubtitleStyleControls], the same widget the
/// settings page uses; only the [Theme] wrapped around them differs, which is
/// what makes this overlay dark without a second copy of the controls.
class SubtitleOptionsSheet extends StatefulWidget {
  const SubtitleOptionsSheet({
    super.key,
    required this.player,
    required this.video,
    required this.onOpenSubtitleDelayPopup,
  });

  final Player player;
  final VideoItem video;
  final Future<void> Function() onOpenSubtitleDelayPopup;

  @override
  State<SubtitleOptionsSheet> createState() => _SubtitleOptionsSheetState();
}

class _SubtitleOptionsSheetState extends State<SubtitleOptionsSheet> {
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    // Built from scratch rather than copyWith, so the typography is the dark
    // one too — a copied light theme keeps dark-on-light text colours.
    final overlayTheme = ThemeData(
      useMaterial3: base.useMaterial3,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: base.colorScheme.primary, brightness: Brightness.dark),
      dividerColor: Colors.grey,
      listTileTheme: const ListTileThemeData(tileColor: Colors.transparent),
    );

    return Theme(
      data: overlayTheme,
      child: BlocBuilder<PlayraSettingsCubit, PlayraSettingsState>(
        builder: (context, settings) {
          final style = settings.subtitleStyle;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (ctx, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const _DragHandle(),

                SectionHeader('player.subtitle_track'.tr(), dense: true),
                ..._buildTrackTiles(),

                const Divider(),

                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text('player.load_subtitle_file'.tr()),
                  onTap: _pickSubtitleFile,
                ),

                const Divider(),

                SectionHeader('settings.section_subtitles'.tr(), dense: true),
                SubtitleStyleControls(
                  style: style,
                  showBottomPadding: true,
                  onChanged: (updated) => context.read<PlayraSettingsCubit>().updateStyle(updated),
                  leading: [
                    ListTile(
                      title: Text('settings.subtitle_delay'.tr()),
                      subtitle: Text('settings.subtitle_delay_popup_hint'.tr()),
                      trailing: const Icon(Icons.tune),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await Future<void>.delayed(const Duration(milliseconds: 120));
                        await widget.onOpenSubtitleDelayPopup();
                      },
                    ),
                  ],
                  trailing: [
                    if (widget.video.source == VideoSource.local) ...[
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.cloud_download),
                        title: Text('player.download_subtitles'.tr()),
                        subtitle: Text('player.download_subtitles_hint'.tr()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openSubtitleSearch,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildTrackTiles() {
    final tracks = widget.player.state.tracks.subtitle;
    final current = widget.player.state.track.subtitle;

    if (tracks.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('player.no_subtitle_tracks'.tr(), style: Theme.of(context).textTheme.bodyMedium),
        ),
      ];
    }

    return tracks.map((t) {
      return ListTile(
        leading: Icon(t == current ? Icons.radio_button_checked : Icons.radio_button_off),
        title: Text(t.title ?? t.language ?? t.id),
        onTap: () => _selectTrack(t),
      );
    }).toList();
  }

  Future<void> _selectTrack(SubtitleTrack track) async {
    if (!await _applyTrack(track)) return;
    if (mounted) setState(() {});
  }

  Future<void> _pickSubtitleFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'ssa', 'vtt', 'sub'],
      dialogTitle: 'player.load_subtitle_file'.tr(),
    );
    final path = res?.files.firstOrNull?.path;
    if (path == null) return;

    final track = SubtitleTrack.uri(Uri.file(path).toString(), title: res!.files.first.name);
    if (!await _applyTrack(track)) return;
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _applyTrack(SubtitleTrack track) async {
    try {
      await widget.player.setSubtitleTrack(track);
    } catch (e, st) {
      debugPrint('Playra subtitle track set failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Playback error: $e')));
      }
      return false;
    }
    await PlayraStorage.savePreferredSubtitleTrackKey(widget.video.id, stableSubtitleTrackKey(track));
    return true;
  }

  Future<void> _openSubtitleSearch() async {
    // Pause playback before leaving the player to open subtitle search.
    try {
      await widget.player.pause();
    } catch (e, st) {
      debugPrint('Playra pause before subtitle search failed: $e\n$st');
    }
    if (!mounted) return;

    final navigator = Navigator.of(context);
    navigator.pop();
    final videoInfo = VideoInfo(
      path: widget.video.uri,
      name: widget.video.name,
      directory: _dirOf(widget.video.uri),
    );
    navigator.push(MaterialPageRoute(builder: (_) => SubtitleSearchScreen(videoInfo: videoInfo)));
  }

  String _dirOf(String path) {
    final slash = path.lastIndexOf(Platform.pathSeparator);
    return slash > 0 ? path.substring(0, slash) : '';
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        width: 40,
        height: 4,
        decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}
