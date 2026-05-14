import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../bloc/library/library_cubit.dart';
import '../models/media_info.dart';
import '../models/player_settings.dart';
import '../models/server_connection.dart';
import '../models/video_info.dart';
import '../models/video_item.dart';
import '../services/lan_sync_service.dart';
import '../services/media_lookup_service.dart';
import '../services/playra_storage.dart';
import '../services/smb_download_service.dart';
import '../services/subtitle_file_service.dart';
import '../services/tmdb_service.dart';
import '../services/video_hash_service.dart';
import '../services/video_name_parser.dart';
import 'downloads_screen.dart';
import 'media_info_screen.dart';
import 'player_launcher.dart';
import 'server_browser_screen.dart';
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
  static const Set<String> _supportedVideoExtensions = {'.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.mpg', '.mpeg', '.3gp'};
  static const String _recentsSectionKey = 'home_recently_played';

  List<VideoItem> _recents = [];
  Map<String, bool> _expandedSections = {};
  String? _structuredCurrentFolder;
  bool _isHomeDragging = false;
  bool _isSyncing = false;
  bool _isDiscoveringPeerSessions = false;

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
    final recents = PlayraStorage.getRecent().where((video) => kSupportedVideoExtensions.contains(video.extension.toLowerCase())).toList();
    if (mounted) setState(() => _recents = recents);
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

  String? _smbPathWithoutServerId(String uri) {
    if (!uri.startsWith('smb://')) return null;
    final rest = uri.substring(6);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    return rest.substring(slash);
  }

  VideoItem? _resolveVideoInLibrarySync(VideoItem input, List<VideoItem> videos) {
    for (final v in videos) {
      if (v.id == input.id) return v;
    }

    final inputUri = _normalizeFolderPath(input.uri);
    for (final v in videos) {
      if (_normalizeFolderPath(v.uri) == inputUri) return v;
    }

    if (input.source == VideoSource.smb) {
      final inputSmbPath = _smbPathWithoutServerId(input.uri);
      if (inputSmbPath != null) {
        for (final v in videos) {
          if (v.source != VideoSource.smb) continue;
          if (_smbPathWithoutServerId(v.uri) == inputSmbPath) return v;
        }
      }
    }

    if (input.sizeBytes != null) {
      final bySize = videos.where((v) => v.sizeBytes == input.sizeBytes).toList();
      if (bySize.length == 1) return bySize.first;
      final bySizeAndName = bySize.where((v) => v.displayName.toLowerCase() == input.displayName.toLowerCase()).toList();
      if (bySizeAndName.isNotEmpty) return bySizeAndName.first;
    }

    return null;
  }

  Future<VideoItem?> _resolveVideoForRecentPlayback(VideoItem recent, List<VideoItem> videos) async {
    final directMatch = _resolveVideoInLibrarySync(recent, videos);
    if (directMatch != null) return directMatch;

    final hash = PlayraStorage.getVideoHash(recent.id);
    if (hash == null || hash.isEmpty) return null;

    return _findVideoByHash(hash, videos, titleHint: recent.displayName, sizeBytesHint: recent.sizeBytes);
  }

  Future<void> _openRecentVideo(VideoItem recent, List<VideoItem> videos) async {
    final resolved = await _resolveVideoForRecentPlayback(recent, videos);
    if (!mounted) return;

    if (resolved == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('home.continue_unavailable_here'.tr())));
      return;
    }

    await _openVideo(resolved);
  }

  Future<void> _addFolder() async {
    final smbServers = PlayraStorage.getServers().where((s) => s.type == ServerType.smb).toList();
    if (smbServers.isEmpty) {
      await _addLocalFolder();
      return;
    }

    final addedLocal = await _addLocalFolder();
    if (addedLocal || !mounted) return;

    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.folder_open), title: const Text('Lokální složka'), onTap: () => Navigator.of(ctx).pop('local')),
            ListTile(leading: const Icon(Icons.lan), title: const Text('SMB server'), onTap: () => Navigator.of(ctx).pop('smb')),
          ],
        ),
      ),
    );

    if (source == 'smb') {
      await _addSmbFolder();
      return;
    }

    if (source == 'local') {
      await _addLocalFolder();
    }
  }

  Future<bool> _addLocalFolder() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected != null) {
      if (!mounted) return false;
      await context.read<LibraryCubit>().addFolder(selected);
      return true;
    }
    return false;
  }

  Future<void> _addSmbFolder() async {
    final smbServers = PlayraStorage.getServers().where((s) => s.type == ServerType.smb).toList();
    if (smbServers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nejprve přidejte SMB server v sekci Servery.')));
      return;
    }

    if (!mounted) return;
    final selectedServer = await showModalBottomSheet<ServerConnection>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [for (final s in smbServers) ListTile(leading: const Icon(Icons.lan), title: Text(s.name), subtitle: Text(s.host), onTap: () => Navigator.of(ctx).pop(s))],
        ),
      ),
    );

    if (selectedServer == null || !mounted) return;

    final selectedSmbFolderUri = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ServerBrowserScreen(server: selectedServer, pickFolderMode: true)));

    if (selectedSmbFolderUri == null || selectedSmbFolderUri.isEmpty || !mounted) return;
    await context.read<LibraryCubit>().addFolder(selectedSmbFolderUri);
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

  bool _canSyncAcrossLan() {
    final settings = PlayraStorage.getPlayerSettings();
    return settings.syncUsername.trim().isNotEmpty && settings.syncPassword.trim().isNotEmpty;
  }

  Future<void> _runLanSync() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    final result = await LanSyncService.instance.syncNow();
    if (!mounted) return;
    setState(() => _isSyncing = false);

    final messenger = ScaffoldMessenger.of(context);

    if (!result.configured) {
      messenger.showSnackBar(SnackBar(content: Text('home.sync_not_configured'.tr())));
      return;
    }

    if (result.error != null) {
      messenger.showSnackBar(SnackBar(content: Text('home.sync_failed'.tr(args: [result.error!]))));
      return;
    }

    if (result.peersFound == 0) {
      messenger.showSnackBar(SnackBar(content: Text('home.sync_no_peers'.tr())));
      return;
    }

    messenger.showSnackBar(SnackBar(content: Text('home.sync_done'.tr(args: [result.peersFound.toString(), result.mergedFromPeers.toString(), result.pushedToPeers.toString()]))));
  }

  String _formatPositionText(int milliseconds) {
    final d = Duration(milliseconds: milliseconds);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '${d.inMinutes}:$seconds';
  }

  Future<VideoItem?> _findVideoByHash(String hash, List<VideoItem> videos, {String? titleHint, int? sizeBytesHint}) async {
    for (final video in videos) {
      if (PlayraStorage.getVideoHash(video.id) == hash) return video;
    }

    final candidates = videos.where((v) {
      if (sizeBytesHint != null && sizeBytesHint > 0) {
        return v.sizeBytes == sizeBytesHint;
      }
      if (titleHint != null && titleHint.trim().isNotEmpty) {
        return v.displayName.toLowerCase() == titleHint.trim().toLowerCase();
      }
      return true;
    }).toList();
    final launcher = context.read<PlayerLauncher>();

    for (final video in candidates) {
      if (!mounted) return null;
      final hashTarget = video.source == VideoSource.smb ? await launcher.resolveForHash(context, video) ?? video : video;
      if (!mounted) return null;
      final computed = await VideoHashService.hashForVideo(hashTarget);
      if (computed == null || computed.isEmpty) continue;
      await PlayraStorage.bindVideoToHash(videoId: video.id, hash: computed, title: video.displayName, sizeBytes: video.sizeBytes);
      if (computed == hash) return video;
    }
    return null;
  }

  Future<void> _continueFromPeerPlayback() async {
    if (_isDiscoveringPeerSessions) return;

    setState(() => _isDiscoveringPeerSessions = true);
    final sessions = await LanSyncService.instance.discoverPeerPlaybackSessions();
    if (!mounted) return;
    setState(() => _isDiscoveringPeerSessions = false);

    final playableSessions =
        sessions.where((s) {
          final hash = s.session['videoHash'];
          final position = s.session['positionMs'];
          return hash is String && hash.isNotEmpty && position is num && position.toInt() > 0;
        }).toList()..sort((a, b) {
          final aAt = (a.session['updatedAt'] as num?)?.toInt() ?? 0;
          final bAt = (b.session['updatedAt'] as num?)?.toInt() ?? 0;
          return bAt.compareTo(aAt);
        });

    if (playableSessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('home.continue_no_sessions'.tr())));
      return;
    }

    final selected = await showModalBottomSheet<LanPeerPlaybackSession>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('home.continue_select_session'.tr())),
            ...playableSessions.map((peer) {
              final title = (peer.session['title'] as String?)?.trim().isNotEmpty == true ? peer.session['title'] as String : 'Unknown';
              final position = (peer.session['positionMs'] as num).toInt();
              return ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${'home.continue_peer'.tr(args: [peer.deviceName])} · ${'home.continue_at'.tr(args: [_formatPositionText(position)])}'),
                trailing: TextButton(onPressed: () => Navigator.of(ctx).pop(peer), child: Text('home.continue_play_here'.tr())),
                onTap: () => Navigator.of(ctx).pop(peer),
              );
            }),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;

    final hash = selected.session['videoHash'] as String;
    final titleHint = selected.session['title'] as String?;
    final sizeBytesHint = (selected.session['sizeBytes'] as num?)?.toInt();
    final positionMs = (selected.session['positionMs'] as num).toInt();
    final audioTrack = selected.session['audioTrack'] as String?;
    final subtitleTrack = selected.session['subtitleTrack'] as String?;

    final library = context.read<LibraryCubit>().state.videos.where((v) => kSupportedVideoExtensions.contains(v.extension.toLowerCase())).toList();
    final localMatch = await _findVideoByHash(hash, library, titleHint: titleHint, sizeBytesHint: sizeBytesHint);

    if (localMatch == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('home.continue_unavailable_here'.tr())));
      return;
    }

    await PlayraStorage.bindVideoToHash(videoId: localMatch.id, hash: hash, title: localMatch.displayName, sizeBytes: localMatch.sizeBytes);
    await PlayraStorage.setResume(localMatch.id, positionMs);
    if (audioTrack != null && audioTrack.isNotEmpty) {
      await PlayraStorage.savePreferredAudioTrackKey(localMatch.id, audioTrack);
    }
    if (subtitleTrack != null && subtitleTrack.isNotEmpty) {
      await PlayraStorage.savePreferredSubtitleTrackKey(localMatch.id, subtitleTrack);
    }
    await PlayraStorage.addRecent(localMatch);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('home.continue_success'.tr(args: [localMatch.displayName]))));
    await context.read<PlayerLauncher>().launch(context, localMatch);
    _loadRecents();
  }

  bool _isSupportedVideoPath(String filePath) {
    return _supportedVideoExtensions.contains(p.extension(filePath).toLowerCase());
  }

  bool get _supportsDesktopDragDrop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  bool get _isMobileDevice {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  bool get _isRecentsExpanded => _expandedSections[_recentsSectionKey] ?? true;

  Widget _buildPosterThumbnail({required String? posterPath, required double width, required double height, required BorderRadius borderRadius, required Widget fallback}) {
    if (posterPath == null || posterPath.isEmpty) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.file(
        File(posterPath),
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: width.round() * 2,
        cacheHeight: height.round() * 2,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }

  Future<void> _handleHomeDrop(List<String> droppedPaths) async {
    String? firstVideoPath;

    for (final dropped in droppedPaths) {
      final type = FileSystemEntity.typeSync(dropped);
      if (type == FileSystemEntityType.directory) {
        await context.read<LibraryCubit>().addFolder(dropped);
      } else if (type == FileSystemEntityType.file && _isSupportedVideoPath(dropped)) {
        firstVideoPath ??= dropped;
      }
    }

    if (firstVideoPath != null && mounted) {
      final v = VideoItem(id: firstVideoPath, name: p.basename(firstVideoPath), uri: firstVideoPath, source: VideoSource.local);
      await _openVideo(v);
    }
  }

  Widget _buildMiniDropZone() {
    if (!_supportsDesktopDragDrop) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: DropTarget(
        onDragEntered: (_) => setState(() => _isHomeDragging = true),
        onDragExited: (_) => setState(() => _isHomeDragging = false),
        onDragDone: (details) async {
          setState(() => _isHomeDragging = false);
          await _handleHomeDrop(details.files.map((f) => f.path).toList());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _isHomeDragging
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45)
                : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _isHomeDragging ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor, width: _isHomeDragging ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(Icons.upload_file, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Přetáhněte sem video nebo složku', style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfiguredFoldersCard(List<String> folders) {
    if (folders.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_open, size: 18),
                  const SizedBox(width: 8),
                  Text('home.library'.tr(), style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: folders
                    .map((folder) => InputChip(avatar: const Icon(Icons.folder, size: 14), label: Text(_folderLabel(folder)), tooltip: folder, onPressed: () {}))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
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
        PopupMenuItem(value: 'movie_info', child: Text('Info o filmu')),
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
      case 'movie_info':
        await _showMovieInfoDialog(v);
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

  List<_LibraryEntry> _buildLibraryEntries(List<VideoItem> videos, String mode, Map<String, String?> posterById) {
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
        final headerPoster = items.map((v) => posterById[v.id]).firstWhere((p) => p != null, orElse: () => null);
        out.add(_LibraryEntry.header(sectionKey: key, title: labels[key] ?? key, count: items.length, expanded: expanded, smartGroup: true, posterPath: headerPoster));
        if (expanded) {
          out.addAll(items.map(_LibraryEntry.video));
        }
      }
      return out;
    }

    // structured - group by library folder (ignore nested subfolders)
    final byDir = <String, List<VideoItem>>{};
    final libraryFolders = PlayraStorage.getLibraryFolders().toSet();
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

  List<VideoItem> _filterDisplayVideos(List<VideoItem> videos) {
    return videos.where((v) => kSupportedVideoExtensions.contains(v.extension.toLowerCase())).toList();
  }

  VideoItem? _resolveLastWatchedInLibrary(List<VideoItem> videos) {
    if (_recents.isEmpty || videos.isEmpty) return null;
    for (final recent in _recents) {
      final matched = _resolveVideoInLibrarySync(recent, videos);
      if (matched != null) return matched;
    }
    return null;
  }

  String? _pathParent(String path) {
    final normalized = _normalizeFolderPath(path);
    final slash = normalized.lastIndexOf('/');
    if (slash <= 0) return null;
    return normalized.substring(0, slash);
  }

  bool _isFolderOnPathToLastWatched(String folderPath, String? lastWatchedVideoPath) {
    if (lastWatchedVideoPath == null) return false;
    final lastFolder = _pathParent(lastWatchedVideoPath);
    if (lastFolder == null) return false;
    return _isSameOrChildFolder(lastFolder, folderPath);
  }

  bool _isLastWatchedVideo(VideoItem video, String? lastWatchedVideoPath) {
    if (lastWatchedVideoPath == null) return false;
    return _normalizeFolderPath(video.uri) == _normalizeFolderPath(lastWatchedVideoPath);
  }

  double _videoProgress(VideoItem video, Map<String, int> resumeById, Map<String, int> durationById) {
    final resumeMs = resumeById[video.id] ?? 0;
    final durationMs = durationById[video.id] ?? 0;
    if (resumeMs <= 0 || durationMs <= 0) return 0;
    final ratio = resumeMs / durationMs;
    if (ratio >= 0.97) return 1;
    return ratio.clamp(0, 1).toDouble();
  }

  Widget _buildProgressPie(double progress, {double size = 18}) {
    final normalized = progress.clamp(0, 1).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ProgressPiePainter(
          progress: normalized,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          fillColor: Theme.of(context).colorScheme.primary,
          borderColor: Theme.of(context).dividerColor,
        ),
      ),
    );
  }

  String _normalizeFolderPath(String path) {
    var normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('smb://')) {
      final rest = normalized.substring(6).replaceAll(RegExp('/+'), '/');
      normalized = 'smb://$rest';
    } else {
      normalized = normalized.replaceAll(RegExp('/+'), '/');
    }
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _isSameOrChildFolder(String candidate, String folder) {
    final c = _normalizeFolderPath(candidate);
    final f = _normalizeFolderPath(folder);
    return c == f || c.startsWith('$f/');
  }

  String? _bestRootForVideo(VideoItem video, List<String> roots) {
    final uri = _normalizeFolderPath(video.uri);
    String? best;
    for (final root in roots) {
      final normalizedRoot = _normalizeFolderPath(root);
      if (_isSameOrChildFolder(uri, normalizedRoot)) {
        if (best == null || normalizedRoot.length > best.length) {
          best = normalizedRoot;
        }
      }
    }
    return best;
  }

  String _folderLabel(String path) {
    if (path.startsWith('smb://')) {
      final rest = path.substring(6);
      final parts = rest.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.length >= 2) return '${parts[0]}/${parts[1]}';
      if (parts.isNotEmpty) return parts.first;
      return path;
    }
    return p.basename(path);
  }

  String? _structuredParentFolder(String currentFolder, List<String> roots) {
    final normalizedCurrent = _normalizeFolderPath(currentFolder);
    final currentRoot = roots.where((r) => _isSameOrChildFolder(normalizedCurrent, r)).fold<String?>(null, (best, root) => best == null || root.length > best.length ? root : best);
    if (currentRoot == null) return null;
    if (normalizedCurrent == currentRoot) return null;

    final slash = normalizedCurrent.lastIndexOf('/');
    if (slash <= 0) return null;
    final parent = normalizedCurrent.substring(0, slash);
    return _isSameOrChildFolder(parent, currentRoot) ? parent : null;
  }

  List<_StructuredEntry> _buildStructuredEntries(List<VideoItem> videos, List<String> rootsInput, String? lastWatchedVideoPath) {
    final roots = rootsInput.map(_normalizeFolderPath).toSet().toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    var effectiveCurrent = _structuredCurrentFolder;
    if (effectiveCurrent != null) {
      final normalizedCurrent = _normalizeFolderPath(effectiveCurrent);
      final valid = roots.any((root) => _isSameOrChildFolder(normalizedCurrent, root));
      effectiveCurrent = valid ? normalizedCurrent : null;
      if (effectiveCurrent != _structuredCurrentFolder) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _structuredCurrentFolder = effectiveCurrent);
        });
      }
    }

    if (effectiveCurrent == null) {
      final counts = <String, int>{for (final r in roots) r: 0};
      for (final v in videos) {
        final root = _bestRootForVideo(v, roots);
        if (root != null) counts[root] = (counts[root] ?? 0) + 1;
      }

      return roots
          .map(
            (root) =>
                _StructuredEntry.folder(path: root, title: _folderLabel(root), count: counts[root] ?? 0, highlighted: _isFolderOnPathToLastWatched(root, lastWatchedVideoPath)),
          )
          .where((entry) => entry.count > 0)
          .toList();
    }

    final folderCounts = <String, int>{};
    final files = <VideoItem>[];
    final currentPrefix = '$effectiveCurrent/';

    for (final v in videos) {
      final uri = _normalizeFolderPath(v.uri);
      if (!_isSameOrChildFolder(uri, effectiveCurrent)) continue;

      if (uri.startsWith(currentPrefix)) {
        final relative = uri.substring(currentPrefix.length);
        if (relative.isEmpty) continue;
        final slash = relative.indexOf('/');
        if (slash < 0) {
          files.add(v);
        } else {
          final childName = relative.substring(0, slash);
          final childPath = '$effectiveCurrent/$childName';
          folderCounts[childPath] = (folderCounts[childPath] ?? 0) + 1;
        }
      }
    }

    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final folders = folderCounts.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final parent = _structuredParentFolder(effectiveCurrent, roots);

    final entries = <_StructuredEntry>[];
    entries.add(_StructuredEntry.parent(path: parent, highlighted: false));
    entries.addAll(
      folders.map((e) => _StructuredEntry.folder(path: e.key, title: p.basename(e.key), count: e.value, highlighted: _isFolderOnPathToLastWatched(e.key, lastWatchedVideoPath))),
    );
    entries.addAll(files.map((v) => _StructuredEntry.video(v, highlighted: _isLastWatchedVideo(v, lastWatchedVideoPath))));
    return entries;
  }

  Future<void> _showMovieInfoDialog(VideoItem video) async {
    final lookup = MediaLookupService(TmdbService());
    final language = context.locale.languageCode;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Info o filmu'),
        content: SizedBox(
          width: 760,
          child: FutureBuilder<MediaLookupResult?>(
            future: () async {
              final hash = await VideoHashService.hashForVideo(video);
              if (hash != null) {
                await PlayraStorage.bindVideoToHash(videoId: video.id, hash: hash, title: video.displayName, sizeBytes: video.sizeBytes);
              }
              return lookup.lookupForFile(video.uri, language, videoHash: hash);
            }(),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
              }

              final result = snapshot.data;
              if (result == null) {
                return SizedBox(height: 120, child: Center(child: Text('Informace o filmu nebyly nalezeny.')));
              }

              final media = result.mediaInfo;
              final rating = media.voteAverage?.toStringAsFixed(1) ?? '-';
              final year = (media.releaseDate != null && media.releaseDate!.length >= 4) ? media.releaseDate!.substring(0, 4) : '-';

              return SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (media.posterPath != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          media.posterUrl,
                          width: 140,
                          height: 210,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(width: 140, height: 210, color: Theme.of(context).colorScheme.surfaceContainerHighest),
                        ),
                      )
                    else
                      Container(
                        width: 140,
                        height: 210,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.movie, size: 48),
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(media.title, style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 6),
                          Text('${media.type == MediaType.movie ? 'Film' : 'Seriál'} • $year • TMDB $rating/10'),
                          if (media.genres.isNotEmpty) ...[const SizedBox(height: 6), Text(media.genres.join(', '))],
                          const SizedBox(height: 12),
                          Text(media.overview?.trim().isNotEmpty == true ? media.overview!.trim() : 'Bez popisu.'),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('common.ok'.tr()))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerSettings = PlayraStorage.getPlayerSettings();
    final libraryMode = playerSettings.libraryViewMode;
    final visualMode = playerSettings.libraryVisualMode;
    final canSyncAcrossLan = _canSyncAcrossLan();

    return Scaffold(
      appBar: AppBar(
        title: Text('app.title'.tr()),
        actions: [
          if (canSyncAcrossLan)
            IconButton(
              tooltip: 'home.sync_now'.tr(),
              icon: _isSyncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
              onPressed: _isSyncing ? null : _runLanSync,
            ),
          if (canSyncAcrossLan)
            IconButton(
              tooltip: 'home.continue_from_device'.tr(),
              icon: _isDiscoveringPeerSessions ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
              onPressed: _isDiscoveringPeerSessions ? null : _continueFromPeerPlayback,
            ),
          if (_isMobileDevice)
            IconButton(
              tooltip: 'downloads.title'.tr(),
              icon: const Icon(Icons.download_for_offline),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
            ),
          IconButton(
            tooltip: 'home.settings'.tr(),
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          if (state.loading) return const Center(child: CircularProgressIndicator());

          final displayVideos = _filterDisplayVideos(state.videos);
          final resumeById = PlayraStorage.getResumeMap();
          final durationById = PlayraStorage.getVideoDurationMap();
          final posterById = PlayraStorage.getRecentPosterPathMap([...displayVideos, ..._recents]);
          final hasFolders = state.folders.isNotEmpty;
          final hasLibrary = hasFolders && displayVideos.isNotEmpty;
          final showRecents = _recents.isNotEmpty;
          final libraryEntries = _buildLibraryEntries(displayVideos, libraryMode, posterById);
          final lastWatchedInLibrary = _resolveLastWatchedInLibrary(displayVideos);
          final lastWatchedPath = lastWatchedInLibrary != null ? _normalizeFolderPath(lastWatchedInLibrary.uri) : null;
          final structuredEntries = libraryMode == 'structured' ? _buildStructuredEntries(displayVideos, state.folders, lastWatchedPath) : const <_StructuredEntry>[];
          final gridVideos = _gridVideosForMode(displayVideos, libraryMode);

          if (!hasLibrary && !showRecents) {
            if (state.folders.isEmpty) {
              return Column(
                children: [
                  _buildMiniDropZone(),
                  _buildConfiguredFoldersCard(state.folders),
                  Expanded(
                    child: _emptyState(
                      icon: Icons.folder_open,
                      title: 'home.empty_title'.tr(),
                      subtitle: 'home.empty_subtitle'.tr(),
                      actionLabel: 'home.add_folder'.tr(),
                      onAction: _addFolder,
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                _buildMiniDropZone(),
                _buildConfiguredFoldersCard(state.folders),
                Expanded(
                  child: _emptyState(
                    icon: Icons.movie_outlined,
                    title: 'home.no_videos_title'.tr(),
                    subtitle: 'home.no_videos_subtitle'.tr(),
                    actionLabel: 'settings.refresh_library'.tr(),
                    onAction: _refreshLibrary,
                  ),
                ),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await _refreshLibrary();
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildMiniDropZone()),
                SliverToBoxAdapter(child: _buildConfiguredFoldersCard(state.folders)),
                if (showRecents) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Row(
                        children: [
                          const Icon(Icons.history, size: 18),
                          const SizedBox(width: 8),
                          Text('home.recently_played'.tr(), style: Theme.of(context).textTheme.titleSmall),
                          IconButton(
                            tooltip: _isRecentsExpanded ? 'home.collapse_recent'.tr() : 'home.expand_recent'.tr(),
                            icon: Icon(_isRecentsExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
                            onPressed: () => _setSectionExpanded(_recentsSectionKey, !_isRecentsExpanded),
                          ),
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
                  if (_isRecentsExpanded)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 140,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _recents.length,
                          itemBuilder: (_, i) => _buildRecentCard(_recents[i], posterById[_recents[i].id], displayVideos),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: Divider(height: 24)),
                ],
                if (hasFolders && !displayVideos.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _emptyState(
                        icon: Icons.movie_outlined,
                        title: 'home.no_videos_title'.tr(),
                        subtitle: 'home.no_videos_subtitle'.tr(),
                        actionLabel: 'home.add_folder'.tr(),
                        onAction: _addFolder,
                      ),
                    ),
                  ),
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
                    itemCount: libraryMode == 'structured' ? structuredEntries.length : libraryEntries.length,
                    itemBuilder: (context, i) {
                      if (libraryMode == 'structured') {
                        final entry = structuredEntries[i];
                        if (entry.isParent) {
                          return ListTile(
                            tileColor: entry.highlighted ? Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.38) : null,
                            leading: const Icon(Icons.arrow_upward),
                            title: const Text('..'),
                            onTap: () => setState(() => _structuredCurrentFolder = entry.path),
                          );
                        }

                        if (entry.isFolder) {
                          return ListTile(
                            tileColor: entry.highlighted ? Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.38) : null,
                            leading: const Icon(Icons.folder_open),
                            title: Text(entry.title ?? '', style: entry.highlighted ? const TextStyle(fontWeight: FontWeight.w700) : null),
                            subtitle: Text('${entry.count}'),
                            onTap: () => setState(() => _structuredCurrentFolder = entry.path),
                          );
                        }

                        final v = entry.video!;
                        final resume = resumeById[v.id];
                        final progress = _videoProgress(v, resumeById, durationById);
                        final posterPath = posterById[v.id];
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onSecondaryTapDown: (details) => _showVideoContextMenu(v, details.globalPosition),
                          child: ListTile(
                            tileColor: entry.highlighted ? Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.38) : null,
                            leading: _buildPosterThumbnail(
                              posterPath: posterPath,
                              width: 28,
                              height: 42,
                              borderRadius: BorderRadius.circular(4),
                              fallback: const Icon(Icons.movie),
                            ),
                            title: Text(v.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [if (v.folder != null) v.folder!, if (v.sizeBytes != null) _formatSize(v.sizeBytes!), if (resume != null) 'home.resume_marker'.tr()].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildProgressPie(progress),
                                const SizedBox(width: 8),
                                IconButton(tooltip: 'home.view_info'.tr(), icon: const Icon(Icons.more_vert, size: 20), onPressed: () => _showVideoMenu(v)),
                              ],
                            ),
                            onTap: () => _openVideo(v),
                            onLongPress: () => _showVideoMenu(v),
                          ),
                        );
                      }

                      final entry = libraryEntries[i];
                      if (entry.isHeader) {
                        return InkWell(
                          onTap: entry.smartGroup == true ? () => _setSectionExpanded(entry.sectionKey!, !(entry.expanded ?? false)) : null,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            child: Row(
                              children: [
                                Icon(entry.smartGroup == true ? ((entry.expanded ?? false) ? Icons.expand_more : Icons.chevron_right) : Icons.folder_open, size: 18),
                                const SizedBox(width: 6),
                                if (entry.posterPath != null)
                                  _buildPosterThumbnail(
                                    posterPath: entry.posterPath,
                                    width: 20,
                                    height: 28,
                                    borderRadius: BorderRadius.circular(4),
                                    fallback: Icon(entry.smartGroup == true ? Icons.auto_awesome : Icons.folder_open, size: 16),
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
                      final resume = resumeById[v.id];
                      final progress = _videoProgress(v, resumeById, durationById);
                      final posterPath = posterById[v.id];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapDown: (details) => _showVideoContextMenu(v, details.globalPosition),
                        child: ListTile(
                          leading: _buildPosterThumbnail(posterPath: posterPath, width: 28, height: 42, borderRadius: BorderRadius.circular(4), fallback: const Icon(Icons.movie)),
                          title: Text(v.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [if (v.folder != null) v.folder!, if (v.sizeBytes != null) _formatSize(v.sizeBytes!), if (resume != null) 'home.resume_marker'.tr()].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildProgressPie(progress),
                              const SizedBox(width: 8),
                              IconButton(tooltip: 'home.view_info'.tr(), icon: const Icon(Icons.more_vert, size: 20), onPressed: () => _showVideoMenu(v)),
                              Icon(resume != null ? Icons.history : Icons.chevron_right, size: 20),
                            ],
                          ),
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
                        final posterPath = posterById[v.id];
                        return InkWell(
                          onTap: () => _openVideo(v, libraryMode: libraryMode, allVideos: displayVideos),
                          onSecondaryTapDown: (d) => _showVideoContextMenu(v, d.globalPosition),
                          onLongPress: () => _showVideoMenu(v),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _buildPosterThumbnail(
                                        posterPath: posterPath,
                                        width: 160,
                                        height: 240,
                                        borderRadius: BorderRadius.circular(8),
                                        fallback: Container(
                                          color: Colors.grey[300],
                                          child: const Icon(Icons.movie, size: 32, color: Colors.grey),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Material(
                                          color: Colors.black45,
                                          borderRadius: BorderRadius.circular(14),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(14),
                                            onTap: () => _showVideoMenu(v),
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(Icons.more_vert, color: Colors.white, size: 16),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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

  Widget _buildRecentCard(VideoItem v, String? posterPath, List<VideoItem> displayVideos) {
    return GestureDetector(
      onTap: () => _openRecentVideo(v, displayVideos),
      onSecondaryTapDown: (d) => _showRecentContextMenu(v, d.globalPosition),
      onLongPress: () => _showVideoMenu(v),
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
                    _buildPosterThumbnail(
                      posterPath: posterPath,
                      width: 100,
                      height: 136,
                      borderRadius: BorderRadius.circular(8),
                      fallback: Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.movie, size: 40, color: Colors.grey),
                      ),
                    ),
                    const Positioned(top: 4, right: 4, child: Icon(Icons.play_circle_outline, color: Colors.white, size: 22)),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showVideoMenu(v),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.more_vert, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ),
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
        child: SingleChildScrollView(
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
                leading: const Icon(Icons.movie_outlined),
                title: const Text('Info o filmu'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showMovieInfoDialog(v);
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
              if (_isMobileDevice && v.source == VideoSource.smb)
                ListTile(
                  leading: const Icon(Icons.download),
                  title: Text('downloads.download_to_device'.tr()),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _downloadSmbVideo(v);
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
      ),
    );
  }

  Future<void> _downloadSmbVideo(VideoItem v) async {
    final proxyVideo = await context.read<PlayerLauncher>().resolveForHash(context, v);
    if (!mounted) return;
    if (proxyVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('downloads.download_error'.tr(args: ['Could not resolve SMB URL']))));
      return;
    }

    final token = DownloadCancellationToken();
    String? received;
    String? total;
    double? progress;
    void Function(void Function())? refreshDialog;
    var lastDialogUpdateMs = 0;
    var isDialogOpen = true;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            refreshDialog = setDialogState;
            return AlertDialog(
              title: Text('downloads.downloading'.tr()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 12),
                  Text(received != null && total != null ? '$received / $total' : v.displayName, style: const TextStyle(fontSize: 13), textAlign: TextAlign.center),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    token.cancel();
                    Navigator.of(ctx).pop();
                  },
                  child: Text('common.cancel'.tr()),
                ),
              ],
            );
          },
        ),
      ).whenComplete(() => isDialogOpen = false),
    );

    try {
      await SmbDownloadService.downloadVideo(
        videoProxyUrl: proxyVideo.uri,
        videoName: v.name,
        onProgress: (r, t, name) {
          received = SmbDownloadService.formatBytes(r);
          total = t > 0 ? SmbDownloadService.formatBytes(t) : '?';
          progress = t > 0 ? (r / t).clamp(0.0, 1.0) : null;

          final now = DateTime.now().millisecondsSinceEpoch;
          if (refreshDialog != null && (now - lastDialogUpdateMs >= 100 || t > 0 && r >= t)) {
            lastDialogUpdateMs = now;
            refreshDialog!.call(() {});
          }
        },
        cancellationToken: token,
      );
      if (isDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;
      if (!token.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('downloads.download_done'.tr(args: [v.displayName]))));
      }
    } catch (e) {
      if (isDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;
      if (!token.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('downloads.download_error'.tr(args: [e.toString()]))));
      }
    }
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

class _StructuredEntry {
  final String? path;
  final String? title;
  final int count;
  final VideoItem? video;
  final bool isParent;
  final bool highlighted;

  bool get isFolder => !isParent && path != null && video == null;

  const _StructuredEntry.parent({required this.path, this.highlighted = false}) : title = '..', count = 0, video = null, isParent = true;

  const _StructuredEntry.folder({required this.path, required this.title, required this.count, this.highlighted = false}) : video = null, isParent = false;

  const _StructuredEntry.video(this.video, {this.highlighted = false}) : path = null, title = null, count = 0, isParent = false;
}

class _ProgressPiePainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color fillColor;
  final Color borderColor;

  const _ProgressPiePainter({required this.progress, required this.backgroundColor, required this.fillColor, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;

    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawCircle(center, radius, bgPaint);

    if (progress > 0) {
      final fillPaint = Paint()..color = fillColor;
      final sweep = 3.141592653589793 * 2 * progress;
      canvas.drawArc(rect, -3.141592653589793 / 2, sweep, true, fillPaint);
    }

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius - 0.5, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ProgressPiePainter oldDelegate) {
    return progress != oldDelegate.progress || backgroundColor != oldDelegate.backgroundColor || fillColor != oldDelegate.fillColor || borderColor != oldDelegate.borderColor;
  }
}
