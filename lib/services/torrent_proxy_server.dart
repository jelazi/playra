import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'torrent_client_service.dart';

/// Local HTTP server that streams a still-downloading torrent file (via aria2)
/// to the video engine, serving HTTP `Range` requests. Bytes are served only
/// once the covering pieces are present (per aria2's bitfield); otherwise the
/// read waits for the sequential download to catch up.
class TorrentProxyServer {
  HttpServer? _server;
  final Map<String, TorrentStreamHandle> _handles = {};
  var _counter = 0;

  static const int _maxOpenEndedRangeBytes = 4 * 1024 * 1024;
  static const Duration _pieceWaitTimeout = Duration(seconds: 120);

  int? get port => _server?.port;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final handler = const Pipeline().addHandler(_handle);
    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
  }

  Future<void> stop() async {
    for (final handle in _handles.values) {
      await handle.dispose();
    }
    _handles.clear();
    await _server?.close(force: true);
    _server = null;
  }

  /// Registers a streaming [handle] and returns a play URL for it.
  String register(TorrentStreamHandle handle) {
    final id = 'torrent${_counter++}';
    _handles[id] = handle;
    final name = handle.filePath.split(Platform.pathSeparator).last;
    final uri = Uri(scheme: 'http', host: '127.0.0.1', port: _server!.port, pathSegments: <String>['play', id, name]);
    return uri.toString();
  }

  Future<Response> _handle(Request req) async {
    final segments = req.url.pathSegments;
    if (segments.length < 2 || segments.first != 'play') {
      return Response.notFound('not found');
    }
    final handle = _handles[segments[1]];
    if (handle == null) return Response.notFound('handle not registered');

    final total = handle.fileLength;
    final rangeHeader = req.headers['range'];
    var start = 0;
    var end = total - 1;
    var partial = false;
    var openEnded = false;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      if (parts.length == 2) {
        if (parts[0].isNotEmpty) start = int.tryParse(parts[0]) ?? 0;
        if (parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]) ?? (total - 1);
        } else {
          openEnded = true;
          end = total - 1;
        }
        partial = true;
      }
    }

    if (openEnded) {
      final cappedEnd = start + _maxOpenEndedRangeBytes - 1;
      if (cappedEnd < end) end = cappedEnd;
    }
    if (start < 0) start = 0;
    if (end >= total) end = total - 1;
    if (start > end) {
      return Response(416, headers: {'content-range': 'bytes */$total'});
    }

    final length = end - start + 1;
    final headers = <String, String>{
      'content-type': 'application/octet-stream',
      'accept-ranges': 'bytes',
      'content-length': length.toString(),
    };
    if (partial) headers['content-range'] = 'bytes $start-$end/$total';

    if (req.method == 'HEAD') {
      return Response(partial ? 206 : 200, headers: headers);
    }

    try {
      await _awaitBytes(handle, start, end);
    } catch (e) {
      return Response.internalServerError(body: 'torrent stream wait failed: $e');
    }

    final body = _readFileRange(handle.filePath, start, end);
    return Response(partial ? 206 : 200, body: body, headers: headers);
  }

  /// Waits until pieces covering file range [start, end] are downloaded.
  /// File ranges are mapped onto the torrent-global bitfield via the handle's
  /// [TorrentStreamHandle.torrentOffset].
  Future<void> _awaitBytes(TorrentStreamHandle handle, int start, int end) async {
    final absStart = handle.torrentOffset + start;
    final absEnd = handle.torrentOffset + end;
    final deadline = DateTime.now().add(_pieceWaitTimeout);
    while (true) {
      final st = await handle.status();
      if (st.status == 'error') throw Exception(st.errorMessage ?? 'download error');
      if (st.hasByteRange(absStart, absEnd)) return;
      // Fallback when bitfield/pieceLength unavailable: rely on completedLength
      // (sequential selector keeps the prefix contiguous).
      if (st.bitfield.isEmpty && st.completedLength > end) return;
      if (DateTime.now().isAfter(deadline)) {
        throw Exception('timed out waiting for bytes $start-$end');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  Stream<List<int>> _readFileRange(String path, int start, int end) async* {
    final file = File(path);
    final raf = await file.open();
    try {
      await raf.setPosition(start);
      var remaining = end - start + 1;
      const chunk = 64 * 1024;
      while (remaining > 0) {
        final toRead = remaining < chunk ? remaining : chunk;
        final bytes = await raf.read(toRead);
        if (bytes.isEmpty) break;
        yield bytes;
        remaining -= bytes.length;
      }
    } finally {
      await raf.close();
    }
  }
}
