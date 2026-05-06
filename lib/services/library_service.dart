import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/video_item.dart';

/// Scans configured local folders for video files.
class LibraryService {
  /// List videos in a single directory (non-recursive by default; set [recursive] to walk subtree).
  Future<List<VideoItem>> listFolder(String folderPath, {bool recursive = false}) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return const [];

    final files = <File>[];
    try {
      await for (final entity in dir.list(recursive: recursive, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase().replaceFirst('.', '');
          if (kSupportedVideoExtensions.contains(ext)) {
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

  /// Scan multiple library folders at once.
  Future<List<VideoItem>> listFolders(List<String> folders, {bool recursive = true}) async {
    final all = <VideoItem>[];
    for (final f in folders) {
      all.addAll(await listFolder(f, recursive: recursive));
    }
    return all;
  }
}
