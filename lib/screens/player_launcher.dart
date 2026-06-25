import 'dart:io';

import 'package:flutter/material.dart';

import '../models/server_connection.dart';
import '../models/video_item.dart';
import '../services/playra_storage.dart';
import '../services/smb_browser_service.dart';
import '../services/smb_proxy_server.dart';
import 'playra_player_screen.dart';

/// Resolve a [VideoItem] into a play URL (local file or local-proxy URL for SMB)
/// and push the player screen.
class PlayerLauncher {
  PlayerLauncher(this._browser, this._proxy);

  final SmbBrowserService _browser;
  final SmbProxyServer _proxy;

  Future<void> launch(BuildContext context, VideoItem video) async {
    await PlayraStorage.addRecent(video);
    if (!context.mounted) return;
    final url = await _resolvePlayUrl(context, video);
    if (!context.mounted) return;
    if (url == null) return;
    final playbackVideo = _toPlaybackVideo(video, url);

    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayraPlayerScreen(video: playbackVideo)));
  }

  Future<void> launchReplacement(BuildContext context, VideoItem video) async {
    await PlayraStorage.addRecent(video);
    if (!context.mounted) return;
    final url = await _resolvePlayUrl(context, video);
    if (!context.mounted) return;
    if (url == null) return;
    final playbackVideo = _toPlaybackVideo(video, url);

    if (!context.mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PlayraPlayerScreen(video: playbackVideo)));
  }

  Future<VideoItem?> resolveForHash(BuildContext context, VideoItem video) async {
    final url = await _resolvePlayUrl(context, video);
    if (url == null) return null;
    return _toPlaybackVideo(video, url);
  }

  VideoItem _toPlaybackVideo(VideoItem original, String resolvedUrl) {
    if (original.uri == resolvedUrl) return original;
    final source = resolvedUrl.startsWith('http') ? VideoSource.http : original.source;
    return VideoItem(id: original.id, name: original.name, uri: resolvedUrl, source: source, sizeBytes: original.sizeBytes, modified: original.modified, folder: original.folder);
  }

  Future<String?> _resolvePlayUrl(BuildContext context, VideoItem video) async {
    String url;
    switch (video.source) {
      case VideoSource.local:
        url = video.uri;
        break;
      case VideoSource.http:
        url = video.uri;
        break;
      case VideoSource.smb:
        // Expected video.uri format: smb://<serverId><path>
        final parsed = _parseSmbUri(video.uri);
        if (parsed == null) {
          _showError(context, 'Invalid SMB URI: ${video.uri}');
          return null;
        }
        final server = PlayraStorage.getServers().firstWhere(
          (s) => s.id == parsed.$1,
          orElse: () => ServerConnection(id: '', name: '', type: ServerType.smb, host: ''),
        );
        if (server.id.isEmpty) {
          _showError(context, 'Server not found');
          return null;
        }
        final playerSettings = PlayraStorage.getPlayerSettings();
        _proxy.setCacheLimitMb(playerSettings.smbStreamCacheSizeMb);
        await _proxy.start();
        _proxy.register(server);
        final candidateUrl = _proxy.urlFor(server, parsed.$2);
        url = await _resolveReachableProxyUrl(candidateUrl);
        break;
    }

    return url;
  }

  (String, String)? _parseSmbUri(String uri) {
    if (!uri.startsWith('smb://')) return null;
    final rest = uri.substring(6);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final id = rest.substring(0, slash);
    final path = rest.substring(slash);
    return (id, path);
  }

  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String> _resolveReachableProxyUrl(String candidateUrl) async {
    final candidates = <String>{candidateUrl, _replaceHost(candidateUrl, 'localhost'), _replaceHost(candidateUrl, '127.0.0.1'), _replaceHost(candidateUrl, '::1')}
      ..removeWhere((url) => url.isEmpty);

    for (final url in candidates) {
      final reachable = await _canReachProxy(url);
      if (reachable) return url;
    }

    return candidateUrl;
  }

  String _replaceHost(String url, String host) {
    try {
      final uri = Uri.parse(url);
      return uri.replace(host: host).toString();
    } catch (_) {
      return url;
    }
  }

  Future<bool> _canReachProxy(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 2));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final res = await req.close().timeout(const Duration(seconds: 2));
      await res.drain<void>();
      return res.statusCode == 200 || res.statusCode == 206;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  // expose browser if needed by callers
  SmbBrowserService get browser => _browser;

  Future<bool> ensureSmbConnected(VideoItem video) async {
    if (video.source != VideoSource.smb) return true;
    final parsed = _parseSmbUri(video.id);
    if (parsed == null) return true;
    final server = PlayraStorage.getServers().firstWhere(
      (s) => s.id == parsed.$1,
      orElse: () => ServerConnection(id: '', name: '', type: ServerType.smb, host: ''),
    );
    if (server.id.isEmpty) return false;
    final connected = await _browser.isConnectedTo(server);
    if (connected) return true;
    try {
      await _browser.close();
      await _proxy.start();
      _proxy.register(server);
      final candidateUrl = _proxy.urlFor(server, parsed.$2);
      await _resolveReachableProxyUrl(candidateUrl);
      return true;
    } catch (_) {
      return false;
    }
  }
}
