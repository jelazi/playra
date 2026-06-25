import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

void _log(String msg) => debugPrint('[playra.aria2] $msg');

/// Raised when aria2 cannot be started or a request fails.
class Aria2Exception implements Exception {
  final String message;
  const Aria2Exception(this.message);
  @override
  String toString() => 'Aria2Exception: $message';
}

/// Status snapshot for an aria2 download (subset of `aria2.tellStatus`).
class Aria2Status {
  final String gid;
  final String status; // active | waiting | paused | error | complete | removed
  final int totalLength;
  final int completedLength;
  final List<String> followedBy;
  final List<Aria2File> files;
  final int? errorCode;
  final String? errorMessage;
  final String bitfield; // hex, one bit per piece (MSB first); '' if unknown
  final int pieceLength;
  final int downloadSpeed;

  const Aria2Status({
    required this.gid,
    required this.status,
    required this.totalLength,
    required this.completedLength,
    required this.followedBy,
    required this.files,
    this.errorCode,
    this.errorMessage,
    this.bitfield = '',
    this.pieceLength = 0,
    this.downloadSpeed = 0,
  });

  factory Aria2Status.fromJson(Map<String, dynamic> j) => Aria2Status(
        gid: (j['gid'] as String?) ?? '',
        status: (j['status'] as String?) ?? '',
        totalLength: int.tryParse('${j['totalLength'] ?? 0}') ?? 0,
        completedLength: int.tryParse('${j['completedLength'] ?? 0}') ?? 0,
        followedBy: (j['followedBy'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        files: (j['files'] as List?)?.whereType<Map<String, dynamic>>().map(Aria2File.fromJson).toList() ?? const [],
        errorCode: int.tryParse('${j['errorCode'] ?? ''}'),
        errorMessage: j['errorMessage'] as String?,
        bitfield: (j['bitfield'] as String?) ?? '',
        pieceLength: int.tryParse('${j['pieceLength'] ?? 0}') ?? 0,
        downloadSpeed: int.tryParse('${j['downloadSpeed'] ?? 0}') ?? 0,
      );

  /// Whether the piece at [index] has been downloaded, per [bitfield].
  bool hasPiece(int index) {
    if (bitfield.isEmpty || index < 0) return false;
    final nibbleIndex = index ~/ 4;
    if (nibbleIndex >= bitfield.length) return false;
    final nibble = int.tryParse(bitfield[nibbleIndex], radix: 16) ?? 0;
    final bitInNibble = 3 - (index % 4); // MSB first
    return (nibble & (1 << bitInNibble)) != 0;
  }

  /// Whether every piece covering byte range [start, end] (inclusive) is present.
  bool hasByteRange(int start, int end) {
    if (pieceLength <= 0) return false;
    final firstPiece = start ~/ pieceLength;
    final lastPiece = end ~/ pieceLength;
    for (var i = firstPiece; i <= lastPiece; i++) {
      if (!hasPiece(i)) return false;
    }
    return true;
  }
}

class Aria2File {
  final int index; // 1-based
  final String path;
  final int length;
  final bool selected;
  Aria2File({required this.index, required this.path, required this.length, required this.selected});
  factory Aria2File.fromJson(Map<String, dynamic> j) => Aria2File(
        index: int.tryParse('${j['index'] ?? 0}') ?? 0,
        path: (j['path'] as String?) ?? '',
        length: int.tryParse('${j['length'] ?? 0}') ?? 0,
        selected: '${j['selected']}' == 'true',
      );

  bool get isMetadata => path.startsWith('[METADATA]');
}

/// Manages a background `aria2c` process in RPC mode and exposes the JSON-RPC
/// calls needed for torrent/magnet downloads.
class Aria2Service {
  Process? _process;
  int? _port;
  String? _secret;
  final Dio _dio = Dio();

  static const List<String> _binaryCandidates = [
    'aria2c',
    '/opt/homebrew/bin/aria2c',
    '/usr/local/bin/aria2c',
    '/usr/bin/aria2c',
  ];

  bool get isRunning => _process != null;

  /// Resolves the aria2c executable: a binary bundled next to the app first,
  /// then well-known locations / PATH.
  static String _resolveBinary() {
    // Bundled next to the executable (for shipped desktop builds).
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundled = File('$exeDir/aria2c');
      if (bundled.existsSync()) return bundled.path;
    } catch (_) {}
    for (final candidate in _binaryCandidates) {
      if (candidate.contains('/')) {
        if (File(candidate).existsSync()) {
          _log('resolved binary: $candidate');
          return candidate;
        }
      }
    }
    // Fall back to PATH lookup (works in dev).
    _log('no known aria2c path found; falling back to PATH lookup');
    return 'aria2c';
  }

  /// Starts the aria2 daemon if not already running.
  Future<void> ensureStarted({required String downloadDir}) async {
    if (_process != null) {
      _log('daemon already running on port $_port');
      return;
    }

    final port = 6800 + Random().nextInt(2000);
    final secret = _randomToken();
    final binary = _resolveBinary();
    _log('starting daemon: binary=$binary port=$port dir=$downloadDir');

    final Process proc;
    try {
      proc = await Process.start(binary, [
        '--enable-rpc',
        '--rpc-listen-all=false',
        '--rpc-listen-port=$port',
        '--rpc-secret=$secret',
        '--rpc-allow-origin-all=true',
        '--dir=$downloadDir',
        '--continue=true',
        '--seed-time=0',
        '--bt-save-metadata=true',
        // Sequential piece selection + no preallocation so the on-disk file
        // grows contiguously from the start, enabling progressive streaming.
        '--stream-piece-selector=inorder',
        '--file-allocation=none',
        '--summary-interval=0',
        '--console-log-level=warn',
      ]);
    } on ProcessException catch (e) {
      _log('ProcessException starting aria2c: ${e.message}');
      throw Aria2Exception('Could not start aria2c ($binary): ${e.message}. Install aria2 or bundle the binary.');
    } catch (e) {
      _log('unexpected error starting aria2c: $e');
      rethrow;
    }

    _process = proc;
    _port = port;
    _secret = secret;
    _log('process started pid=${proc.pid}');

    // Surface aria2 output to logs (helps diagnose spawn/permission issues).
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => _log('out: $l'));
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => _log('ERR: $l'));
    unawaited(proc.exitCode.then((code) {
      _log('aria2c exited with code $code');
      if (identical(_process, proc)) {
        _process = null;
        _port = null;
        _secret = null;
      }
    }));

