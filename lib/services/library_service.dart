import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/server_connection.dart';
import '../models/video_item.dart';
import 'playra_storage.dart';
import 'smb_browser_service.dart';

/// Scans configured local folders for video files.
class LibraryService {
  static const int _minVideoBytes = 256 * 1024;
  static const Duration _folderScanTimeout = Duration(seconds: 12);
  static const Duration _mountedVolumeScanTimeout = Duration(minutes: 2);
  final SmbBrowserService _smbBrowser = SmbBrowserService();

  Duration _scanTimeoutForFolder(String folderPath) {
    if (folderPath.startsWith('smb://')) {
      return _mountedVolumeScanTimeout;
    }

    if (Platform.isMacOS && folderPath.startsWith('/Volumes/')) {
      return _mountedVolumeScanTimeout;
    }

    return _folderScanTimeout;
  }

  /// List videos in a single directory (non-recursive by default; set [recursive] to walk subtree).
  Future<List<VideoItem>> listFolder(String folderPath, {bool recursive = false}) async {
    if (folderPath.startsWith('smb://')) {
      return _listSmbFolder(folderPath, recursive: recursive);
    }

    final dir = Directory(folderPath);
    if (!await dir.exists()) return const [];

    final files = <File>[];
    try {
      await for (final entity in dir.list(recursive: recursive, followLinks: false)) {
        if (entity is File) {
          final base = p.basename(entity.path);
          if (base.startsWith('.')) continue;
          final ext = p.extension(entity.path).toLowerCase().replaceFirst('.', '');
          if (kSupportedVideoExtensions.contains(ext)) {
            final stat = await entity.stat();
            if (stat.size < _minVideoBytes) continue;
            files.add(entity);
          }
        }
      }
    } catch (_) {
      // ignore permission errors etc.
    }

    files.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));

    return files.map((f) {
      final stat = f.statSync();
      return VideoItem(
        id: f.path,
        name: p.basename(f.path),
        uri: f.path,
        source: VideoSource.local,
        sizeBytes: stat.size,
        modified: stat.modified,
        folder: p.basename(p.dirname(f.path)),
      );
    }).toList();
  }

  (String, String)? _parseSmbFolderUri(String folderUri) {
    if (!folderUri.startsWith('smb://')) return null;
    final rest = folderUri.substring(6);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final serverId = rest.substring(0, slash);
    final smbPath = rest.substring(slash);
    return (serverId, smbPath);
  }

  Future<List<VideoItem>> _listSmbFolder(String folderUri, {required bool recursive}) async {
    final parsed = _parseSmbFolderUri(folderUri);
    if (parsed == null) return const [];

    final serverId = parsed.$1;
    final smbPath = parsed.$2;

    final server = PlayraStorage.getServers().firstWhere(
      (s) => s.id == serverId,
      orElse: () => const ServerConnection(id: '', name: '', type: ServerType.smb, host: ''),
    );
    if (server.id.isEmpty) return const [];

    final items = await _listSmbPath(server, smbPath, recursive: recursive);
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  Future<List<VideoItem>> _listSmbPath(ServerConnection server, String smbPath, {required bool recursive}) async {
    final entries = await _smbBrowser.listPath(server, smbPath);
    final out = <VideoItem>[];

    for (final e in entries) {
      if (_smbBrowser.isHiddenEntry(e.name)) {
        continue;
      }

      if (e.isDirectory) {
        if (recursive) {
          try {
            out.addAll(await _listSmbPath(server, e.path, recursive: true));
          } catch (_) {
            // Ignore unreadable SMB subfolders.
          }
        }
        continue;
      }

      if (!_smbBrowser.isVideo(e.name)) {
        continue;
      }

      out.add(_smbBrowser.entryToVideoItem(server, e));
    }

    return out;
  }

  /// Scan multiple library folders at once.
  Future<List<VideoItem>> listFolders(List<String> folders, {bool recursive = true}) async {
    final all = <VideoItem>[];
    for (final f in folders) {
      try {
        all.addAll(await listFolder(f, recursive: recursive).timeout(_scanTimeoutForFolder(f)));
      } on TimeoutException {
        // Skip folders that are currently unreachable (for example offline SMB paths).
      } catch (_) {
        // Keep loading remaining folders even when one fails.
      }
    }
    return all;
  }
}
