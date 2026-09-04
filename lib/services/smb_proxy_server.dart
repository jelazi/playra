import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../models/server_connection.dart';
import 'smb_browser_service.dart';

/// Local HTTP proxy that streams SMB file contents to the local video engine
/// (media_kit / libmpv). Supports HTTP `Range` requests so seeking works.
///
/// Usage:
///   final proxy = SmbProxyServer(browser);
///   await proxy.start();
///   final url = proxy.urlFor(server, '/share/movies/foo.mkv');
///   // feed [url] to the player
class SmbProxyServer {
  SmbProxyServer(this._browser);

  final SmbBrowserService _browser;
  HttpServer? _server;
  final Map<String, ServerConnection> _registered = {};
  final LinkedHashMap<String, _CachedChunk> _chunkCache = LinkedHashMap<String, _CachedChunk>();

  static const int _chunkSizeBytes = 1024 * 1024;
  static const int _maxOpenEndedRangeBytes = 2 * 1024 * 1024;
  static const int _defaultCacheLimitBytes = 256 * 1024 * 1024;
  int _cacheLimitBytes = _defaultCacheLimitBytes;
  int _cachedBytes = 0;

  int? get port => _server?.port;
  bool get isRunning => _server != null;

  void setCacheLimitMb(int sizeMb) {
    final normalizedMb = sizeMb.clamp(16, 512);
    _cacheLimitBytes = normalizedMb * 1024 * 1024;
    _trimCache();
  }

  void clearCache() {
    _chunkCache.clear();
    _cachedBytes = 0;
  }

  Future<void> start() async {
    if (_server != null) return;
    final handler = const Pipeline().addHandler(_handle);
    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    clearCache();
  }

  /// Register a server so its files can be streamed through the proxy.
  void register(ServerConnection s) => _registered[s.id] = s;

  /// Build a local URL for a video on a registered server. [smbPath] should
  /// start with `/`. Returns e.g. `http://127.0.0.1:54321/play/<id>/share/movies/foo.mkv`.
  String urlFor(ServerConnection server, String smbPath) {
    register(server);
    final normalizedPath = smbPath.startsWith('/') ? smbPath : '/$smbPath';
    final smbSegments = normalizedPath.split('/').where((segment) => segment.isNotEmpty);
    final uri = Uri(scheme: 'http', host: '127.0.0.1', port: _server!.port, pathSegments: <String>['play', server.id, ...smbSegments]);
    return uri.toString();
  }

  Future<Response> _handle(Request req) async {
    final segments = req.url.pathSegments;
    if (segments.length < 2 || segments.first != 'play') {
      return Response.notFound('not found');
    }
    final serverId = segments[1];
    final server = _registered[serverId];
    if (server == null) {
      return Response.notFound('server not registered');
    }

    final smbPath = '/${segments.skip(2).join('/')}';
    final fileKeyPrefix = '$serverId|$smbPath';

    int total;
    try {
      total = await _browser.getSize(server, smbPath);
    } catch (e) {
      return Response.notFound('smb file not found: $e');
    }

    final rangeHeader = req.headers['range'];
    int start = 0;
    int end = total - 1;
    bool partial = false;
    bool openEndedRange = false;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring(6);
      final parts = spec.split('-');
      if (parts.length == 2) {
        if (parts[0].isNotEmpty) start = int.tryParse(parts[0]) ?? 0;
        if (parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]) ?? (total - 1);
        } else {
          openEndedRange = true;
          end = total - 1;
        }
        partial = true;
      }
    }

    if (openEndedRange) {
      final cappedEnd = start + _maxOpenEndedRangeBytes - 1;
      if (cappedEnd < end) {
        end = cappedEnd;
      }
    }

    if (start < 0) start = 0;
    if (end >= total) end = total - 1;
    if (start > end) {
      return Response(416, headers: {'content-range': 'bytes */$total'});
    }

    final length = end - start + 1;
    final headers = <String, String>{'content-type': 'application/octet-stream', 'accept-ranges': 'bytes', 'content-length': length.toString()};
    if (partial) headers['content-range'] = 'bytes $start-$end/$total';

    if (req.method == 'HEAD') {
      return Response(partial ? 206 : 200, headers: headers);
    }

    Uint8List bodyBytes;
    try {
      bodyBytes = await _readRangeWithCache(server, fileKeyPrefix, smbPath, start: start, end: end, totalSize: total);
    } catch (e) {
      return Response.internalServerError(body: 'smb read error: $e');
    }

    return Response(partial ? 206 : 200, body: Stream<List<int>>.value(bodyBytes), headers: headers);
  }

  Future<Uint8List> _readRangeWithCache(
    ServerConnection server,
    String fileKeyPrefix,
    String smbPath, {
    required int start,
    required int end,
    required int totalSize,
  }) async {
    final expectedLength = end - start + 1;
    final buffer = BytesBuilder(copy: false);

    var cursor = start;
    while (cursor <= end) {
      final chunkIndex = cursor ~/ _chunkSizeBytes;
      final chunkStart = chunkIndex * _chunkSizeBytes;
      final chunkEnd = chunkStart + _chunkSizeBytes - 1;
      final key = '$fileKeyPrefix|$chunkIndex';

      var cached = _touchChunk(key);
      if (cached == null) {
        final fetchEnd = chunkEnd >= totalSize ? totalSize - 1 : chunkEnd;
        cached = await _fetchChunk(server, smbPath, chunkStart, fetchEnd);
        _storeChunk(key, cached);
      }

      final localStart = cursor - chunkStart;
      final localEnd = (end < chunkEnd ? end : chunkEnd) - chunkStart;
      final slice = Uint8List.sublistView(cached.bytes, localStart, localEnd + 1);
      buffer.add(slice);
      cursor = chunkEnd + 1;
    }

    final out = buffer.toBytes();
    if (out.length == expectedLength) return out;
    if (out.length > expectedLength) {
      return Uint8List.sublistView(out, 0, expectedLength);
    }
    return out;
  }

  _CachedChunk? _touchChunk(String key) {
    final existing = _chunkCache.remove(key);
    if (existing == null) return null;
    _chunkCache[key] = existing;
    return existing;
  }

  Future<_CachedChunk> _fetchChunk(ServerConnection server, String smbPath, int chunkStart, int chunkEnd) async {
    final raw = await _browser.openRead(server, smbPath, start: chunkStart, end: chunkEnd + 1);
    final builder = BytesBuilder(copy: false);
    await for (final part in raw) {
      builder.add(part);
    }
    final bytes = builder.toBytes();
    return _CachedChunk(start: chunkStart, bytes: bytes);
  }

  void _storeChunk(String key, _CachedChunk chunk) {
    final prev = _chunkCache.remove(key);
    if (prev != null) {
      _cachedBytes -= prev.bytes.length;
    }
    _chunkCache[key] = chunk;
    _cachedBytes += chunk.bytes.length;
    _trimCache();
  }

  void _trimCache() {
    while (_cachedBytes > _cacheLimitBytes && _chunkCache.isNotEmpty) {
      final oldestKey = _chunkCache.keys.first;
      final removed = _chunkCache.remove(oldestKey);
      if (removed != null) {
        _cachedBytes -= removed.bytes.length;
      }
    }
  }
}

class _CachedChunk {
  const _CachedChunk({required this.start, required this.bytes});

  final int start;
  final Uint8List bytes;
}
