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
  DateTime? _lastConnectedAt;

  static const Duration _connectionTimeout = Duration(seconds: 8);
  static const Duration _readTimeout = Duration(seconds: 10);
  static const int _maxReconnectAttempts = 3;

  bool _sameConnectionTarget(ServerConnection a, ServerConnection b) {
    return a.host == b.host && (a.username ?? '') == (b.username ?? '') && (a.password ?? '') == (b.password ?? '') && (a.port ?? 445) == (b.port ?? 445);
  }

  bool isHiddenEntry(String name) {
    return name.trim().startsWith('.');
  }

  bool get _isConnectionStale {
    if (_lastConnectedAt == null) return false;
    return DateTime.now().difference(_lastConnectedAt!) > const Duration(minutes: 2);
  }

  /// Returns the currently held connection or opens a new one.
  Future<SmbConnect> _ensureConnected(ServerConnection server) async {
    if (_connect != null && _server != null && _sameConnectionTarget(_server!, server) && !_isConnectionStale) {
      return _connect!;
    }
    await close();
    _connect = await SmbConnect.connectAuth(
      host: server.host,
      domain: '',
      username: server.username ?? '',
      password: server.password ?? '',
    ).timeout(_connectionTimeout);
    _server = server;
    _lastConnectedAt = DateTime.now();
    return _connect!;
  }

  Future<T> _runWithReconnect<T>(ServerConnection server, Future<T> Function(SmbConnect c) action) async {
    final reusedConnection = _connect != null && _server != null && _sameConnectionTarget(_server!, server) && !_isConnectionStale;

    Exception? lastError;
    for (var attempt = 0; attempt < _maxReconnectAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await close();
          await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
        final c = await _ensureConnected(server);
        return await action(c).timeout(_readTimeout);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (!reusedConnection && attempt == 0) rethrow;
      }
    }
    throw lastError ?? Exception('SMB operation failed after $_maxReconnectAttempts attempts');
  }

  /// List entries (folders + supported video files) at [path] (e.g. "/share/movies").
  Future<List<SmbEntry>> listPath(ServerConnection server, String path) async {
    return _runWithReconnect(server, (c) async {
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
    });
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
    final openResult = await _runWithReconnect(server, (c) async {
      final file = await c.file(path);
      final raf = await c.open(file);
      return (file, raf);
    });
    final file = openResult.$1;
    final raf = openResult.$2;
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
          final chunk = await raf.read(toRead).timeout(_readTimeout);
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
    return _runWithReconnect(server, (c) async {
      final file = await c.file(path);
      return file.size;
    });
  }

  Future<bool> isConnectedTo(ServerConnection server) async {
    if (_connect == null || _server == null) return false;
    if (!_sameConnectionTarget(_server!, server)) return false;
    if (_isConnectionStale) return false;
    try {
      await _connect!.listShares().timeout(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
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
