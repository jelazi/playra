import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../bloc/library/library_cubit.dart';
import '../models/video_item.dart';
import '../services/playra_storage.dart';
import '../services/video_name_parser.dart';
import 'media_info_screen.dart';
import 'player_launcher.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';

/// Main Playra home screen — the local video library.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<VideoItem> _recents = [];

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
        final key = parsed.isTV ? 'tv:${parsed.cleanName.toLowerCase()}' : 'dir:${p.dirname(v.uri).toLowerCase()}';
        labels[key] = parsed.isTV ? parsed.cleanName : (v.folder ?? p.basename(p.dirname(v.uri)));
        groups.putIfAbsent(key, () => []).add(v);
      }

      final keys = groups.keys.toList()..sort((a, b) => (labels[a] ?? a).toLowerCase().compareTo((labels[b] ?? b).toLowerCase()));

      final out = <_LibraryEntry>[];
      for (final k in keys) {
        final items = groups[k]!;
        items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        out.add(_LibraryEntry.header(labels[k] ?? k, items.length));
        out.addAll(items.map(_LibraryEntry.video));
      }
      return out;
    }

    // structured
    final byDir = <String, List<VideoItem>>{};
    for (final v in videos) {
      final dir = p.dirname(v.uri);
      byDir.putIfAbsent(dir, () => []).add(v);
    }
    final dirs = byDir.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final out = <_LibraryEntry>[];
    for (final dir in dirs) {
      final items = byDir[dir]!;
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      out.add(_LibraryEntry.header(p.basename(dir), items.length));
      out.addAll(items.map(_LibraryEntry.video));
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryCubit>().load();
      _loadRecents();
    });
  }

  void _loadRecents() {
    if (mounted) setState(() => _recents = PlayraStorage.getRecent());
  }

  Future<void> _openVideo(VideoItem v) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MediaInfoRoute(video: v)));
    // Refresh recents when returning.
    _loadRecents();
  }

  Future<void> _addFolder() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected != null) {
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

  @override
  Widget build(BuildContext context) {
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
      floatingActionButton: FloatingActionButton.extended(onPressed: _addFolder, icon: const Icon(Icons.create_new_folder), label: Text('home.add_folder'.tr())),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          if (state.loading) return const Center(child: CircularProgressIndicator());

          final hasLibrary = state.folders.isNotEmpty && state.videos.isNotEmpty;
          final showRecents = _recents.isNotEmpty;
          final libraryMode = PlayraStorage.getPlayerSettings().libraryViewMode;
          final libraryEntries = _buildLibraryEntries(state.videos, libraryMode);

          if (!hasLibrary && !showRecents) {
            if (state.folders.isEmpty) {
              return _emptyState(icon: Icons.folder_open, title: 'home.empty_title'.tr(), subtitle: 'home.empty_subtitle'.tr());
            }
            return _emptyState(icon: Icons.movie_outlined, title: 'home.no_videos_title'.tr(), subtitle: 'home.no_videos_subtitle'.tr());
          }

          return RefreshIndicator(
            onRefresh: () async {
              await context.read<LibraryCubit>().load();
              _loadRecents();
            },
            child: CustomScrollView(
              slivers: [
                // --- Recently played section ---
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

                // --- Library header ---
                if (hasLibrary)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        children: [
                          const Icon(Icons.video_library, size: 18),
                          const SizedBox(width: 8),
                          Text('home.library'.tr(), style: Theme.of(context).textTheme.titleSmall),
                        ],
                      ),
                    ),
                  ),

                // --- Library items ---
                if (hasLibrary)
                  SliverList.builder(
                    itemCount: libraryEntries.length,
                    itemBuilder: (context, i) {
                      final entry = libraryEntries[i];
                      if (entry.isHeader) {
                        return Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_open, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${entry.headerTitle} (${entry.count})', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                              ),
                            ],
                          ),
                        );
                      }

                      final v = entry.video!;
                      final resume = PlayraStorage.getResume(v.id);
                      return ListTile(
                        leading: const Icon(Icons.movie),
                        title: Text(v.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [if (v.folder != null) v.folder!, if (v.sizeBytes != null) _formatSize(v.sizeBytes!), if (resume != null) 'home.resume_marker'.tr()].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: resume != null ? const Icon(Icons.history, size: 20) : const Icon(Icons.chevron_right),
                        onTap: () => _openVideo(v),
                        onLongPress: () => _showVideoMenu(v),
                      );
                    },
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
                        errorBuilder: (_, __, ___) => Container(
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

  Widget _emptyState({required IconData icon, required String title, required String subtitle}) {
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
              title: Text('home.view_info'.tr()),
              onTap: () {
                Navigator.of(ctx).pop();
                _openVideo(v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text('home.play'.tr()),
              onTap: () async {
                Navigator.of(ctx).pop();
                await PlayraStorage.addRecent(v);
                if (ctx.mounted) await context.read<PlayerLauncher>().launch(context, v);
                _loadRecents();
              },
            ),
            if (PlayraStorage.getResume(v.id) != null)
              ListTile(
                leading: const Icon(Icons.delete_sweep),
                title: Text('home.clear_resume'.tr()),
                onTap: () async {
                  await PlayraStorage.clearResume(v.id);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (mounted) setState(() {});
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
  final String? headerTitle;
  final int count;
  final VideoItem? video;

  bool get isHeader => headerTitle != null;

  const _LibraryEntry.header(this.headerTitle, this.count) : video = null;
  const _LibraryEntry.video(this.video) : headerTitle = null, count = 0;
}

/// Main Playra home screen — the local video library.
