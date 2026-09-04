import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/video_item.dart';
import '../services/playra_storage.dart';
import '../services/smb_download_service.dart';
import '../widgets/empty_state.dart';
import 'player_launcher.dart';

/// Screen for managing videos downloaded from an SMB share to this device.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<DownloadedFile> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final files = await SmbDownloadService.listDownloads();
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  Future<void> _confirmDelete(DownloadedFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('downloads.delete_title'.tr()),
        content: Text('downloads.delete_confirm'.tr(args: [file.displayName])),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.cancel'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('downloads.delete'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await SmbDownloadService.deleteDownload(file.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('downloads.deleted'.tr(args: [file.displayName]))));
    await _refresh();
  }

  Future<void> _openLocalFile(DownloadedFile file) async {
    final video = VideoItem(id: file.path, name: file.name, uri: file.path, source: VideoSource.local, sizeBytes: file.sizeBytes);
    await PlayraStorage.addRecent(video);
    if (!mounted) return;
    await context.read<PlayerLauncher>().launch(context, video);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('downloads.title'.tr()),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'downloads.refresh'.tr(), onPressed: _refresh)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
          ? EmptyState(icon: Icons.download_done, iconSize: 64, title: 'downloads.empty'.tr())
          : RefreshIndicator(onRefresh: _refresh, child: _buildList()),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      itemCount: _files.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final file = _files[index];
        return ListTile(
          leading: const Icon(Icons.movie),
          title: Text(file.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(file.formattedSize),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.play_circle_outline), tooltip: 'downloads.play'.tr(), onPressed: () => _openLocalFile(file)),
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'downloads.delete'.tr(), color: Colors.red, onPressed: () => _confirmDelete(file)),
            ],
          ),
          onTap: () => _openLocalFile(file),
        );
      },
    );
  }
}
