import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/torrent_stream.dart';
import 'aria2_service.dart';
import 'magnet_builder.dart';
import 'smb_download_service.dart';

void _log(String msg) => debugPrint('[playra.torrent] $msg');

/// Raised when the native torrent client cannot complete an operation.
class TorrentClientException implements Exception {
  final String message;
  const TorrentClientException(this.message);
  @override
  String toString() => 'TorrentClientException: $message';
}

/// Native torrent client backed by a bundled `aria2c` process (JSON-RPC).
///
/// aria2 is a mature, production-grade BitTorrent/magnet engine; it replaced the
/// pure-Dart `dtorrent_task_v2`, which could not reliably fetch metadata.
class TorrentClientService {
  TorrentClientService([Aria2Service? aria2]) : _aria2 = aria2 ?? Aria2Service();

  final Aria2Service _aria2;

  /// Downloads the movie referenced by [stream] into the downloads folder and
  /// returns its local path.
  Future<String> download(
    TorrentStream stream, {
    void Function(int received, int total, String fileName)? onProgress,
    DownloadCancellationToken? cancellationToken,
  }) async {
    if (!stream.hasInfoHash) throw const TorrentClientException('Stream has no info hash');
    _log('download() start: ${stream.releaseName} infoHash=${stream.infoHash} fileIdx=${stream.fileIdx}');

    final downloadsDir = await SmbDownloadService.getDownloadsDir();
    await _aria2.ensureStarted(downloadDir: downloadsDir.path);

    final magnet = MagnetBuilder.fromStream(stream);
    var gid = await _aria2.addUri(magnet, options: _addOptions(stream, downloadsDir.path));
    onProgress?.call(0, 0, stream.releaseName);

    Aria2Status status;
    var lastLog = 0;
    while (true) {
      if (cancellationToken?.isCancelled == true) {
        await _aria2.remove(gid);
        throw const _CancelledException();
      }

      try {
        status = await _aria2.tellStatus(gid);
      } catch (e) {
        throw TorrentClientException('aria2 status failed: $e');
      }

      // A magnet is first a metadata download; once done it spawns the real
      // file download referenced in `followedBy`. Switch to it.
      if (status.followedBy.isNotEmpty) {
        _log('metadata done, following to file gid=${status.followedBy.first}');
        gid = status.followedBy.first;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        continue;
      }

      switch (status.status) {
        case 'complete':
          _log('complete: total=${status.totalLength} files=${status.files.length}');
          onProgress?.call(status.completedLength, status.totalLength, stream.releaseName);
          final src = _targetFile(status, stream.fileIdx);
          if (src == null) throw const TorrentClientException('Downloaded file not found');
          final dest = await _moveToRoot(src.path, downloadsDir.path);
          _log('moved to $dest');
          return dest;
        case 'error':
          _log('aria2 error: ${status.errorMessage} (code ${status.errorCode})');
          throw TorrentClientException(status.errorMessage ?? 'aria2 error ${status.errorCode}');
        case 'removed':
          throw const _CancelledException();
        default:
          onProgress?.call(status.completedLength, status.totalLength, stream.releaseName);
          if (status.completedLength - lastLog > 5 * 1024 * 1024 || lastLog == 0) {
            _log('status=${status.status} ${status.completedLength}/${status.totalLength} '
                '${(status.downloadSpeed / 1024).toStringAsFixed(0)}KB/s peers/pieces gid=${status.gid}');
            lastLog = status.completedLength;
          }
          await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// Starts a streaming download and returns a handle once the target file is
  /// known (after metadata). The download continues in the background; the
  /// proxy serves bytes as pieces arrive (sequential selector).
  Future<TorrentStreamHandle> openStream(TorrentStream stream) async {
    if (!stream.hasInfoHash) throw const TorrentClientException('Stream has no info hash');
    _log('openStream() start: ${stream.releaseName} infoHash=${stream.infoHash} fileIdx=${stream.fileIdx}');

    final downloadsDir = await SmbDownloadService.getDownloadsDir();
    await _aria2.ensureStarted(downloadDir: downloadsDir.path);

    final magnet = MagnetBuilder.fromStream(stream);
    var gid = await _aria2.addUri(magnet, options: _addOptions(stream, downloadsDir.path));

    // Wait until metadata resolves into the real file download with a path.
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      final st = await _aria2.tellStatus(gid);
      if (st.followedBy.isNotEmpty) {
        gid = st.followedBy.first;
        continue;
      }
      if (st.status == 'error') {
        throw TorrentClientException(st.errorMessage ?? 'aria2 error ${st.errorCode}');
      }
      // Skip the `[METADATA]` pseudo-file; only return once the real target
      // file (with a concrete path and size) is known.
      final file = _targetFile(st, stream.fileIdx);
      if (file != null && file.length > 0) {
        var offset = 0;
        for (final f in st.files) {
          if (!f.isMetadata && f.index < file.index) offset += f.length;
        }
        _log('stream ready: file=${file.path} len=${file.length} offset=$offset');
        return TorrentStreamHandle(_aria2, gid, file.path, file.length, offset);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _log('openStream timed out (no metadata/seeders)');
    await _aria2.remove(gid);
    throw const TorrentClientException('Timed out preparing torrent stream (no seeders?)');
  }

  /// addUri options: target only the chosen file (Torrentio fileIdx -> aria2's
  /// 1-based select-file), so multi-file packs don't download everything.
  Map<String, String> _addOptions(TorrentStream stream, String dir) {
    final opts = {'dir': dir};
    if (stream.fileIdx >= 0) opts['select-file'] = '${stream.fileIdx + 1}';
    return opts;
  }

  /// Picks the target file: the one matching the requested index, else the
  /// largest real (non-`[METADATA]`) file.
  Aria2File? _targetFile(Aria2Status status, int fileIdx) {
    final wantIndex = fileIdx >= 0 ? fileIdx + 1 : -1;
    Aria2File? exact;
    Aria2File? largest;
    for (final f in status.files) {
      if (f.path.isEmpty || f.isMetadata) continue;
      if (f.index == wantIndex) exact = f;
      if (largest == null || f.length > largest.length) largest = f;
    }
    return exact ?? largest;
  }

  /// Moves [srcPath] into the downloads root with a clean name so it appears in
  /// DownloadsScreen (which lists top-level files only), cleaning up the leftover
  /// torrent subfolder for multi-file torrents.
  Future<String> _moveToRoot(String srcPath, String root) async {
    final src = File(srcPath);
    final cleanName = _sanitize(p.basename(srcPath));
    final dest = p.join(root, cleanName);

    if (p.normalize(srcPath) == p.normalize(dest)) return dest;
    if (await File(dest).exists()) await File(dest).delete();
    if (await src.exists()) {
      await src.rename(dest);
    } else {
      throw const TorrentClientException('Downloaded file missing after completion');
    }

    // Remove an empty leftover torrent subfolder.
    final parent = Directory(p.dirname(srcPath));
    if (p.normalize(parent.path) != p.normalize(root) && parent.existsSync()) {
      try {
        if (parent.listSync().isEmpty) parent.deleteSync(recursive: true);
      } catch (_) {}
    }
    return dest;
  }

  String _sanitize(String name) {
    var cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (cleaned.isEmpty) cleaned = 'movie';
    return cleaned;
  }

  Future<void> dispose() => _aria2.dispose();
}

class _CancelledException implements Exception {
  const _CancelledException();
}

/// A live handle to a streaming torrent download, used by [TorrentProxyServer]
/// to serve byte ranges from the growing on-disk file as pieces arrive.
class TorrentStreamHandle {
  TorrentStreamHandle(this._aria2, this.gid, this.filePath, this.fileLength, this.torrentOffset);

  final Aria2Service _aria2;
  final String gid;
  final String filePath;
  final int fileLength;

  /// Byte offset of this file within the whole torrent (0 for single-file
  /// torrents). Used to map file ranges onto the torrent-global piece bitfield.
  final int torrentOffset;

  /// Latest aria2 status (bitfield, completed bytes, speed) for this download.
  Future<Aria2Status> status() => _aria2.tellStatus(gid);

  /// Stops the download and removes it from aria2.
  Future<void> dispose() => _aria2.remove(gid);
}

/// Whether the native torrent client should be available on this platform.
bool get torrentClientSupported => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
