import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Represents a file that has been downloaded to the app's local downloads folder.
class DownloadedFile {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;

  const DownloadedFile({required this.path, required this.name, required this.sizeBytes, required this.modified});

  String get displayName {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String get formattedSize {
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Token used to cancel an in-progress download.
class DownloadCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Service for downloading SMB proxy video files to the app's local storage,
/// and managing (listing / deleting) those downloads.
class SmbDownloadService {
  static const String _subdir = 'playra_downloads';

  static const Set<String> _subtitleExtensions = {'.srt', '.ass', '.ssa', '.vtt', '.sub'};

  /// Human-readable byte size string.
  static String formatBytes(int bytes) => _fmtBytes(bytes);

  /// Returns the local directory where downloads are stored. Creates it if needed.
  static Future<Directory> getDownloadsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _subdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns a sorted list of downloaded video files (subtitle sidecars excluded).
  static Future<List<DownloadedFile>> listDownloads() async {
    final dir = await getDownloadsDir();
    final entities = await dir.list().toList();
    final files = entities.whereType<File>().where((f) => !_isSubtitleFile(f.path)).toList()
      ..sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));

    final result = <DownloadedFile>[];
    for (final file in files) {
      final stat = await file.stat();
      result.add(DownloadedFile(path: file.path, name: p.basename(file.path), sizeBytes: stat.size, modified: stat.modified));
    }
    return result;
  }

  /// Deletes the downloaded file at [filePath] and any matching subtitle sidecars.
  static Future<void> deleteDownload(String filePath) async {
    final baseName = p.basenameWithoutExtension(filePath);
    final dir = Directory(p.dirname(filePath));
    if (!await dir.exists()) return;

    final entities = await dir.list().toList();
    for (final entity in entities.whereType<File>()) {
      final name = p.basename(entity.path);
      final isTarget = name == p.basename(filePath);
      final isSidecar = _isSubtitleFile(entity.path) && p.basenameWithoutExtension(name).startsWith(baseName);
      if (isTarget || isSidecar) {
        if (await entity.exists()) {
          await entity.delete();
        }
      }
    }
  }

  static bool _isSubtitleFile(String path) {
    return _subtitleExtensions.contains(p.extension(path).toLowerCase());
  }

  /// Returns candidate subtitle proxy URLs for a given [videoProxyUrl],
  /// mirroring the player's side-car lookup logic.
  static List<String> subtitleCandidatesFor(String videoProxyUrl) {
    try {
      final uri = Uri.parse(videoProxyUrl);
      final segments = uri.pathSegments;
      if (segments.length < 3 || segments.first != 'play') return const [];

      final videoName = segments.last;
      final dot = videoName.lastIndexOf('.');
      if (dot <= 0) return const [];
      final base = videoName.substring(0, dot);

      final names = ['$base.srt', '$base.cs.srt', '$base.cz.srt', '$base.czech.srt', '$base.en.srt', '$base.english.srt'];

      return names.map((name) {
        final updated = [...segments]..[segments.length - 1] = name;
        return uri.replace(pathSegments: updated, query: null, fragment: null).toString();
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Checks whether a remote URL responds with 200/206.
  static Future<bool> remoteFileExists(String url) async {
    try {
      final response = await http.head(Uri.parse(url));
      return response.statusCode == HttpStatus.ok || response.statusCode == HttpStatus.partialContent;
    } catch (_) {
      return false;
    }
  }

  /// Streams [url] to [targetPath], invoking [onProgress] with (received, total).
  static Future<void> _downloadFile(String url, String targetPath, void Function(int received, int total)? onProgress, DownloadCancellationToken? token) async {
    final request = http.Request('GET', Uri.parse(url));
    final streamedResponse = await request.send();
    if (streamedResponse.statusCode != HttpStatus.ok && streamedResponse.statusCode != HttpStatus.partialContent) {
      throw Exception('HTTP ${streamedResponse.statusCode}');
    }

    final total = streamedResponse.contentLength ?? -1;
    var received = 0;
    final sink = File(targetPath).openWrite();

    try {
      await for (final chunk in streamedResponse.stream) {
        if (token?.isCancelled == true) {
          throw const _CancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } on _CancelledException {
      await sink.flush();
      await sink.close();
      final f = File(targetPath);
      if (await f.exists()) await f.delete();
      rethrow;
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// Downloads video from [videoProxyUrl] (SMB proxy HTTP URL) plus any available
  /// subtitle sidecars to the app downloads folder.
  ///
  /// Returns the local path of the downloaded video file, or throws on error.
  ///
  /// [onProgress] is called with (receivedBytes, totalBytes, currentFileName).
  /// Pass a [cancellationToken] to allow the caller to abort the download.
  static Future<String> downloadVideo({
    required String videoProxyUrl,
    required String videoName,
    void Function(int received, int total, String fileName)? onProgress,
    DownloadCancellationToken? cancellationToken,
  }) async {
    final dir = await getDownloadsDir();
    final targetVideoPath = p.join(dir.path, videoName);

    // Download the main video file.
    await _downloadFile(videoProxyUrl, targetVideoPath, (r, t) => onProgress?.call(r, t, videoName), cancellationToken);

    // Download subtitle sidecars (non-fatal if they fail).
    final candidates = subtitleCandidatesFor(videoProxyUrl);
    for (final candidateUrl in candidates) {
      if (cancellationToken?.isCancelled == true) break;
      if (!await remoteFileExists(candidateUrl)) continue;
      final subName = Uri.parse(candidateUrl).pathSegments.last;
      final targetSubPath = p.join(dir.path, subName);
      try {
        await _downloadFile(candidateUrl, targetSubPath, null, cancellationToken);
      } catch (_) {
        // Subtitle download failure is non-fatal.
      }
    }

    return targetVideoPath;
  }
}

class _CancelledException implements Exception {
  const _CancelledException();
}

String _fmtBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
