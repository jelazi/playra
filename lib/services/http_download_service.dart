import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'smb_download_service.dart';

/// Downloads a video from a direct HTTP(S) URL into the app's downloads folder.
///
/// Mirrors [SmbDownloadService.downloadVideoDirect] (chunked streaming, progress
/// callbacks, cancellation, partial-file cleanup) but reads from an HTTP stream
/// instead of SMB. Used for Real-Debrid direct links.
class HttpDownloadService {
  /// Downloads [url] to `<downloads>/<fileName>` and returns the local path.
  static Future<String> downloadUrl({
    required String url,
    required String fileName,
    void Function(int received, int total, String fileName)? onProgress,
    DownloadCancellationToken? cancellationToken,
  }) async {
    final dir = await SmbDownloadService.getDownloadsDir();
    final safeName = _sanitizeFileName(fileName);
    final targetPath = p.join(dir.path, safeName);

    final request = http.Request('GET', Uri.parse(url));
    final response = await request.send();

    if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
      await response.stream.drain();
      throw HttpException('Download failed with status ${response.statusCode}', uri: Uri.parse(url));
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = File(targetPath).openWrite();
    onProgress?.call(received, total, safeName);

    try {
      await for (final chunk in response.stream) {
        if (cancellationToken?.isCancelled == true) {
          throw const _HttpCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total, safeName);
      }
    } on _HttpCancelledException {
      await sink.close();
      final f = File(targetPath);
      if (await f.exists()) await f.delete();
      rethrow;
    } catch (_) {
      await sink.close();
      final f = File(targetPath);
      if (await f.exists()) await f.delete();
      rethrow;
    } finally {
      if (cancellationToken?.isCancelled != true) {
        await sink.flush();
        await sink.close();
      }
    }

    return targetPath;
  }

  static String _sanitizeFileName(String name) {
    var cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (cleaned.isEmpty) cleaned = 'movie';
    // Ensure a video extension so the player and library treat it as a video.
    if (!cleaned.contains('.')) cleaned = '$cleaned.mp4';
    return cleaned;
  }
}

class _HttpCancelledException implements Exception {
  const _HttpCancelledException();
}
