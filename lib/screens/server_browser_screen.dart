import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/server_connection.dart';
import '../models/video_item.dart';
import '../services/smb_browser_service.dart';
import 'media_info_screen.dart';
import 'player_launcher.dart';

/// Browse files on a remote server (currently SMB-only).
class ServerBrowserScreen extends StatefulWidget {
  final ServerConnection server;
  final String? initialPath;
  final bool pickFolderMode;

  const ServerBrowserScreen({super.key, required this.server, this.initialPath, this.pickFolderMode = false});

  @override
  State<ServerBrowserScreen> createState() => _ServerBrowserScreenState();
}

class _ServerBrowserScreenState extends State<ServerBrowserScreen> {
  late String _path;
  bool _loading = false;
  String? _error;
  List<SmbEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath ?? widget.server.path ?? '/';
    _load();
  }

  Future<void> _load() async {
    if (widget.server.type != ServerType.smb) {
      setState(() => _error = 'servers.only_smb_supported'.tr());
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final browser = context.read<PlayerLauncher>().browser;
      final rawEntries = await browser.listPath(widget.server, _path);
      final entries = rawEntries.where((entry) {
        if (browser.isHiddenEntry(entry.name)) return false;
        if (entry.isDirectory) return true;
        return browser.isVideo(entry.name);
      }).toList();
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _navigateTo(String newPath) {
    setState(() => _path = newPath);
    _load();
  }

  void _navigateUp() {
    if (_path == '/' || _path.isEmpty) return;
    final segments = _path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      _navigateTo('/');
    } else {
      segments.removeLast();
      _navigateTo(segments.isEmpty ? '/' : '/${segments.join('/')}');
    }
  }

  String _currentSmbFolderUri() => 'smb://${widget.server.id}$_path';

  void _selectCurrentFolder() {
    Navigator.of(context).pop(_currentSmbFolderUri());
  }

  Future<void> _openVideoInfo(VideoItem video) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MediaInfoRoute(video: video)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.server.name),
        actions: [
          if (widget.pickFolderMode) IconButton(tooltip: 'home.add_folder'.tr(), icon: const Icon(Icons.create_new_folder), onPressed: _selectCurrentFolder),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(_path, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text('common.retry'.tr())),
            ],
          ),
        ),
      );
    }

    final showUp = _path != '/' && _path.isNotEmpty;
    final itemCount = _entries.length + (showUp ? 1 : 0);

    return ListView.separated(
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        if (showUp && i == 0) {
          return ListTile(leading: const Icon(Icons.arrow_upward), title: Text('servers.up'.tr()), onTap: _navigateUp);
        }
        final e = _entries[i - (showUp ? 1 : 0)];
        final browser = context.read<PlayerLauncher>().browser;
        final isVideo = !e.isDirectory && browser.isVideo(e.name);

        return ListTile(
          leading: Icon(e.isDirectory ? Icons.folder : (isVideo ? Icons.movie : Icons.insert_drive_file), color: e.isDirectory ? Colors.amber[700] : null),
          title: Text(e.name),
          subtitle: e.sizeBytes != null ? Text(_formatSize(e.sizeBytes!)) : null,
          enabled: e.isDirectory || (isVideo && !widget.pickFolderMode),
          trailing: isVideo
              ? IconButton(
                  tooltip: 'home.view_info'.tr(),
                  icon: const Icon(Icons.info_outline, size: 20),
                  onPressed: () {
                    if (widget.pickFolderMode) return;
                    final video = browser.entryToVideoItem(widget.server, e);
                    _openVideoInfo(video);
                  },
                )
              : (widget.pickFolderMode && e.isDirectory
                    ? IconButton(
                        tooltip: 'home.add_folder'.tr(),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: () => Navigator.of(context).pop('smb://${widget.server.id}${e.path}'),
                      )
                    : null),
          onTap: () {
            if (e.isDirectory) {
              _navigateTo(e.path);
            } else if (isVideo && !widget.pickFolderMode) {
              final video = browser.entryToVideoItem(widget.server, e);
              _openVideoInfo(video);
            }
          },
        );
      },
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
