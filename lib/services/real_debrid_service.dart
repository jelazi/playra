import 'package:dio/dio.dart';

import '../models/torrent_stream.dart';
import 'magnet_builder.dart';

/// Raised when the Real-Debrid flow fails in a way worth surfacing to the user.
class RealDebridException implements Exception {
  final String message;
  final int? statusCode;
  const RealDebridException(this.message, {this.statusCode});

  bool get isAuthError => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'RealDebridException($statusCode): $message';
}

/// Resolves a Torrentio infoHash into a direct, unrestricted HTTPS URL using the
/// Real-Debrid REST API.
///
/// Flow: addMagnet -> selectFiles -> poll info until `downloaded` -> unrestrict.
class RealDebridService {
  RealDebridService({required this.apiKey, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ));

  static const String _baseUrl = 'https://api.real-debrid.com/rest/1.0';

  final String apiKey;
  final Dio _dio;

  Options get _auth => Options(headers: {'Authorization': 'Bearer $apiKey'});

  /// Resolves [stream] to a direct download URL. [onStatus] reports progress
  /// stages (e.g. while the torrent is being cached on Real-Debrid).
  Future<String> resolveDirectUrl(
    TorrentStream stream, {
    void Function(String status)? onStatus,
  }) async {
    if (apiKey.isEmpty) {
      throw const RealDebridException('Missing Real-Debrid API key', statusCode: 401);
    }
    if (!stream.hasInfoHash) {
      throw const RealDebridException('Stream has no info hash');
    }

    final magnet = MagnetBuilder.fromStream(stream);

    try {
      onStatus?.call('adding');
      final torrentId = await _addMagnet(magnet);

      onStatus?.call('selecting');
      await _selectFiles(torrentId, stream.fileIdx);

      onStatus?.call('caching');
      final link = await _waitForDownloadLink(torrentId, onStatus: onStatus);

      onStatus?.call('unrestricting');
      return await _unrestrict(link);
    } on DioException catch (e) {
      throw RealDebridException(
        e.response?.data?.toString() ?? e.message ?? 'Network error',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<String> _addMagnet(String magnet) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/torrents/addMagnet',
      data: {'magnet': magnet},
      options: _auth.copyWith(contentType: Headers.formUrlEncodedContentType),
    );
    final id = response.data?['id'] as String?;
    if (id == null) throw const RealDebridException('addMagnet returned no id');
    return id;
  }

  Future<void> _selectFiles(String torrentId, int fileIdx) async {
    // Real-Debrid file ids are 1-based; Torrentio fileIdx is 0-based. When the
    // mapping is uncertain we fall back to selecting all files.
    final candidate = fileIdx >= 0 ? '${fileIdx + 1}' : 'all';
    try {
      await _dio.post(
        '/torrents/selectFiles/$torrentId',
        data: {'files': candidate},
        options: _auth.copyWith(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException {
      await _dio.post(
        '/torrents/selectFiles/$torrentId',
        data: {'files': 'all'},
        options: _auth.copyWith(contentType: Headers.formUrlEncodedContentType),
      );
    }
  }

  Future<String> _waitForDownloadLink(
    String torrentId, {
    void Function(String status)? onStatus,
  }) async {
    const maxAttempts = 60; // ~3 minutes worst case
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final response = await _dio.get<Map<String, dynamic>>('/torrents/info/$torrentId', options: _auth);
      final data = response.data ?? const {};
      final status = data['status'] as String? ?? '';

      switch (status) {
        case 'downloaded':
          final links = (data['links'] as List?)?.whereType<String>().toList() ?? const [];
          if (links.isEmpty) throw const RealDebridException('Torrent has no links');
          return links.first;
        case 'magnet_error':
        case 'error':
        case 'virus':
        case 'dead':
          throw RealDebridException('Real-Debrid status: $status');
        default:
          final progress = (data['progress'] as num?)?.toInt() ?? 0;
          onStatus?.call('caching:$progress');
          await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    throw const RealDebridException('Timed out waiting for Real-Debrid to cache the torrent');
  }

  Future<String> _unrestrict(String link) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/unrestrict/link',
      data: {'link': link},
      options: _auth.copyWith(contentType: Headers.formUrlEncodedContentType),
    );
    final download = response.data?['download'] as String?;
    if (download == null || download.isEmpty) {
      throw const RealDebridException('unrestrict returned no download url');
    }
    return download;
  }
}
