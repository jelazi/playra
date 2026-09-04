import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/server_connection.dart';
import 'smb_browser_service.dart';

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

  static Future<void> _downloadOptionalFile(String url, String targetPath, DownloadCancellationToken? token) async {
    final request = http.Request('GET', Uri.parse(url));
    final streamedResponse = await request.send();

    if (streamedResponse.statusCode != HttpStatus.ok && streamedResponse.statusCode != HttpStatus.partialContent) {
      await streamedResponse.stream.drain();
      return;
    }

    final sink = File(targetPath).openWrite();
    try {
      await for (final chunk in streamedResponse.stream) {
        if (token?.isCancelled == true) {
          throw const _CancelledException();
        }
        sink.add(chunk);
      }
    } on _CancelledException {
      final f = File(targetPath);
      if (await f.exists()) {
        await f.delete();
      }
      rethrow;
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  static Future<void> _downloadSubtitleSidecars({
    required String videoProxyUrl,
    required String downloadsDirPath,
    DownloadCancellationToken? cancellationToken,
    SmbBrowserService? browser,
    ServerConnection? server,
    String? smbPath,
  }) async {
    if (browser != null && server != null && smbPath != null) {
      await _downloadSubtitleSidecarsDirect(
        downloadsDirPath: downloadsDirPath,
        cancellationToken: cancellationToken,
        browser: browser,
        server: server,
        videoSmbPath: smbPath,
      );
      return;
    }

    final candidates = subtitleCandidatesFor(videoProxyUrl);
    await Future.wait(
      candidates.map((candidateUrl) async {
        if (cancellationToken?.isCancelled == true) return;
        final subName = Uri.parse(candidateUrl).pathSegments.last;
        final targetSubPath = p.join(downloadsDirPath, subName);
        try {
          await _downloadOptionalFile(candidateUrl, targetSubPath, cancellationToken);
        } catch (_) {
          // Subtitle download failure is non-fatal.
        }
      }),
      eagerError: false,
    );
  }

  static Future<void> _downloadSubtitleSidecarsDirect({
    required String downloadsDirPath,
    required SmbBrowserService browser,
    required ServerConnection server,
    required String videoSmbPath,
    DownloadCancellationToken? cancellationToken,
  }) async {
    final dir = p.dirname(videoSmbPath);
    final base = p.basenameWithoutExtension(videoSmbPath);
    final names = <String>['$base.srt', '$base.cs.srt', '$base.cz.srt', '$base.czech.srt', '$base.en.srt', '$base.english.srt'];

    for (final name in names) {
      if (cancellationToken?.isCancelled == true) return;
      final subSmbPath = p.posix.join(dir, name);
      final targetPath = p.join(downloadsDirPath, name);
      try {
        final size = await browser.getSize(server, subSmbPath);
        if (size <= 0) continue;
        final stream = await browser.openRead(server, subSmbPath, start: 0, end: size);
        final sink = File(targetPath).openWrite();
        try {
          await for (final chunk in stream) {
            if (cancellationToken?.isCancelled == true) break;
            sink.add(chunk);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
      } catch (_) {
        // Subtitle download failure is non-fatal.
      }
    }
  }

  /// Downloads video directly from SMB using [browser] for [server] at [smbPath].
  /// Much more reliable than going through the proxy server, especially for
  /// large files on mobile where connections may be interrupted.
  ///
  /// Supports cancellation via [cancellationToken] and progress via [onProgress].
  /// Returns the local path of the downloaded video file, or throws on error.
  static Future<String> downloadVideoDirect({
    required SmbBrowserService browser,
    required ServerConnection server,
    required String smbPath,
    required String videoName,
    void Function(int received, int total, String fileName)? onProgress,
    DownloadCancellationToken? cancellationToken,
  }) async {
    final dir = await getDownloadsDir();
    final targetVideoPath = p.join(dir.path, videoName);

    final fileSize = await browser.getSize(server, smbPath);
    var received = 0;
    final sink = File(targetVideoPath).openWrite();

    onProgress?.call(received, fileSize, videoName);

    try {
      final stream = await browser.openRead(server, smbPath, start: 0, end: fileSize);

      try {
        await for (final chunk in stream) {
          if (cancellationToken?.isCancelled == true) {
            throw const _CancelledException();
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, fileSize, videoName);
        }
      } catch (e) {
        if (e is _CancelledException) rethrow;
        rethrow;
      }
    } on _CancelledException {
      final f = File(targetVideoPath);
      if (await f.exists()) {
        await f.delete();
      }
      rethrow;
    } finally {
      await sink.flush();
      await sink.close();
    }

    unawaited(
      _downloadSubtitleSidecars(
        videoProxyUrl: '',
        downloadsDirPath: dir.path,
        cancellationToken: cancellationToken,
        browser: browser,
        server: server,
        smbPath: smbPath,
      ),
    );

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
