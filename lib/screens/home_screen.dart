import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/library/library_cubit.dart';
import '../models/video_item.dart';
import '../services/playra_storage.dart';
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
    final result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
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
                  SliverList.separated(
                    itemCount: state.videos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final v = state.videos[i];
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

/// Main Playra home screen — the local video library.
