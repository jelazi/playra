import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:smb_connect/smb_connect.dart';

import '../models/server_connection.dart';
import '../models/video_item.dart';

/// Lightweight wrapper around `smb_connect` used for browsing and streaming.
class SmbBrowserService {
  SmbConnect? _connect;
  ServerConnection? _server;

  bool isHiddenEntry(String name) {
    return name.trim().startsWith('.');
  }

  /// Returns the currently held connection or opens a new one.
  Future<SmbConnect> _ensureConnected(ServerConnection server) async {
    if (_connect != null && _server?.id == server.id) return _connect!;
    await close();
    _connect = await SmbConnect.connectAuth(host: server.host, domain: '', username: server.username ?? '', password: server.password ?? '');
    _server = server;
    return _connect!;
  }

  /// List entries (folders + supported video files) at [path] (e.g. "/share/movies").
  Future<List<SmbEntry>> listPath(ServerConnection server, String path) async {
    final c = await _ensureConnected(server);

    if (path.isEmpty || path == '/') {
      final shares = await c.listShares();
      return shares.map((s) => SmbEntry(name: s.path.replaceAll('/', ''), path: s.path, isDirectory: true, sizeBytes: null)).toList();
    }

    final folder = await c.file(path);
    final entries = await c.listFiles(folder);
    final list = entries.map((e) {
      final name = e.path.split('/').where((s) => s.isNotEmpty).last;
      final isDir = e.isDirectory();
      return SmbEntry(name: name, path: e.path, isDirectory: isDir, sizeBytes: isDir ? null : e.size);
    }).toList();

    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  /// Returns true if the entry's filename has a supported video extension.
  bool isVideo(String name) {
    if (isHiddenEntry(name)) return false;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return kSupportedVideoExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  /// Convert an entry to a [VideoItem] suitable for playback (uri is opaque
  /// `smb://serverId/full/path` – the proxy resolves it).
  VideoItem entryToVideoItem(ServerConnection server, SmbEntry e) {
    return VideoItem(id: 'smb://${server.id}${e.path}', name: e.name, uri: 'smb://${server.id}${e.path}', source: VideoSource.smb, sizeBytes: e.sizeBytes);
  }

  /// Read a byte range from [path] on [server].
  Future<Stream<Uint8List>> openRead(ServerConnection server, String path, {int start = 0, int? end}) async {
    final c = await _ensureConnected(server);
    final file = await c.file(path);
    final raf = await c.open(file);
    final controller = StreamController<Uint8List>(sync: true);
    final effectiveEnd = end ?? file.size;
    final totalLength = max(0, effectiveEnd - start);
    const chunkSize = 64 * 1024;

    unawaited(() async {
      try {
        if (start > 0) {
          await raf.setPosition(start);
        }

        var remaining = totalLength;
        while (remaining > 0) {
          final toRead = remaining > chunkSize ? chunkSize : remaining;
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) {
            break;
          }
          controller.add(chunk);
          remaining -= chunk.length;
          if (chunk.length < toRead) {
            break;
          }
        }
        await raf.close();
        await controller.close();
      } catch (e, st) {
        try {
          await raf.close();
        } catch (_) {}
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      }
    }());

    return controller.stream;
  }

  /// Get file size in bytes.
  Future<int> getSize(ServerConnection server, String path) async {
    final c = await _ensureConnected(server);
    final file = await c.file(path);
    return file.size;
  }

  Future<void> close() async {
    try {
      await _connect?.close();
    } catch (_) {}
    _connect = null;
    _server = null;
  }
}

class SmbEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int? sizeBytes;

  const SmbEntry({required this.name, required this.path, required this.isDirectory, this.sizeBytes});
}
