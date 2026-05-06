import 'dart:async';
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

  int? get port => _server?.port;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final handler = const Pipeline().addHandler(_handle);
    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Register a server so its files can be streamed through the proxy.
  void register(ServerConnection s) => _registered[s.id] = s;

  /// Build a local URL for a video on a registered server. [smbPath] should
  /// start with `/`. Returns e.g. `http://127.0.0.1:54321/play/<id>/share/movies/foo.mkv`.
  String urlFor(ServerConnection server, String smbPath) {
    register(server);
    final p = smbPath.startsWith('/') ? smbPath : '/$smbPath';
    return 'http://127.0.0.1:${_server!.port}/play/${server.id}$p';
  }

  Future<Response> _handle(Request req) async {
    final segments = req.url.pathSegments;
    if (segments.length < 2 || segments.first != 'play') {
      return Response.notFound('not found');
    }
    final serverId = segments[1];
    final server = _registered[serverId];
    if (server == null) return Response.notFound('server not registered');

    final smbPath = '/${segments.skip(2).join('/')}';

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

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring(6);
      final parts = spec.split('-');
      if (parts.length == 2) {
        if (parts[0].isNotEmpty) start = int.tryParse(parts[0]) ?? 0;
        if (parts[1].isNotEmpty) end = int.tryParse(parts[1]) ?? (total - 1);
        partial = true;
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

    Stream<List<int>> body;
    try {
      final raw = await _browser.openRead(server, smbPath, start: start, end: end + 1);
      body = raw.cast<List<int>>();
    } catch (e) {
      return Response.internalServerError(body: 'smb read error: $e');
    }

    // Limit to the requested byte length so libmpv sees an exact match.
    body = _limit(body, length);

    return Response(partial ? 206 : 200, body: body, headers: headers);
  }

  Stream<List<int>> _limit(Stream<List<int>> source, int max) async* {
    var sent = 0;
    await for (final chunk in source) {
      if (sent >= max) break;
      final remaining = max - sent;
      if (chunk.length <= remaining) {
        sent += chunk.length;
        yield chunk;
      } else {
        yield Uint8List.fromList(chunk.sublist(0, remaining));
        sent += remaining;
        break;
      }
    }
  }
}
