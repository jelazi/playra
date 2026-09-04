import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;

import '../bloc/subtitle/subtitle_bloc.dart';
import '../bloc/subtitle/subtitle_event.dart';
import '../bloc/subtitle/subtitle_state.dart';
import '../models/media_info.dart';
import '../models/video_info.dart';
import '../services/media_cache_service.dart';
import '../services/playra_storage.dart';
import '../services/settings_service.dart';
import '../services/subtitle_file_service.dart';
import '../services/tmdb_service.dart';
import '../services/video_name_parser.dart';
import 'subtitle_editor_screen.dart';
import 'subtitle_search_screen.dart';
import 'video_player_screen.dart';
import 'video_selection_screen.dart';

class VideoLibraryScreen extends StatefulWidget {
  const VideoLibraryScreen({super.key});

  @override
  State<VideoLibraryScreen> createState() => _VideoLibraryScreenState();
}

class _FolderEntry {
  final String? sectionKey;
  final String? title;
  final int? count;
  final bool? expanded;
  final VideoInfo? video;
  final int level;
  final bool isRoot;

  const _FolderEntry._({this.sectionKey, this.title, this.count, this.expanded, this.video, this.level = 0, this.isRoot = false});

  const _FolderEntry.header({required String sectionKey, required String title, required int count, required bool expanded, required int level, required bool isRoot})
    : this._(sectionKey: sectionKey, title: title, count: count, expanded: expanded, level: level, isRoot: isRoot);

  const _FolderEntry.video(VideoInfo video, {required int level}) : this._(video: video, level: level);

  bool get isHeader => video == null;
}

class _FolderNode {
  final String name;
  final String fullPath;
  final Map<String, _FolderNode> children = <String, _FolderNode>{};
  final List<VideoInfo> videos = <VideoInfo>[];

  _FolderNode({required this.name, required this.fullPath});
}

class _VideoLibraryScreenState extends State<VideoLibraryScreen> {
  static const int _minVideoBytes = 256 * 1024;

  static const Set<String> _supportedVideoExtensions = {'.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.mpg', '.mpeg', '.3gp'};

  final List<VideoInfo> _videos = [];
  VideoInfo? _selectedVideo;
  MediaInfo? _selectedMediaInfo;
  bool _isSearching = false;
  bool _isDragging = false;
  bool _isFromCache = false; // Příznak, že info je z cache
  final Map<String, bool> _expandedSections = {};

  final TmdbService _tmdbService = TmdbService();

  // Breakpoint pro responzivní layout
  static const double _tabletBreakpoint = 600;

