import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../bloc/library/library_cubit.dart';
import '../models/player_settings.dart';
import '../models/video_info.dart';
import '../models/video_item.dart';
import '../services/playra_storage.dart';
import '../services/subtitle_file_service.dart';
import '../services/video_name_parser.dart';
import 'media_info_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'subtitle_editor_screen.dart';
import 'subtitle_search_screen.dart';

/// Main Playra home screen — the local video library.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<VideoItem> _recents = [];
  Map<String, bool> _expandedSections = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryCubit>().load();
      _loadRecents();
      _loadExpandedSections();
    });
  }

  void _loadRecents() {
    if (mounted) setState(() => _recents = PlayraStorage.getRecent());
  }

  void _loadExpandedSections() {
    if (mounted) {
      setState(() {
        _expandedSections = PlayraStorage.getLibrarySectionExpandedMap();
      });
    }
  }

  Future<void> _setSectionExpanded(String sectionKey, bool expanded) async {
    final updated = Map<String, bool>.from(_expandedSections);
    updated[sectionKey] = expanded;
    await PlayraStorage.setLibrarySectionExpandedMap(updated);
    if (mounted) {
      setState(() {
        _expandedSections = updated;
      });
    }
  }

  Future<void> _openVideo(VideoItem v, {String? libraryMode, List<VideoItem>? allVideos}) async {
    if (libraryMode == 'smart' && allVideos != null) {
      final parsed = VideoNameParser.parse(v.uri);
      if (parsed.isTV) {
        _showSeriesEpisodes(context, v, allVideos);
        return;
      }
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MediaInfoRoute(video: v)));
    _loadRecents();
  }

  Future<void> _addFolder() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected != null) {
      if (!mounted) return;
      await context.read<LibraryCubit>().addFolder(selected);
    }
  }

  Future<void> _openSingleFile() async {
    final initialDir = PlayraStorage.getLastOpenedDirectory();
    final result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: false, initialDirectory: initialDir);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    await PlayraStorage.setLastOpenedDirectory(File(file.path!).parent.path);
    final v = VideoItem(id: file.path!, name: file.name, uri: file.path!, source: VideoSource.local);
    await _openVideo(v);
  }

  Future<void> _updatePlayerSettings(PlayerSettings Function(PlayerSettings) updater) async {
    final current = PlayraStorage.getPlayerSettings();
    final updated = updater(current);
    await PlayraStorage.savePlayerSettings(updated);
    if (mounted) setState(() {});
  }

  Future<void> _refreshLibrary() async {
    await context.read<LibraryCubit>().refresh();
    _loadRecents();
    _loadExpandedSections();
  }

  VideoInfo _toVideoInfo(VideoItem v) {
    final file = File(v.uri);
    return VideoInfo(path: v.uri, name: v.name, directory: file.parent.path);
  }

  bool _isLocalVideo(VideoItem v) => v.source == VideoSource.local && File(v.uri).existsSync();

  Future<void> _showUnsupportedFileActionMessage() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('home.action_local_only'.tr())));
  }

  Future<void> _showFileInfoDialog(VideoItem v) async {
    final file = File(v.uri);
    final stat = _isLocalVideo(v) ? await file.stat() : null;
    final subtitleInfo = _isLocalVideo(v) ? SubtitleFileService.checkSubtitleFiles(_toVideoInfo(v)) : SubtitleFileInfo(hasSubtitles: false, subtitleFiles: []);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('home.file_info'.tr()),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('home.info_name'.tr(), v.name),
              _infoRow('home.info_path'.tr(), v.uri),
              _infoRow('home.info_folder'.tr(), v.folder ?? p.basename(p.dirname(v.uri))),
              _infoRow('home.info_size'.tr(), stat != null ? _formatSize(stat.size) : (v.sizeBytes != null ? _formatSize(v.sizeBytes!) : '-')),
              _infoRow('home.info_modified'.tr(), stat?.modified.toLocal().toString() ?? (v.modified?.toLocal().toString() ?? '-')),
              _infoRow('home.info_extension'.tr(), v.extension.toUpperCase()),
              _infoRow('home.info_subtitles'.tr(), subtitleInfo.description),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('common.ok'.tr()))],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }

  Future<void> _editSubtitles(VideoItem v) async {
    if (!_isLocalVideo(v)) {
      await _showUnsupportedFileActionMessage();
      return;
    }

    final info = SubtitleFileService.checkSubtitleFiles(_toVideoInfo(v));
    if (info.subtitleFiles.isEmpty) {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SubtitleSearchScreen(videoInfo: _toVideoInfo(v))));
      return;
    }

    String? subtitlePath;
    if (info.subtitleFiles.length == 1) {
      subtitlePath = info.subtitleFiles.first;
    } else {
      if (!mounted) return;
      subtitlePath = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text('home.edit_subtitles'.tr())),
              ...info.subtitleFiles.map((path) => ListTile(leading: const Icon(Icons.subtitles), title: Text(p.basename(path)), onTap: () => Navigator.of(ctx).pop(path))),
            ],
          ),
        ),
      );
    }

    if (subtitlePath == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubtitleEditorScreen(videoPath: v.uri, subtitlePath: subtitlePath!),
      ),
    );
  }

  Future<void> _shareVideoFile(VideoItem v) async {
    if (!_isLocalVideo(v)) {
      await _showUnsupportedFileActionMessage();
      return;
    }

    final subtitleInfo = SubtitleFileService.checkSubtitleFiles(_toVideoInfo(v));
    final files = <XFile>[XFile(v.uri), ...subtitleInfo.subtitleFiles.map(XFile.new)];
    await Share.shareXFiles(files, subject: v.displayName, text: v.displayName);
  }

  Future<void> _copyVideoFile(VideoItem v) async {
    await _transferVideoFile(v, move: false);
  }

  Future<void> _moveVideoFile(VideoItem v) async {
    await _transferVideoFile(v, move: true);
  }

  Future<void> _transferVideoFile(VideoItem v, {required bool move}) async {
    if (!_isLocalVideo(v)) {
      await _showUnsupportedFileActionMessage();
      return;
    }

    final targetDir = await FilePicker.platform.getDirectoryPath(dialogTitle: move ? 'home.move_file'.tr() : 'home.copy_file'.tr());
    if (targetDir == null || targetDir.isEmpty) return;

    final subtitleInfo = SubtitleFileService.checkSubtitleFiles(_toVideoInfo(v));
    final sourceFiles = <String>[v.uri, ...subtitleInfo.subtitleFiles];
    final collisions = sourceFiles.where((source) => File(p.join(targetDir, p.basename(source))).existsSync()).toList();
    if (collisions.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('home.target_exists'.tr())));
      return;
    }

    for (final source in sourceFiles) {
      final target = p.join(targetDir, p.basename(source));
      await File(source).copy(target);
    }

    if (move) {
      for (final source in sourceFiles.reversed) {
        final file = File(source);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await PlayraStorage.removeRecent(v.id);
      await PlayraStorage.clearResume(v.id);
      await _refreshLibrary();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((move ? 'home.move_done' : 'home.copy_done').tr())));
  }

  Future<void> _deleteVideoFile(VideoItem v) async {
    if (!_isLocalVideo(v)) {
      await _showUnsupportedFileActionMessage();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('home.delete_file'.tr()),
        content: Text('home.delete_file_confirm'.tr(args: [v.name])),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.cancel'.tr())),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('home.delete_file'.tr())),
        ],
      ),
    );

    if (confirmed != true) return;

    final subtitleInfo = SubtitleFileService.checkSubtitleFiles(_toVideoInfo(v));
    for (final subtitle in subtitleInfo.subtitleFiles) {
      final file = File(subtitle);
      if (await file.exists()) {
        await file.delete();
      }
    }

    final videoFile = File(v.uri);
    if (await videoFile.exists()) {
      await videoFile.delete();
    }

    await PlayraStorage.removeRecent(v.id);
    await PlayraStorage.clearResume(v.id);
    await _refreshLibrary();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('home.delete_done'.tr())));
  }

  Future<void> _copyVideoPath(VideoItem v) async {
    await Clipboard.setData(ClipboardData(text: v.uri));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('home.copy_path_done'.tr())));
  }

  Future<void> _showVideoContextMenu(VideoItem v, Offset globalPosition) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPosition.dx, globalPosition.dy, globalPosition.dx, globalPosition.dy),
      items: [
        PopupMenuItem(value: 'info', child: Text('home.file_info'.tr())),
        PopupMenuItem(value: 'subtitles', child: Text('home.edit_subtitles'.tr())),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'copy', child: Text('home.copy_file'.tr())),
        PopupMenuItem(value: 'move', child: Text('home.move_file'.tr())),
        PopupMenuItem(value: 'copy_path', child: Text('home.copy_path'.tr())),
        PopupMenuItem(value: 'share', child: Text('home.share_file'.tr())),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('home.delete_file'.tr())),
      ],
    );

    switch (selected) {
      case 'info':
        await _showFileInfoDialog(v);
        break;
      case 'subtitles':
        await _editSubtitles(v);
        break;
      case 'copy':
        await _copyVideoFile(v);
        break;
      case 'move':
        await _moveVideoFile(v);
        break;
      case 'copy_path':
        await _copyVideoPath(v);
        break;
      case 'share':
        await _shareVideoFile(v);
        break;
      case 'delete':
        await _deleteVideoFile(v);
        break;
    }
  }

  List<_LibraryEntry> _buildLibraryEntries(List<VideoItem> videos, String mode) {
    if (mode == 'flat') {
      final sorted = videos.toList()..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      return sorted.map((v) => _LibraryEntry.video(v)).toList();
    }

    if (mode == 'smart') {
      final groups = <String, List<VideoItem>>{};
      final labels = <String, String>{};

      for (final v in videos) {
        final parsed = VideoNameParser.parse(v.uri);
        final key = parsed.isTV ? 'smart-tv:${parsed.cleanName.toLowerCase()}' : 'smart-dir:${p.dirname(v.uri).toLowerCase()}';
        labels[key] = parsed.isTV ? parsed.cleanName : (v.folder ?? p.basename(p.dirname(v.uri)));
        groups.putIfAbsent(key, () => []).add(v);
      }

      final keys = groups.keys.toList()..sort((a, b) => (labels[a] ?? a).toLowerCase().compareTo((labels[b] ?? b).toLowerCase()));

      final out = <_LibraryEntry>[];
      for (final key in keys) {
        final items = groups[key]!;
        items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        final expanded = _expandedSections[key] ?? false;
        final headerPoster = items.map((v) => PlayraStorage.getRecentPosterPath(v)).firstWhere((p) => p != null, orElse: () => null);
        out.add(_LibraryEntry.header(sectionKey: key, title: labels[key] ?? key, count: items.length, expanded: expanded, smartGroup: true, posterPath: headerPoster));
        if (expanded) {
          out.addAll(items.map(_LibraryEntry.video));
        }
      }
      return out;
    }

    // structured - group by library folder (ignore nested subfolders)
    final byDir = <String, List<VideoItem>>{};
    final libraryFolders = PlayraStorage.getPlayerSettings().libraryFolders.toSet();
    for (final v in videos) {
      String displayDir = p.dirname(v.uri);
      // Try to find which library folder this file belongs to
      for (final libFolder in libraryFolders) {
        if (v.uri.startsWith(libFolder)) {
          displayDir = libFolder;
          break;
        }
      }
      byDir.putIfAbsent(displayDir, () => []).add(v);
    }

    final dirs = byDir.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final out = <_LibraryEntry>[];
    for (final dir in dirs) {
      final items = byDir[dir]!;
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final key = 'dir:$dir';
      final expanded = _expandedSections[key] ?? false;
      out.add(_LibraryEntry.header(sectionKey: key, title: p.basename(dir), count: items.length, expanded: expanded, smartGroup: false));
      if (expanded) {
        out.addAll(items.map(_LibraryEntry.video));
      }
    }
    return out;
  }

  List<VideoItem> _getSeriesVideos(VideoItem representative, List<VideoItem> allVideos) {
    final parsed = VideoNameParser.parse(representative.uri);
    if (!parsed.isTV) return [representative];
    return allVideos.where((v) {
      final p = VideoNameParser.parse(v.uri);
      if (!p.isTV) return false;
      return p.cleanName.toLowerCase() == parsed.cleanName.toLowerCase();
    }).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _showSeriesEpisodes(BuildContext context, VideoItem representative, List<VideoItem> allVideos) {
    final episodes = _getSeriesVideos(representative, allVideos);
    if (episodes.length <= 1) {
      _openVideo(representative);
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
            title: Text(representative.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
            automaticallyImplyLeading: false,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: episodes.length,
              itemBuilder: (_, i) {
                final ep = episodes[i];
                return ListTile(
                  title: Text(ep.name),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openVideo(ep);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<VideoItem> _gridVideosForMode(List<VideoItem> videos, String mode) {
    if (mode == 'flat') {
      final sorted = videos.toList()..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      return sorted;
    }

    if (mode == 'smart') {
      final byKey = <String, VideoItem>{};
      for (final v in videos) {
        final parsed = VideoNameParser.parse(v.uri);
        final key = parsed.isTV ? 'tv:${parsed.cleanName.toLowerCase()}' : 'dir:${p.dirname(v.uri).toLowerCase()}';
        byKey.putIfAbsent(key, () => v);
      }
      final values = byKey.values.toList()..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      return values;
    }

    final sorted = videos.toList()..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final playerSettings = PlayraStorage.getPlayerSettings();
    final libraryMode = playerSettings.libraryViewMode;
    final visualMode = playerSettings.libraryVisualMode;

    return Scaffold(
      appBar: AppBar(
        title: Text('app.title'.tr()),
        actions: [
          IconButton(tooltip: 'home.open_file'.tr(), icon: const Icon(Icons.video_file), onPressed: _openSingleFile),
          IconButton(
            tooltip: 'home.servers'.tr(),
            icon: const Icon(Icons.dns),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServersScreen())),
          ),
          IconButton(
            tooltip: 'home.settings'.tr(),
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          if (state.loading) return const Center(child: CircularProgressIndicator());

          final hasLibrary = state.folders.isNotEmpty && state.videos.isNotEmpty;
          final showRecents = _recents.isNotEmpty;
          final libraryEntries = _buildLibraryEntries(state.videos, libraryMode);
          final gridVideos = _gridVideosForMode(state.videos, libraryMode);

          if (!hasLibrary && !showRecents) {
            if (state.folders.isEmpty) {
              return _emptyState(icon: Icons.folder_open, title: 'home.empty_title'.tr(), subtitle: 'home.empty_subtitle'.tr());
            }
            return _emptyState(
              icon: Icons.movie_outlined,
              title: 'home.no_videos_title'.tr(),
              subtitle: 'home.no_videos_subtitle'.tr(),
              actionLabel: 'home.refresh_library'.tr(),
              onAction: _refreshLibrary,
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await _refreshLibrary();
            },
            child: CustomScrollView(
              slivers: [
                if (showRecents) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Row(
                        children: [
                          const Icon(Icons.history, size: 18),
                          const SizedBox(width: 8),
                          Text('home.recently_played'.tr(), style: Theme.of(context).textTheme.titleSmall),
                          const Spacer(),
                          TextButton(
                            style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8)),
                            onPressed: () async {
                              await PlayraStorage.clearRecent();
                              _loadRecents();
                            },
                            child: Text('home.clear_recent'.tr(), style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 140,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _recents.length,
                        itemBuilder: (_, i) => _buildRecentCard(_recents[i]),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: Divider(height: 24)),
                ],
                if (hasLibrary)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        children: [
                          const Icon(Icons.video_library, size: 18),
                          const SizedBox(width: 8),
                          Text('home.library'.tr(), style: Theme.of(context).textTheme.titleSmall),
                          const Spacer(),
                          PopupMenuButton<String>(
                            tooltip: 'home.display_options'.tr(),
                            icon: const Icon(Icons.view_compact_alt, size: 18),
                            onSelected: (value) {
                              if (value.startsWith('view:')) {
                                final view = value.substring(5);
                                _updatePlayerSettings((s) => s.copyWith(libraryVisualMode: view));
                                return;
                              }
                              if (value.startsWith('group:')) {
                                final group = value.substring(6);
                                _updatePlayerSettings((s) => s.copyWith(libraryViewMode: group));
                                return;
                              }
                            },
                            itemBuilder: (ctx) => [
                              CheckedPopupMenuItem(value: 'view:list', checked: visualMode == 'list', child: Text('home.view_list'.tr())),
                              CheckedPopupMenuItem(value: 'view:iconsSmall', checked: visualMode == 'iconsSmall', child: Text('home.view_icons_small'.tr())),
                              CheckedPopupMenuItem(value: 'view:iconsLarge', checked: visualMode == 'iconsLarge', child: Text('home.view_icons_large'.tr())),
                              const PopupMenuDivider(),
                              CheckedPopupMenuItem(value: 'group:structured', checked: libraryMode == 'structured', child: Text('settings.library_mode_structured'.tr())),
                              CheckedPopupMenuItem(value: 'group:flat', checked: libraryMode == 'flat', child: Text('settings.library_mode_flat'.tr())),
                              CheckedPopupMenuItem(value: 'group:smart', checked: libraryMode == 'smart', child: Text('settings.library_mode_smart'.tr())),
                            ],
                          ),
                          IconButton(icon: const Icon(Icons.refresh, size: 18), tooltip: 'home.refresh_library'.tr(), onPressed: _refreshLibrary),
                          IconButton(icon: const Icon(Icons.add_circle_outline, size: 18), tooltip: 'home.add_folder'.tr(), onPressed: _addFolder),
                        ],
                      ),
                    ),
                  ),
                if (hasLibrary && visualMode == 'list')
                  SliverList.builder(
                    itemCount: libraryEntries.length,
                    itemBuilder: (context, i) {
                      final entry = libraryEntries[i];
                      if (entry.isHeader) {
                        return InkWell(
                          onTap: () => _setSectionExpanded(entry.sectionKey!, !(entry.expanded ?? false)),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            child: Row(
                              children: [
                                Icon((entry.expanded ?? false) ? Icons.expand_more : Icons.chevron_right, size: 18),
                                const SizedBox(width: 6),
                                if (entry.posterPath != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.file(File(entry.posterPath!), width: 20, height: 28, fit: BoxFit.cover),
                                  )
                                else
                                  Icon(entry.smartGroup == true ? Icons.auto_awesome : Icons.folder_open, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text('${entry.title} (${entry.count})', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final v = entry.video!;
                      final resume = PlayraStorage.getResume(v.id);
                      final posterPath = PlayraStorage.getRecentPosterPath(v);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapDown: (details) => _showVideoContextMenu(v, details.globalPosition),
                        child: ListTile(
                          leading: posterPath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.file(
                                    File(posterPath),
                                    width: 28,
                                    height: 42,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.movie),
                                  ),
                                )
                              : const Icon(Icons.movie),
                          title: Text(v.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [if (v.folder != null) v.folder!, if (v.sizeBytes != null) _formatSize(v.sizeBytes!), if (resume != null) 'home.resume_marker'.tr()].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: resume != null ? const Icon(Icons.history, size: 20) : const Icon(Icons.chevron_right),
                          onTap: () => _openVideo(v),
                          onLongPress: () => _showVideoMenu(v),
                        ),
                      );
                    },
                  ),
                if (hasLibrary && visualMode != 'list')
                  SliverPadding(
                    padding: const EdgeInsets.all(12),
                    sliver: SliverGrid.builder(
                      itemCount: gridVideos.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: visualMode == 'iconsLarge' ? 4 : 9,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: visualMode == 'iconsLarge' ? 0.7 : 0.6,
                      ),
                      itemBuilder: (context, i) {
                        final v = gridVideos[i];
                        final posterPath = PlayraStorage.getRecentPosterPath(v);
                        return InkWell(
                          onTap: () => _openVideo(v, libraryMode: libraryMode, allVideos: state.videos),
                          onSecondaryTapDown: (d) => _showVideoContextMenu(v, d.globalPosition),
                          onLongPress: () => _showVideoMenu(v),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: posterPath != null
                                      ? Image.file(
                                          File(posterPath),
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.movie, size: 32, color: Colors.grey),
                                          ),
                                        )
                                      : Container(
                                          color: Colors.grey[300],
                                          child: const Icon(Icons.movie, size: 32, color: Colors.grey),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                v.displayName,
                                maxLines: visualMode == 'iconsLarge' ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: visualMode == 'iconsLarge' ? 11 : 10),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentCard(VideoItem v) {
    final posterPath = PlayraStorage.getRecentPosterPath(v);
    return GestureDetector(
      onTap: () => _openVideo(v),
      onSecondaryTapDown: (d) => _showRecentContextMenu(v, d.globalPosition),
      child: Container(
        width: 100,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterPath != null)
                      Image.file(
                        File(posterPath),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.movie, size: 40, color: Colors.grey),
                        ),
                      )
                    else
                      Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.movie, size: 40, color: Colors.grey),
                      ),
                    const Positioned(top: 4, right: 4, child: Icon(Icons.play_circle_outline, color: Colors.white, size: 22)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(v.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _showRecentContextMenu(VideoItem v, Offset globalPosition) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPosition.dx, globalPosition.dy, globalPosition.dx, globalPosition.dy),
      items: [PopupMenuItem<String>(value: 'remove_recent', child: Text('home.remove_from_recent'.tr()))],
    );

    if (selected == 'remove_recent') {
      await PlayraStorage.removeRecent(v.id);
      _loadRecents();
    }
  }

  Widget _emptyState({required IconData icon, required String title, required String subtitle, String? actionLabel, Future<void> Function()? onAction}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.refresh), label: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  void _showVideoMenu(VideoItem v) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text('home.file_info'.tr()),
              onTap: () {
                Navigator.of(ctx).pop();
                _showFileInfoDialog(v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.subtitles),
              title: Text('home.edit_subtitles'.tr()),
              onTap: () {
                Navigator.of(ctx).pop();
                _editSubtitles(v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_copy_outlined),
              title: Text('home.copy_file'.tr()),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _copyVideoFile(v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text('home.move_file'.tr()),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _moveVideoFile(v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all),
              title: Text('home.copy_path'.tr()),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _copyVideoPath(v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text('home.share_file'.tr()),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _shareVideoFile(v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text('home.delete_file'.tr()),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _deleteVideoFile(v);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _LibraryEntry {
  final String? sectionKey;
  final String? title;
  final int count;
  final bool? expanded;
  final bool? smartGroup;
  final String? posterPath;
  final VideoItem? video;

  bool get isHeader => sectionKey != null;

  const _LibraryEntry.header({required this.sectionKey, required this.title, required this.count, required this.expanded, required this.smartGroup, this.posterPath})
    : video = null;

  const _LibraryEntry.video(this.video) : sectionKey = null, title = null, count = 0, expanded = null, smartGroup = null, posterPath = null;
}
