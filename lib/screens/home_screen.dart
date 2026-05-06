import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/library/library_cubit.dart';
import '../models/video_item.dart';
import '../services/playra_storage.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryCubit>().load();
    });
  }

  Future<void> _addFolder() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected != null) {
      await context.read<LibraryCubit>().addFolder(selected);
    }
  }

  Future<void> _openSingleFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    final v = VideoItem(
      id: file.path!,
      name: file.name,
      uri: file.path!,
      source: VideoSource.local,
    );
    await context.read<PlayerLauncher>().launch(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('app.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'home.open_file'.tr(),
            icon: const Icon(Icons.video_file),
            onPressed: _openSingleFile,
          ),
          IconButton(
            tooltip: 'home.servers'.tr(),
            icon: const Icon(Icons.dns),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ServersScreen()),
            ),
          ),
          IconButton(
            tooltip: 'home.settings'.tr(),
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFolder,
        icon: const Icon(Icons.create_new_folder),
        label: Text('home.add_folder'.tr()),
      ),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          if (state.loading) return const Center(child: CircularProgressIndicator());

          if (state.folders.isEmpty) {
            return _emptyState(
              icon: Icons.folder_open,
              title: 'home.empty_title'.tr(),
              subtitle: 'home.empty_subtitle'.tr(),
            );
          }

          if (state.videos.isEmpty) {
            return _emptyState(
              icon: Icons.movie_outlined,
              title: 'home.no_videos_title'.tr(),
              subtitle: 'home.no_videos_subtitle'.tr(),
            );
          }

          return RefreshIndicator(
            onRefresh: () => context.read<LibraryCubit>().load(),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: state.videos.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final v = state.videos[i];
                final resume = PlayraStorage.getResume(v.id);
                return ListTile(
                  leading: const Icon(Icons.movie),
                  title: Text(v.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      if (v.folder != null) v.folder!,
                      if (v.sizeBytes != null) _formatSize(v.sizeBytes!),
                      if (resume != null) 'home.resume_marker'.tr(),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: resume != null
                      ? const Icon(Icons.history, size: 20)
                      : const Icon(Icons.play_arrow),
                  onTap: () => context.read<PlayerLauncher>().launch(context, v),
                  onLongPress: () => _showVideoMenu(v),
                );
              },
            ),
          );
        },
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
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
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
              leading: const Icon(Icons.play_arrow),
              title: Text('home.play'.tr()),
              onTap: () {
                Navigator.of(ctx).pop();
                context.read<PlayerLauncher>().launch(context, v);
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