  bool _isTabletOrDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= _tabletBreakpoint;
  }

  bool get _supportsDesktopDragDrop {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();

    // Zkontrolovat, zda je uživatel přihlášen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLoginStatus();
    });
  }

  /// Refresh subtitle status for all videos (both from Hive and file system)
  void _refreshSubtitleStates() {
    setState(() {
      for (int i = 0; i < _videos.length; i++) {
        _videos[i] = SubtitleFileService.updateVideoInfoWithSubtitles(_videos[i]);
      }
    });
  }

  void _checkLoginStatus() {
    final settings = SettingsService.getSettings();
    final subtitleBloc = context.read<SubtitleBloc>();

    // Pokud už jsme přihlášeni, nic nedělat
    if (subtitleBloc.state is SubtitleLoggedIn) {
      return;
    }

    // Zkusit auto-login pokud máme uložené údaje
    if (settings.username != null && settings.username!.isNotEmpty && settings.password != null && settings.password!.isNotEmpty) {
      debugPrint('🔵 VideoLibraryScreen: Attempting auto-login');
      subtitleBloc.add(AutoLoginToTitulky());
    } else {
      // Zobrazit přihlášení
      _showLoginDialog();
    }
  }

  void _showLoginDialog() {
    showDialog(context: context, barrierDismissible: false, builder: (context) => const VideoSelectionScreen(isDialog: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Knihovna videí - vyhledávání titulků'), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: _isTabletOrDesktop(context)
          ? Row(
              children: [
                // Levá strana - Info o vybraném videu
                Expanded(flex: 3, child: _buildVideoInfo()),
                const VerticalDivider(width: 1),
                // Pravá strana - Seznam videí
                Expanded(flex: 2, child: _buildVideoList()),
              ],
            )
          : _buildVideoList(), // Na telefonu pouze seznam
    );
  }

  // Obrazovka detailu pro telefon
  void _showVideoDetailScreen(VideoInfo video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _VideoDetailScreen(
          video: video,
          mediaInfo: _selectedMediaInfo,
          isSearching: _isSearching,
          isFromCache: _isFromCache,
          onPlay: () => _playVideo(video),
          onSearchSubtitles: _searchSubtitles,
          onEditSubtitles: video.hasAnySubtitles && video.subtitleFiles.isNotEmpty ? () => _openSubtitleEditor(video) : null,
          onEditMediaInfo: () => _editMediaInfo(video),
          onSearchAgain: () => _searchMediaInfo(video),
        ),
      ),
    );
  }

  Widget _buildVideoInfo() {
    if (_selectedVideo == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('video.select_video_from_list'.tr(), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster a základní info
          if (_selectedMediaInfo != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster
                if (_selectedMediaInfo!.posterUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      _selectedMediaInfo!.posterUrl,
                      width: 200,
                      height: 300,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(width: 200, height: 300, color: Colors.grey[300], child: const Icon(Icons.movie, size: 64)),
                    ),
                  ),
                const SizedBox(width: 24),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(_selectedMediaInfo!.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      if (_selectedMediaInfo!.originalTitle != _selectedMediaInfo!.title)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SelectableText(
                            _selectedMediaInfo!.originalTitle,
                            style: TextStyle(fontSize: 16, color: Colors.grey[600], fontStyle: FontStyle.italic),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Žánry
                      if (_selectedMediaInfo!.genres.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          children: _selectedMediaInfo!.genres.map((genre) {
                            return Chip(label: Text(genre), backgroundColor: Colors.blue[100]);
                          }).toList(),
                        ),
                      const SizedBox(height: 16),
                      // Hodnocení
                      if (_selectedMediaInfo!.voteAverage != null)
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 24),
                            const SizedBox(width: 8),
                            SelectableText(_selectedMediaInfo!.voteAverage!.toStringAsFixed(1), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            SelectableText(' / 10', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                          ],
                        ),
                      const SizedBox(height: 16),
                      // Rok vydání / Sezóny
                      if (_selectedMediaInfo!.type == MediaType.movie && _selectedMediaInfo!.releaseDate != null)
                        SelectableText('${'video.release_date'.tr()}: ${_selectedMediaInfo!.releaseDate}', style: const TextStyle(fontSize: 16)),
                      if (_selectedMediaInfo!.type == MediaType.tv) ...[
                        if (_selectedMediaInfo!.numberOfSeasons != null)
                          SelectableText('${'video.seasons'.tr()}: ${_selectedMediaInfo!.numberOfSeasons}', style: const TextStyle(fontSize: 16)),
                        if (_selectedMediaInfo!.numberOfEpisodes != null)
                          SelectableText('${'video.episodes'.tr()}: ${_selectedMediaInfo!.numberOfEpisodes}', style: const TextStyle(fontSize: 16)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Popis
            if (_selectedMediaInfo!.overview != null && _selectedMediaInfo!.overview!.isNotEmpty) ...[
              SelectableText('video.overview'.tr(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(_selectedMediaInfo!.overview!, style: const TextStyle(fontSize: 16, height: 1.5)),
              const SizedBox(height: 24),
            ],
            // Tlačítka pro přehrávání a vyhledání titulků
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _playVideo(_selectedVideo!),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('video.play'.tr()),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _searchSubtitles(),
                    icon: const Icon(Icons.subtitles),
                    label: Text('subtitle.search_button'.tr()),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                if (_selectedVideo!.hasAnySubtitles && _selectedVideo!.subtitleFiles.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openSubtitleEditor(_selectedVideo!),
                      icon: const Icon(Icons.edit),
                      label: Text('player.edit_subtitles'.tr()),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.orange, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Info o cache a tlačítko pro editaci
            if (_isFromCache) ...[
              Row(
                children: [
                  Icon(Icons.cached, size: 16, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Text('video.cached_info'.tr(), style: TextStyle(fontSize: 14, color: Colors.green[700])),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // Tlačítko pro změnu přiřazení
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(onPressed: () => _editMediaInfo(_selectedVideo!), icon: const Icon(Icons.edit), label: Text('video.edit_media_info'.tr())),
            ),
          ] else if (_isSearching) ...[
            const Center(child: CircularProgressIndicator()),
          ] else ...[
            SelectableText(_selectedVideo!.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('video.no_media_info'.tr()),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(onPressed: () => _searchMediaInfo(_selectedVideo!), icon: const Icon(Icons.refresh), label: Text('video.search_again'.tr())),
                const SizedBox(width: 12),
                ElevatedButton.icon(onPressed: () => _editMediaInfo(_selectedVideo!), icon: const Icon(Icons.search), label: Text('video.manual_search'.tr())),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoList() {
    final isPhone = !_isTabletOrDesktop(context);
    final libraryFolders = PlayraStorage.getLibraryFolders();
    final entries = _buildFolderEntries();

    return Stack(
      children: [
        Column(
          children: [
            if (libraryFolders.isNotEmpty)
              Card(
                margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.folder_open, size: 16),
                          const SizedBox(width: 6),
                          Expanded(child: Text('Přidané adresáře', style: Theme.of(context).textTheme.labelLarge)),
                          IconButton(tooltip: 'home.add_folder'.tr(), onPressed: _addLibraryFolder, icon: const Icon(Icons.add_circle_outline, size: 18)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: libraryFolders
                            .map(
                              (folder) => ActionChip(
                                avatar: const Icon(Icons.folder, size: 14),
                                label: Text(path.basename(folder)),
                                tooltip: folder,
                                onPressed: () => _addVideosFromDirectory(folder),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: _supportsDesktopDragDrop
                  ? DropTarget(
                      onDragDone: (details) async {
                        await _addVideosFromPaths(details.files.map((f) => f.path).toList());
                      },
                      onDragEntered: (details) {
                        setState(() => _isDragging = true);
                      },
                      onDragExited: (details) {
                        setState(() => _isDragging = false);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _isDragging ? Colors.blue : Theme.of(context).dividerColor, width: _isDragging ? 2 : 1),
                          color: _isDragging ? Colors.blue.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.upload_file, size: 18, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('video.drag_drop_hint'.tr(), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                            ),
                          ],
                        ),
                      ),
                    )
                  : InkWell(
                      onTap: _pickVideos,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Theme.of(context).dividerColor),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.video_library, size: 18, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('video.tap_to_add'.tr(), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // Drop zone
            Expanded(
              child: _supportsDesktopDragDrop
                  ? DropTarget(
                      onDragDone: (details) async {
                        await _addVideosFromPaths(details.files.map((f) => f.path).toList());
                      },
                      onDragEntered: (details) {
                        setState(() => _isDragging = true);
                      },
                      onDragExited: (details) {
                        setState(() => _isDragging = false);
                      },
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: _isDragging ? Colors.blue : Colors.transparent, width: 2)),
                        child: _videos.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.video_library_outlined, size: 64, color: Colors.grey[400]),
                                    const SizedBox(height: 16),
                                    Text(
                                      'video.drag_drop_hint'.tr(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: entries.length,
                                itemBuilder: (context, index) {
                                  final entry = entries[index];

                                  if (entry.isHeader) {
                                    final expanded = entry.expanded ?? false;
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _expandedSections[entry.sectionKey!] = !expanded;
                                        });
                                      },
                                      child: Container(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                        padding: EdgeInsets.fromLTRB(10 + (entry.level * 16), 8, 10, 8),
                                        child: Row(
                                          children: [
                                            Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 18),
                                            const SizedBox(width: 6),
                                            Icon(entry.isRoot ? Icons.folder_open : Icons.folder, size: 16),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${entry.title} (${entry.count})',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.labelLarge,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  final video = entry.video!;
                                  final isSelected = _selectedVideo == video;

                                  return GestureDetector(
                                    onDoubleTap: () => _searchSubtitles(video: video),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      decoration: BoxDecoration(
                                        color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : null,
                                        border: isSelected
                                            ? Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4))
                                            : const Border(left: BorderSide(color: Colors.transparent, width: 4)),
                                      ),
                                      child: ListTile(
                                        selected: isSelected,
                                        selectedTileColor: Colors.transparent,
                                        contentPadding: EdgeInsets.only(left: 12 + (entry.level * 16), right: 8, top: 2, bottom: 2),
                                        leading: Stack(
                                          children: [
                                            Icon(
                                              Icons.movie,
                                              color: isSelected ? Theme.of(context).colorScheme.primary : (video.hasAnySubtitles ? Colors.green : null),
                                              size: isSelected ? 28 : 24,
                                            ),
                                            // Subtitle indicator
                                            if (video.hasAnySubtitles)
                                              Positioned(
                                                right: -2,
                                                bottom: -2,
                                                child: Container(
                                                  padding: const EdgeInsets.all(2),
                                                  decoration: BoxDecoration(color: video.hasPhysicalSubtitles ? Colors.green : Colors.orange, shape: BoxShape.circle),
                                                  child: const Icon(Icons.subtitles, color: Colors.white, size: 10),
                                                ),
                                              ),
                                          ],
                                        ),
                                        title: Text(
                                          video.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: isSelected ? TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary) : null,
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(path.dirname(video.path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                            if (video.hasAnySubtitles)
                                              Row(
                                                children: [
                                                  Icon(Icons.subtitles, size: 12, color: video.hasPhysicalSubtitles ? Colors.green : Colors.orange),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      video.hasPhysicalSubtitles ? 'Soubory titulků (${video.subtitleFiles.length})' : 'Stažené přes aplikaci',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: video.hasPhysicalSubtitles ? Colors.green[700] : Colors.orange[700],
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            if (isSelected)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Text(
                                                  'Dvojklik = vyhledat titulky',
                                                  style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7), fontStyle: FontStyle.italic),
                                                ),
                                              ),
                                          ],
                                        ),
                                        trailing: isPhone
                                            ? IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _selectVideo(video))
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(icon: const Icon(Icons.play_circle_outline, size: 24), tooltip: 'video.play'.tr(), onPressed: () => _playVideo(video)),
                                                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => _removeVideo(video)),
                                                ],
                                              ),
                                        onTap: () => _selectVideo(video),
                                        onLongPress: isPhone ? () => _showVideoOptionsMenu(video) : null,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    )
                  : Container(
                      child: _videos.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.video_library_outlined, size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'video.tap_to_add'.tr(),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(onPressed: _pickVideos, icon: const Icon(Icons.add), label: Text('video.add_videos'.tr())),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: entries.length,
                              itemBuilder: (context, index) {
                                final entry = entries[index];

                                if (entry.isHeader) {
                                  final expanded = entry.expanded ?? false;
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        _expandedSections[entry.sectionKey!] = !expanded;
                                      });
                                    },
                                    child: Container(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                      padding: EdgeInsets.fromLTRB(10 + (entry.level * 16), 8, 10, 8),
                                      child: Row(
                                        children: [
                                          Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 18),
                                          const SizedBox(width: 6),
                                          Icon(entry.isRoot ? Icons.folder_open : Icons.folder, size: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${entry.title} (${entry.count})',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context).textTheme.labelLarge,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }

                                final video = entry.video!;
                                final isSelected = _selectedVideo == video;

                                return GestureDetector(
                                  onDoubleTap: () => _searchSubtitles(video: video),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : null,
                                      border: isSelected
                                          ? Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4))
                                          : const Border(left: BorderSide(color: Colors.transparent, width: 4)),
                                    ),
                                    child: ListTile(
                                      selected: isSelected,
                                      selectedTileColor: Colors.transparent,
                                      contentPadding: EdgeInsets.only(left: 12 + (entry.level * 16), right: 8, top: 2, bottom: 2),
                                      leading: Stack(
                                        children: [
                                          Icon(
                                            Icons.movie,
                                            color: isSelected ? Theme.of(context).colorScheme.primary : (video.hasAnySubtitles ? Colors.green : null),
                                            size: isSelected ? 28 : 24,
                                          ),
                                          // Subtitle indicator
                                          if (video.hasAnySubtitles)
                                            Positioned(
                                              right: -2,
                                              bottom: -2,
                                              child: Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: BoxDecoration(color: video.hasPhysicalSubtitles ? Colors.green : Colors.orange, shape: BoxShape.circle),
                                                child: const Icon(Icons.subtitles, color: Colors.white, size: 10),
                                              ),
                                            ),
                                        ],
                                      ),
                                      title: Text(
                                        video.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: isSelected ? TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary) : null,
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(path.dirname(video.path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                          if (video.hasAnySubtitles)
                                            Row(
                                              children: [
                                                Icon(Icons.subtitles, size: 12, color: video.hasPhysicalSubtitles ? Colors.green : Colors.orange),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    video.hasPhysicalSubtitles ? 'Soubory titulků (${video.subtitleFiles.length})' : 'Stažené přes aplikaci',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: video.hasPhysicalSubtitles ? Colors.green[700] : Colors.orange[700],
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          if (isSelected)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Dvojklik = vyhledat titulky',
                                                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7), fontStyle: FontStyle.italic),
                                              ),
                                            ),
                                        ],
                                      ),
                                      trailing: isPhone
                                          ? IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _selectVideo(video))
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(icon: const Icon(Icons.play_circle_outline, size: 24), tooltip: 'video.play'.tr(), onPressed: () => _playVideo(video)),
                                                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => _removeVideo(video)),
                                              ],
                                            ),
                                      onTap: () => _selectVideo(video),
                                      onLongPress: isPhone ? () => _showVideoOptionsMenu(video) : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
            // Tlačítka - pouze na tabletu/desktopu
            if (!isPhone) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickVideos,
                        icon: const Icon(Icons.add, size: 18),
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text('video.add_videos'.tr())),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _videos.isNotEmpty ? _refreshSubtitleStates : null,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Aktualizovat titulky')),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _videos.isNotEmpty ? _clearAll : null,
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text('video.clear_all'.tr())),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        // FAB pro telefon
        if (isPhone && _videos.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(onPressed: _pickVideos, child: const Icon(Icons.add)),
          ),
      ],
    );
  }

  // Menu pro dlouhé stisknutí na telefonu
  void _showVideoOptionsMenu(VideoInfo video) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text('video.play'.tr()),
              onTap: () {
                Navigator.pop(context);
                _playVideo(video);
              },
            ),
            ListTile(
              leading: const Icon(Icons.subtitles),
              title: Text('subtitle.search_button'.tr()),
              onTap: () {
                Navigator.pop(context);
                _selectVideo(video);
              },
            ),
            if (video.hasAnySubtitles && video.subtitleFiles.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.orange),
                title: Text('player.edit_subtitles'.tr()),
                onTap: () {
                  Navigator.pop(context);
                  _openSubtitleEditor(video);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text('video.remove'.tr()),
              onTap: () {
                Navigator.pop(context);
                _removeVideo(video);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickVideos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg', '3gp'],
      allowMultiple: true,
      dialogTitle: 'video.select_videos'.tr(),
    );

    if (result != null && result.files.isNotEmpty) {
      final paths = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
      await _addVideosFromPaths(paths);
    }
  }

  Future<void> _addLibraryFolder() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected == null || selected.isEmpty) return;

    await PlayraStorage.addLibraryFolder(selected);

    await _addVideosFromDirectory(selected);
    if (mounted) setState(() {});
  }

  Future<void> _addVideosFromDirectory(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;

    final paths = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && _isSupportedVideoFile(entity.path) && await _isValidVideoFile(entity.path)) {
        paths.add(entity.path);
      }
    }

    if (paths.isNotEmpty) {
      await _addVideosFromPaths(paths);
    }
  }

  bool _isSupportedVideoFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return _supportedVideoExtensions.contains(ext);
  }

  Future<bool> _isValidVideoFile(String filePath) async {
    final base = path.basename(filePath);
    if (base.startsWith('.')) return false;

    try {
      final stat = await File(filePath).stat();
      if (stat.type != FileSystemEntityType.file) return false;
      if (stat.size < _minVideoBytes) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _addVideosFromPaths(List<String> paths) async {
    for (final filePath in paths) {
      if (!_isSupportedVideoFile(filePath)) continue;
      if (!await _isValidVideoFile(filePath)) continue;

      // Kontrola, zda už video není v seznamu
      if (_videos.any((v) => v.path == filePath)) continue;

      final fileName = path.basename(filePath);
      final fileDir = path.dirname(filePath);

      // Create VideoInfo and check for subtitles
      var videoInfo = VideoInfo(path: filePath, name: fileName, directory: fileDir);
      videoInfo = SubtitleFileService.updateVideoInfoWithSubtitles(videoInfo);

      if (!mounted) return;
      setState(() {
        _videos.add(videoInfo);
      });

      // Automaticky vyhledat info o prvním přidaném videu
      if (_videos.length == 1) {
        _selectVideo(videoInfo);
      }
    }
  }

  void _removeVideo(VideoInfo video) {
    setState(() {
      _videos.remove(video);
      if (_selectedVideo == video) {
        _selectedVideo = null;
        _selectedMediaInfo = null;
        if (_videos.isNotEmpty) {
          _selectVideo(_videos.first);
        }
      }
    });
  }

  void _playVideo(VideoInfo video) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => VideoPlayerScreen(videoInfo: video)));
  }

  void _clearAll() {
    setState(() {
      _videos.clear();
      _selectedVideo = null;
      _selectedMediaInfo = null;
      _expandedSections.clear();
    });
  }

  List<_FolderEntry> _buildFolderEntries() {
    final rootNodes = <String, _FolderNode>{};
    final libraryFolders = PlayraStorage.getLibraryFolders().toList()..sort((a, b) => b.length.compareTo(a.length));

    for (final v in _videos) {
      final rootPath = _resolveLibraryRootForPath(v.path, libraryFolders) ?? path.dirname(v.path);
      final rootNode = rootNodes.putIfAbsent(rootPath, () => _FolderNode(name: path.basename(rootPath), fullPath: rootPath));

      final videoDir = path.dirname(v.path);
      final relativeDir = path.relative(videoDir, from: rootPath);

      var node = rootNode;
      if (relativeDir != '.' && relativeDir.isNotEmpty && !relativeDir.startsWith('..')) {
        for (final segment in path.split(relativeDir)) {
          if (segment.isEmpty || segment == '.') continue;
          final childFullPath = path.join(node.fullPath, segment);
          node = node.children.putIfAbsent(segment, () => _FolderNode(name: segment, fullPath: childFullPath));
        }
      }

      node.videos.add(v);
    }

    final roots = rootNodes.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final out = <_FolderEntry>[];

    for (final root in roots) {
      _appendNodeEntries(out, root, level: 0, isRoot: true);
    }

    return out;
  }

  void _appendNodeEntries(List<_FolderEntry> out, _FolderNode node, {required int level, required bool isRoot}) {
    final key = 'dir:${node.fullPath}';
    final expanded = _expandedSections[key] ?? false;
    final totalCount = _countVideos(node);

    out.add(_FolderEntry.header(sectionKey: key, title: node.name, count: totalCount, expanded: expanded, level: level, isRoot: isRoot));

    if (!expanded) return;

    final children = node.children.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final child in children) {
      _appendNodeEntries(out, child, level: level + 1, isRoot: false);
    }

    node.videos.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final video in node.videos) {
      out.add(_FolderEntry.video(video, level: level + 1));
    }
  }

  int _countVideos(_FolderNode node) {
    var count = node.videos.length;
    for (final child in node.children.values) {
      count += _countVideos(child);
    }
    return count;
  }

  String? _resolveLibraryRootForPath(String filePath, List<String> libraryFolders) {
    for (final folder in libraryFolders) {
      final normalizedFolder = path.normalize(folder);
      final normalizedFile = path.normalize(filePath);

      if (normalizedFile == normalizedFolder) {
        return folder;
      }

      final folderWithSeparator = normalizedFolder.endsWith(path.separator) ? normalizedFolder : '$normalizedFolder${path.separator}';

      if (normalizedFile.startsWith(folderWithSeparator)) {
        return folder;
      }
    }
    return null;
  }

  void _selectVideo(VideoInfo video) {
    setState(() {
      _selectedVideo = video;
      _selectedMediaInfo = null;
    });
    _searchMediaInfo(video).then((_) {
      // Na telefonu otevřít detail screen po načtení
      if (mounted && !_isTabletOrDesktop(context)) {
        _showVideoDetailScreen(video);
      }
    });
  }

  Future<void> _searchMediaInfo(VideoInfo video) async {
    setState(() => _isSearching = true);

    try {
      // Parsovat název souboru
      final parsed = VideoNameParser.parse(video.path);
      debugPrint('Parsed name: ${parsed.cleanName}');
      debugPrint('Is TV: ${parsed.isTV}, Season: ${parsed.season}, Episode: ${parsed.episode}');

      // Zkontrolovat cache
      final cached = MediaCacheService.getMapping(parsed.cleanName);
      if (cached != null) {
        debugPrint('✅ Found in cache: ${cached.title}');

        // Načíst detaily z cache
        final language = context.locale.languageCode;
        MediaInfo? details;

        if (cached.mediaType == 'movie') {
          details = await _tmdbService.getMovieDetails(cached.tmdbId, language);
        } else {
          details = await _tmdbService.getTVDetails(cached.tmdbId, language);
        }

        if (mounted) {
          setState(() {
            _selectedMediaInfo = details ?? MediaCacheService.cacheToMediaInfo(cached);
            _isFromCache = true;
            _isSearching = false;
          });
        }
        return;
      }

      // Vyhledat v TMDB
      final language = context.locale.languageCode;
      final results = await _tmdbService.search(query: parsed.cleanName, language: language, searchMovies: !parsed.isTV, searchTV: parsed.isTV, year: parsed.year);

      if (results.isNotEmpty) {
        // Zobrazit dialog s výběrem
        if (mounted) {
          setState(() => _isSearching = false);

          final selectedMedia = await _showMediaSelectionDialog(results, parsed.cleanName);

          if (selectedMedia != null) {
            setState(() => _isSearching = true);

            // Získat detaily
            MediaInfo? details;
            if (selectedMedia.type == MediaType.movie) {
              details = await _tmdbService.getMovieDetails(selectedMedia.id, language);
            } else {
              details = await _tmdbService.getTVDetails(selectedMedia.id, language);
            }

            final finalInfo = details ?? selectedMedia;

            // Uložit do cache
            await MediaCacheService.saveMapping(parsed.cleanName, finalInfo);
            debugPrint('💾 Saved to cache: ${parsed.cleanName} → ${finalInfo.title}');

            if (mounted) {
              setState(() {
                _selectedMediaInfo = finalInfo;
                _isFromCache = false;
                _isSearching = false;
              });
            }
          } else {
            setState(() => _isSearching = false);
          }
        }
      } else {
        if (mounted) {
          setState(() => _isSearching = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('video.media_not_found'.tr())));
        }
      }
    } catch (e) {
      debugPrint('Error searching media info: $e');
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('video.search_error'.tr())));
      }
    }
  }

  // Funkce pro editaci přiřazení
  Future<void> _editMediaInfo(VideoInfo video) async {
    final parsed = VideoNameParser.parse(video.path);

    // Zobrazit dialog pro ruční vyhledávání
    final selectedMedia = await _showManualSearchDialog(parsed.cleanName);

    if (selectedMedia != null && mounted) {
      // Uložit do cache
      await MediaCacheService.saveMapping(parsed.cleanName, selectedMedia);

      setState(() {
        _selectedMediaInfo = selectedMedia;
        _isFromCache = false;
      });
    }
  }

  Future<MediaInfo?> _showMediaSelectionDialog(List<MediaInfo> results, String cleanName) async {
    final selected = await showDialog<MediaInfo>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('video.select_media'.tr()),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length > 10 ? 10 : results.length,
            itemBuilder: (context, index) {
              final media = results[index];
              return ListTile(
                leading: media.posterPath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          media.posterUrl,
                          width: 40,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(width: 40, height: 60, color: Colors.grey[300], child: const Icon(Icons.movie, size: 24)),
                        ),
                      )
                    : Container(width: 40, height: 60, color: Colors.grey[300], child: const Icon(Icons.movie, size: 24)),
                title: Text(media.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (media.originalTitle != media.title) Text(media.originalTitle, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    Text(
                      '${media.releaseDate?.substring(0, 4) ?? '?'} • ${media.type == MediaType.movie ? 'Film' : 'Seriál'} • ⭐ ${media.voteAverage?.toStringAsFixed(1) ?? '?'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                onTap: () => Navigator.pop(context, media),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('common.cancel'.tr())),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(context); // Zavřít první dialog
              await _showManualSearchDialog(cleanName);
            },
            icon: const Icon(Icons.search),
            label: Text('video.manual_search'.tr()),
          ),
        ],
      ),
    );

    // Pokud selected je null (Cancel nebo Ruční vyhledávání), zkusit ruční vyhledávání
    if (selected == null && mounted) {
      return await _showManualSearchDialog(cleanName);
    }

    return selected;
  }

  // Dialog pro ruční vyhledávání
  Future<MediaInfo?> _showManualSearchDialog(String initialQuery) async {
    final controller = TextEditingController(text: initialQuery);
    List<MediaInfo> searchResults = [];
    bool isSearching = false;

    return showDialog<MediaInfo>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('video.manual_search'.tr()),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'video.manual_search_hint'.tr(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () async {
                        if (controller.text.trim().isEmpty) return;

                        setDialogState(() {
                          isSearching = true;
                          searchResults = [];
                        });

                        final language = context.locale.languageCode;
                        final results = await _tmdbService.search(query: controller.text.trim(), language: language, searchMovies: true, searchTV: true);

                        setDialogState(() {
                          searchResults = results;
                          isSearching = false;
                        });
                      },
                    ),
                  ),
                  onSubmitted: (value) async {
                    if (value.trim().isEmpty) return;

                    setDialogState(() {
                      isSearching = true;
                      searchResults = [];
                    });

                    final language = context.locale.languageCode;
                    final results = await _tmdbService.search(query: value.trim(), language: language, searchMovies: true, searchTV: true);

                    setDialogState(() {
                      searchResults = results;
                      isSearching = false;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isSearching
                      ? const Center(child: CircularProgressIndicator())
                      : searchResults.isEmpty
                      ? Center(
                          child: Text('video.manual_search_hint'.tr(), style: TextStyle(color: Colors.grey[600])),
                        )
                      : ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final media = searchResults[index];
                            return ListTile(
                              leading: media.posterPath != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        media.posterUrl,
                                        width: 40,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(width: 40, height: 60, color: Colors.grey[300], child: const Icon(Icons.movie, size: 24)),
                                      ),
                                    )
                                  : Container(width: 40, height: 60, color: Colors.grey[300], child: const Icon(Icons.movie, size: 24)),
                              title: Text(media.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (media.originalTitle != media.title) Text(media.originalTitle, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                  Text(
                                    '${media.releaseDate?.substring(0, 4) ?? '?'} • ${media.type == MediaType.movie ? 'Film' : 'Seriál'} • ⭐ ${media.voteAverage?.toStringAsFixed(1) ?? '?'}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              onTap: () => Navigator.pop(context, media),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('common.cancel'.tr()))],
        ),
      ),
    );
  }

  void _searchSubtitles({VideoInfo? video}) {
    final targetVideo = video ?? _selectedVideo;
    if (targetVideo == null) return;

    // If a specific video is provided and is not yet selected, select it first
    if (video != null && _selectedVideo != video) {
      setState(() {
        _selectedVideo = video;
      });
    }

    // Use TMDB title if available (and media info belongs to the target video), else raw name
    final useMediaTitle = _selectedMediaInfo != null && _selectedVideo == targetVideo;
    final videoInfo = VideoInfo(path: targetVideo.path, name: useMediaTitle ? _selectedMediaInfo!.title : targetVideo.name, directory: targetVideo.directory);

    Navigator.push(context, MaterialPageRoute(builder: (context) => SubtitleSearchScreen(videoInfo: videoInfo))).then((_) {
      // Refresh subtitle states after returning from subtitle search
      _refreshSubtitleStates();
    });
  }

  void _openSubtitleEditor(VideoInfo video) {
    // Find the first subtitle file for this video
    final subtitlePath = video.subtitleFiles.isNotEmpty ? video.subtitleFiles.first : SubtitleFileService.getExpectedSubtitlePath(video);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubtitleEditorScreen(videoPath: video.path, subtitlePath: subtitlePath),
      ),
    ).then((_) {
      _refreshSubtitleStates();
    });
  }
}

