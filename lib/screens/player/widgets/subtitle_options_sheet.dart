import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../../../bloc/settings/playra_settings_cubit.dart';
import '../../../models/video_info.dart';
import '../../../models/video_item.dart';
import '../../../services/playra_storage.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/subtitle_style_controls.dart';
import '../../subtitle_search_screen.dart';
import '../secondary_subtitles.dart';
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
    required this.onOpenSubtitleEditor,
    required this.secondarySubtitles,
    required this.siblingSubtitleFiles,
  });

  final Player player;
  final VideoItem video;
  final Future<void> Function() onOpenSubtitleDelayPopup;
  final Future<void> Function() onOpenSubtitleEditor;
  final SecondarySubtitles secondarySubtitles;

  /// Subtitle files next to the video (file or proxy URIs), offered as secondary tracks.
  final Future<List<String>> Function() siblingSubtitleFiles;

  @override
  State<SubtitleOptionsSheet> createState() => _SubtitleOptionsSheetState();
}

class _SubtitleOptionsSheetState extends State<SubtitleOptionsSheet> {
  late final Future<List<String>> _siblingFiles = widget.siblingSubtitleFiles();

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

                ListTile(leading: const Icon(Icons.folder_open), title: Text('player.load_subtitle_file'.tr()), onTap: _pickSubtitleFile),

                const Divider(),

                SectionHeader('player.secondary_subtitles'.tr(), dense: true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('player.secondary_subtitles_hint'.tr(), style: Theme.of(context).textTheme.bodySmall),
                ),
                ..._buildSecondaryTiles(),

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
                        leading: const Icon(Icons.edit_note),
                        title: Text('player.edit_subtitles'.tr()),
                        subtitle: Text('player.edit_subtitles_hint'.tr()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await widget.onOpenSubtitleEditor();
                        },
                      ),
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

  /// Picking the current secondary track as the main one swaps the two,
  /// since mpv cannot show one track in both roles.
  Future<void> _selectTrack(SubtitleTrack track) async {
    final secondary = widget.secondarySubtitles;
    final swapped = secondary.selected.value?.id == track.id;
    final previousMain = swapped ? await secondary.mainTrack() : null;
    if (swapped) await secondary.off();
    if (!await _applyTrack(track)) return;
    if (previousMain != null) {
      await secondary.select(previousMain);
      await PlayraStorage.saveSecondarySubtitleKey(widget.video.id, stableSubtitleTrackKey(previousMain));
    } else if (swapped) {
      await PlayraStorage.saveSecondarySubtitleKey(widget.video.id, PlayraStorage.secondarySubtitleOff);
    }
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

  List<Widget> _buildSecondaryTiles() {
    final selected = widget.secondarySubtitles.selected.value;
    final primary = widget.player.state.track.subtitle;
    final tracks = widget.player.state.tracks.subtitle.where((t) => t.id != primary.id && t.id != 'auto' && t.id != 'no').toList();
    final loadedTitles = widget.player.state.tracks.subtitle.map((t) => normalizeTrackPart(t.title)).toSet();

    Icon radio(bool on) => Icon(on ? Icons.radio_button_checked : Icons.radio_button_off);

    return [
      ListTile(leading: radio(selected == null), title: Text('player.secondary_subtitles_off'.tr()), onTap: _turnSecondaryOff),
      for (final t in tracks) ListTile(leading: radio(selected?.id == t.id), title: Text(t.title ?? t.language ?? t.id), onTap: () => _selectSecondary(t)),
      FutureBuilder<List<String>>(
        future: _siblingFiles,
        builder: (context, snapshot) {
          final files = (snapshot.data ?? const <String>[]).where((f) => !loadedTitles.contains(normalizeTrackPart(_trackTitle(f))));
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final file in files)
                ListTile(
                  leading: radio(false),
                  title: Text(Uri.parse(file).pathSegments.lastOrNull ?? file),
                  onTap: () => _addSecondaryFile(file, _trackTitle(file)),
                ),
            ],
          );
        },
      ),
      ListTile(leading: const Icon(Icons.folder_open), title: Text('player.load_secondary_subtitle_file'.tr()), onTap: _pickSecondaryFile),
    ];
  }

  /// The same title the player gives a sibling file it loads, so stored choices match either way.
  String _trackTitle(String uri) => p.basename(Uri.parse(uri).path);

  Future<void> _turnSecondaryOff() async {
    await _runSecondary(() async {
      await widget.secondarySubtitles.off();
      await PlayraStorage.saveSecondarySubtitleKey(widget.video.id, PlayraStorage.secondarySubtitleOff);
    });
  }

  /// Picking the current main track as the secondary one swaps the two.
  Future<void> _selectSecondary(SubtitleTrack track) async {
    await _runSecondary(() async {
      final secondary = widget.secondarySubtitles;
      if ((await secondary.mainTrack())?.id == track.id) {
        final previousSecondary = secondary.selected.value;
        await secondary.off();
        await _applyTrack(previousSecondary ?? SubtitleTrack.no());
      }
      await secondary.select(track);
      await PlayraStorage.saveSecondarySubtitleKey(widget.video.id, stableSubtitleTrackKey(track));
    });
  }

  Future<void> _addSecondaryFile(String uri, String title) async {
    await _runSecondary(() async {
      final track = await widget.secondarySubtitles.addFile(uri, title);
      if (track != null) await PlayraStorage.saveSecondarySubtitleKey(widget.video.id, stableSubtitleTrackKey(track));
    });
  }

  Future<void> _pickSecondaryFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'ssa', 'vtt', 'sub'],
      dialogTitle: 'player.load_secondary_subtitle_file'.tr(),
    );
    final path = res?.files.firstOrNull?.path;
    if (path == null) return;
    await _addSecondaryFile(Uri.file(path).toString(), res!.files.first.name);
  }

  Future<void> _runSecondary(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, st) {
      debugPrint('Playra secondary subtitle change failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Playback error: $e')));
      }
    }
    if (mounted) setState(() {});
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
    final videoInfo = VideoInfo(path: widget.video.uri, name: widget.video.name, directory: _dirOf(widget.video.uri));
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
