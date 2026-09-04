import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../bloc/library/library_cubit.dart';
import '../models/server_connection.dart';
import '../services/playra_storage.dart';
import 'server_browser_screen.dart';

class LibraryManagementScreen extends StatefulWidget {
  const LibraryManagementScreen({super.key});

  @override
  State<LibraryManagementScreen> createState() => _LibraryManagementScreenState();
}

class _LibraryManagementScreenState extends State<LibraryManagementScreen> {
  static const Set<String> _supportedVideoExtensions = {'.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.mpg', '.mpeg', '.3gp'};

  bool _isDragging = false;

  bool get _supportsDesktopDragDrop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  bool _isSupportedVideoPath(String filePath) {
    return _supportedVideoExtensions.contains(p.extension(filePath).toLowerCase());
  }

  Future<void> _addLibraryFolder() async {
    final smbServers = PlayraStorage.getServers().where((s) => s.type == ServerType.smb).toList();
    if (smbServers.isEmpty) {
      await _addLocalLibraryFolder();
      return;
    }

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
      await _addSmbLibraryFolder();
      return;
    }

    if (source == 'local') {
      await _addLocalLibraryFolder();
    }
  }

  Future<void> _addLocalLibraryFolder() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected == null || !mounted) return;
    await context.read<LibraryCubit>().addFolder(selected);
  }

  Future<void> _addSmbLibraryFolder() async {
    final smbServers = PlayraStorage.getServers().where((s) => s.type == ServerType.smb).toList();
    if (smbServers.isEmpty || !mounted) return;

    final selectedServer = await showModalBottomSheet<ServerConnection>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in smbServers)
              ListTile(leading: const Icon(Icons.lan), title: Text(s.name), subtitle: Text(s.host), onTap: () => Navigator.of(ctx).pop(s)),
          ],
        ),
      ),
    );

    if (selectedServer == null || !mounted) return;
    final selectedSmbFolderUri = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => ServerBrowserScreen(server: selectedServer, pickFolderMode: true)));
    if (selectedSmbFolderUri == null || selectedSmbFolderUri.isEmpty || !mounted) return;
    await context.read<LibraryCubit>().addFolder(selectedSmbFolderUri);
  }

  Future<void> _handleDrop(List<String> droppedPaths) async {
    final existingFolders = PlayraStorage.getLibraryFolders().map((f) => f.toLowerCase()).toSet();
    final toAdd = <String>{};

    for (final dropped in droppedPaths) {
      final type = FileSystemEntity.typeSync(dropped);
      if (type == FileSystemEntityType.directory) {
        toAdd.add(dropped);
        continue;
      }

      if (type == FileSystemEntityType.file && _isSupportedVideoPath(dropped)) {
        toAdd.add(p.dirname(dropped));
      }
    }

    var addedCount = 0;
    for (final folder in toAdd) {
      if (existingFolders.contains(folder.toLowerCase())) continue;
      await context.read<LibraryCubit>().addFolder(folder);
      addedCount += 1;
    }

    if (!mounted) return;
    if (addedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('settings.library_drop_added'.tr(args: [addedCount.toString()]))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.library_management_title'.tr())),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          final folders = state.folders;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              if (_supportsDesktopDragDrop)
                DropTarget(
                  onDragEntered: (_) => setState(() => _isDragging = true),
                  onDragExited: (_) => setState(() => _isDragging = false),
                  onDragDone: (details) async {
                    setState(() => _isDragging = false);
                    await _handleDrop(details.files.map((f) => f.path).toList());
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: _isDragging
                          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45)
                          : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isDragging ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                        width: _isDragging ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.upload_file, size: 20, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text('settings.library_drop_hint'.tr(), style: Theme.of(context).textTheme.bodyMedium)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.create_new_folder),
                title: Text('home.add_folder'.tr()),
                subtitle: Text('settings.library_management_hint'.tr()),
                onTap: _addLibraryFolder,
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text('settings.refresh_library'.tr()),
                subtitle: Text('settings.refresh_library_hint'.tr()),
                onTap: () => context.read<LibraryCubit>().refresh(),
              ),
              const Divider(height: 22),
              Text('settings.section_library'.tr(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (folders.isEmpty) ListTile(title: Text('settings.no_folders'.tr()), leading: const Icon(Icons.folder_off)),
              ...folders.map(
                (folder) => ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(folder, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => context.read<LibraryCubit>().removeFolder(folder)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