// Obrazovka detailu videa pro telefon
class _VideoDetailScreen extends StatelessWidget {
  final VideoInfo video;
  final MediaInfo? mediaInfo;
  final bool isSearching;
  final bool isFromCache;
  final VoidCallback onPlay;
  final VoidCallback onSearchSubtitles;
  final VoidCallback? onEditSubtitles;
  final VoidCallback onEditMediaInfo;
  final VoidCallback onSearchAgain;

  const _VideoDetailScreen({
    required this.video,
    required this.mediaInfo,
    required this.isSearching,
    required this.isFromCache,
    required this.onPlay,
    required this.onSearchSubtitles,
    this.onEditSubtitles,
    required this.onEditMediaInfo,
    required this.onSearchAgain,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(mediaInfo?.title ?? video.name), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mediaInfo != null) ...[
              // Poster - na telefonu menší a centrovaný
              if (mediaInfo!.posterUrl.isNotEmpty)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      mediaInfo!.posterUrl,
                      width: 150,
                      height: 225,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(width: 150, height: 225, color: Colors.grey[300], child: const Icon(Icons.movie, size: 48)),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Název
              SelectableText(
                mediaInfo!.title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if (mediaInfo!.originalTitle != mediaInfo!.title)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Center(
                    child: SelectableText(
                      mediaInfo!.originalTitle,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600], fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Žánry
              if (mediaInfo!.genres.isNotEmpty)
                Center(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: mediaInfo!.genres.map((genre) {
                      return Chip(
                        label: Text(genre, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.blue[100],
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 16),
              // Hodnocení a rok
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (mediaInfo!.voteAverage != null) ...[
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text('${mediaInfo!.voteAverage!.toStringAsFixed(1)}/10', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                  ],
                  if (mediaInfo!.releaseDate != null) Text(mediaInfo!.releaseDate!.substring(0, 4), style: const TextStyle(fontSize: 16)),
                  if (mediaInfo!.type == MediaType.tv) ...[
                    const SizedBox(width: 8),
                    Text('• ${mediaInfo!.numberOfSeasons ?? '?'} ${'video.seasons'.tr()}', style: const TextStyle(fontSize: 14)),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              // Popis
              if (mediaInfo!.overview != null && mediaInfo!.overview!.isNotEmpty) ...[
                Text('video.overview'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText(mediaInfo!.overview!, style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 24),
              ],
              // Tlačítka
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: Text('video.play'.tr()),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onSearchSubtitles,
                  icon: const Icon(Icons.subtitles),
                  label: Text('subtitle.search_button'.tr()),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              if (onEditSubtitles != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onEditSubtitles,
                    icon: const Icon(Icons.edit),
                    label: Text('player.edit_subtitles'.tr()),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // Info o cache
              if (isFromCache)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cached, size: 16, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Text('video.cached_info'.tr(), style: TextStyle(fontSize: 14, color: Colors.green[700])),
                  ],
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(onPressed: onEditMediaInfo, icon: const Icon(Icons.edit), label: Text('video.edit_media_info'.tr())),
              ),
            ] else if (isSearching) ...[
              const Center(
                child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
              ),
            ] else ...[
              // Nenalezeno
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    Icon(Icons.movie_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    SelectableText(
                      video.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text('video.no_media_info'.tr(), style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(onPressed: onSearchAgain, icon: const Icon(Icons.refresh), label: Text('video.search_again'.tr())),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(onPressed: onEditMediaInfo, icon: const Icon(Icons.search), label: Text('video.manual_search'.tr())),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