    // Wait until the RPC endpoint answers.
    await _waitForRpc();
    _log('RPC ready on port $port');
  }

  Future<void> _waitForRpc() async {
    Object? lastError;
    for (var i = 0; i < 50; i++) {
      try {
        await call('aria2.getVersion', []);
        return;
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    _log('RPC never became ready, last error: $lastError');
    throw Aria2Exception('aria2 RPC did not become ready: $lastError');
  }

  /// Adds a magnet/URI and returns its GID.
  Future<String> addUri(String uri, {Map<String, String>? options}) async {
    _log('addUri uri=${uri.length > 60 ? '${uri.substring(0, 60)}…' : uri} options=$options');
    final result = await call('aria2.addUri', [
      [uri],
      options ?? <String, String>{},
    ]);
    if (result is String) {
      _log('addUri -> gid=$result');
      return result;
    }
    throw const Aria2Exception('addUri returned no GID');
  }

  Future<Aria2Status> tellStatus(String gid) async {
    final result = await call('aria2.tellStatus', [
      gid,
      ['gid', 'status', 'totalLength', 'completedLength', 'followedBy', 'files', 'errorCode', 'errorMessage', 'bitfield', 'pieceLength', 'downloadSpeed'],
    ]);
    return Aria2Status.fromJson(result as Map<String, dynamic>);
  }

  Future<void> remove(String gid) async {
    try {
      await call('aria2.forceRemove', [gid]);
    } catch (_) {}
    try {
      await call('aria2.removeDownloadResult', [gid]);
    } catch (_) {}
  }

  /// Performs a JSON-RPC call. The secret token is injected as the first param.
  Future<dynamic> call(String method, List<dynamic> params) async {
    final port = _port;
    final secret = _secret;
    if (port == null || secret == null) throw const Aria2Exception('aria2 not started');

    final body = {
      'jsonrpc': '2.0',
      'id': _randomToken(),
      'method': method,
      'params': ['token:$secret', ...params],
    };
    // aria2 replies with content-type `application/json-rpc`, which dio does not
    // auto-decode, so fetch as plain text and parse manually.
    final response = await _dio.post(
      'http://127.0.0.1:$port/jsonrpc',
      data: jsonEncode(body),
      options: Options(contentType: 'application/json', responseType: ResponseType.plain),
    );
    final raw = response.data;
    final data = (raw is String ? jsonDecode(raw) : raw) as Map<String, dynamic>;
    if (data['error'] != null) {
      final err = data['error'] as Map<String, dynamic>;
      throw Aria2Exception('${err['message']} (code ${err['code']})');
    }
    return data['result'];
  }

  Future<void> dispose() async {
    final proc = _process;
    _process = null;
    if (proc != null) {
      try {
        await call('aria2.shutdown', []);
      } catch (_) {}
      proc.kill();
    }
  }

  String _randomToken() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
