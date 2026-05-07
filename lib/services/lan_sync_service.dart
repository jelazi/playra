import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'playra_storage.dart';

class LanSyncRunResult {
  final bool configured;
  final int peersFound;
  final int mergedFromPeers;
  final int pushedToPeers;
  final String? error;

  const LanSyncRunResult({required this.configured, required this.peersFound, required this.mergedFromPeers, required this.pushedToPeers, this.error});
}

class LanPeerPlaybackSession {
  final String host;
  final int port;
  final String deviceName;
  final Map<String, dynamic> session;

  const LanPeerPlaybackSession({required this.host, required this.port, required this.deviceName, required this.session});
}

class _DiscoveryRequest {
  final void Function(String host, int port) onPeer;

  const _DiscoveryRequest(this.onPeer);
}

class LanSyncService {
  static const int _udpDiscoveryPort = 42116;
  static const int _preferredHttpPort = 42117;
  static const String _discoveryType = 'playra_sync_discovery';
  static const String _responseType = 'playra_sync_response';

  LanSyncService._();

  static final LanSyncService instance = LanSyncService._();

  RawDatagramSocket? _udpSocket;
  HttpServer? _httpServer;
  int _httpPort = _preferredHttpPort;
  bool _started = false;

  final Map<String, _DiscoveryRequest> _pendingDiscovery = <String, _DiscoveryRequest>{};

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _udpDiscoveryPort, reuseAddress: true, reusePort: true);
    _udpSocket?.broadcastEnabled = true;
    _udpSocket?.listen(_handleUdpEvent, onError: (_, error) {});

    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, _preferredHttpPort, shared: true);
      _httpPort = _preferredHttpPort;
    } catch (_) {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
      _httpPort = _httpServer!.port;
    }
    _httpServer?.listen(_handleHttpRequest, onError: (_, error) {});
  }

  bool get _isConfigured {
    final settings = PlayraStorage.getPlayerSettings();
    return settings.syncUsername.trim().isNotEmpty && settings.syncPassword.trim().isNotEmpty;
  }

  String get _syncUsername => PlayraStorage.getPlayerSettings().syncUsername.trim();
  String get _syncPassword => PlayraStorage.getPlayerSettings().syncPassword.trim();

  Future<LanSyncRunResult> syncNow() async {
    if (!_isConfigured) {
      return const LanSyncRunResult(configured: false, peersFound: 0, mergedFromPeers: 0, pushedToPeers: 0);
    }

    await start();

    try {
      final peers = await _discoverPeers();
      if (peers.isEmpty) {
        return const LanSyncRunResult(configured: true, peersFound: 0, mergedFromPeers: 0, pushedToPeers: 0);
      }

      int merged = 0;
      for (final entry in peers.entries) {
        final snapshot = await _fetchPeerSnapshot(entry.key, entry.value);
        if (snapshot == null) continue;
        await PlayraStorage.mergeSyncSnapshot(snapshot);
        merged++;
      }

      final mergedLocalSnapshot = PlayraStorage.exportSyncSnapshot();

      int pushed = 0;
      for (final entry in peers.entries) {
        final ok = await _pushSnapshotToPeer(entry.key, entry.value, mergedLocalSnapshot);
        if (ok) pushed++;
      }

      return LanSyncRunResult(configured: true, peersFound: peers.length, mergedFromPeers: merged, pushedToPeers: pushed);
    } catch (e) {
      return LanSyncRunResult(configured: true, peersFound: 0, mergedFromPeers: 0, pushedToPeers: 0, error: e.toString());
    }
  }

  Future<List<LanPeerPlaybackSession>> discoverPeerPlaybackSessions() async {
    if (!_isConfigured) return const [];

    await start();
    final peers = await _discoverPeers();
    if (peers.isEmpty) return const [];

    final out = <LanPeerPlaybackSession>[];
    for (final entry in peers.entries) {
      final payload = await _fetchPeerSession(entry.key, entry.value);
      if (payload == null) continue;
      final session = payload['session'];
      if (session is! Map) continue;
      final sessionMap = Map<String, dynamic>.from(session);
      if (sessionMap.isEmpty) continue;
      out.add(
        LanPeerPlaybackSession(
          host: entry.key,
          port: entry.value,
          deviceName: (payload['deviceName'] as String?)?.trim().isNotEmpty == true ? payload['deviceName'] as String : entry.key,
          session: sessionMap,
        ),
      );
    }
    return out;
  }

  Future<Map<String, int>> _discoverPeers() async {
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
    final peers = <String, int>{};

    _pendingDiscovery[requestId] = _DiscoveryRequest((host, port) {
      if (port <= 0) return;
      peers[host] = port;
    });

    final payload = jsonEncode(<String, dynamic>{'type': _discoveryType, 'requestId': requestId, 'username': _syncUsername, 'password': _syncPassword, 'httpPort': _httpPort});

    final broadcasts = await _candidateBroadcastAddresses();
    for (final b in broadcasts) {
      _udpSocket?.send(utf8.encode(payload), b, _udpDiscoveryPort);
    }

    await Future<void>.delayed(const Duration(milliseconds: 1300));
    _pendingDiscovery.remove(requestId);

    final localIps = await _localIpv4Addresses();
    peers.removeWhere((host, port) => localIps.contains(host) && port == _httpPort);
    return peers;
  }

  void _handleUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _udpSocket?.receive();
    if (datagram == null) return;

    final text = utf8.decode(datagram.data, allowMalformed: true);
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;
      payload = decoded;
    } catch (_) {
      return;
    }

    final type = payload['type'];
    if (type == _discoveryType) {
      _handleDiscovery(datagram.address, payload);
      return;
    }

    if (type == _responseType) {
      final requestId = payload['requestId'];
      if (requestId is! String) return;
      final req = _pendingDiscovery[requestId];
      if (req == null) return;
      final port = payload['httpPort'];
      if (port is! num) return;
      req.onPeer(datagram.address.address, port.toInt());
    }
  }

  void _handleDiscovery(InternetAddress source, Map<String, dynamic> payload) {
    if (!_isConfigured) return;

    final incomingUser = payload['username'] as String? ?? '';
    final incomingPass = payload['password'] as String? ?? '';
    if (incomingUser != _syncUsername || incomingPass != _syncPassword) return;

    final requestId = payload['requestId'];
    if (requestId is! String || requestId.isEmpty) return;

    final response = jsonEncode(<String, dynamic>{'type': _responseType, 'requestId': requestId, 'httpPort': _httpPort});

    _udpSocket?.send(utf8.encode(response), source, _udpDiscoveryPort);
  }

  Future<void> _handleHttpRequest(HttpRequest req) async {
    if (req.uri.path == '/sync/session') {
      if (!_isAuthorized(req)) {
        req.response.statusCode = HttpStatus.unauthorized;
        req.response.write('Unauthorized');
        await req.response.close();
        return;
      }

      if (req.method != 'GET') {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
        return;
      }

      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(<String, dynamic>{'deviceName': Platform.localHostname, 'session': PlayraStorage.getNowPlayingSession(), 'generatedAt': DateTime.now().millisecondsSinceEpoch}),
      );
      await req.response.close();
      return;
    }

    if (req.uri.path != '/sync/state') {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    if (!_isAuthorized(req)) {
      req.response.statusCode = HttpStatus.unauthorized;
      req.response.write('Unauthorized');
      await req.response.close();
      return;
    }

    if (req.method == 'GET') {
      final snapshot = PlayraStorage.exportSyncSnapshot();
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(snapshot));
      await req.response.close();
      return;
    }

    if (req.method == 'POST') {
      try {
        final body = await utf8.decoder.bind(req).join();
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          req.response.statusCode = HttpStatus.badRequest;
          req.response.write('Invalid payload');
          await req.response.close();
          return;
        }
        await PlayraStorage.mergeSyncSnapshot(decoded);
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"ok":true}');
      } catch (_) {
        req.response.statusCode = HttpStatus.badRequest;
        req.response.write('Invalid payload');
      }
      await req.response.close();
      return;
    }

    req.response.statusCode = HttpStatus.methodNotAllowed;
    await req.response.close();
  }

  bool _isAuthorized(HttpRequest req) {
    if (!_isConfigured) return false;
    final incomingUser = req.headers.value('x-playra-sync-user') ?? '';
    final incomingPass = req.headers.value('x-playra-sync-pass') ?? '';
    return incomingUser == _syncUsername && incomingPass == _syncPassword;
  }

  Future<Map<String, dynamic>?> _fetchPeerSnapshot(String host, int port) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('http://$host:$port/sync/state');
      final req = await client.getUrl(uri);
      req.headers.set('x-playra-sync-user', _syncUsername);
      req.headers.set('x-playra-sync-pass', _syncPassword);
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) return null;
      final body = await utf8.decoder.bind(res).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _pushSnapshotToPeer(String host, int port, Map<String, dynamic> snapshot) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('http://$host:$port/sync/state');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.headers.set('x-playra-sync-user', _syncUsername);
      req.headers.set('x-playra-sync-pass', _syncPassword);
      req.write(jsonEncode(snapshot));
      final res = await req.close();
      return res.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _fetchPeerSession(String host, int port) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('http://$host:$port/sync/session');
      final req = await client.getUrl(uri);
      req.headers.set('x-playra-sync-user', _syncUsername);
      req.headers.set('x-playra-sync-pass', _syncPassword);
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) return null;
      final body = await utf8.decoder.bind(res).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Set<String>> _localIpv4Addresses() async {
    final out = <String>{};
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          out.add(addr.address);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<List<InternetAddress>> _candidateBroadcastAddresses() async {
    final set = <String>{'255.255.255.255'};

    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          final parts = ip.split('.');
          if (parts.length == 4) {
            set.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
          }
        }
      }
    } catch (_) {}

    return set.map(InternetAddress.new).toList();
  }
}
