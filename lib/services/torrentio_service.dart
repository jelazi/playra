import 'package:dio/dio.dart';

import '../models/torrent_stream.dart';

/// Queries the Torrentio addon for available streams of a movie/episode.
///
/// Torrentio exposes a Stremio-style endpoint:
///   `https://torrentio.strem.fun/<config>/stream/<type>/<id>.json`
class TorrentioService {
  TorrentioService({Dio? dio, this.config = _defaultConfig})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ));

  static const String _baseUrl = 'https://torrentio.strem.fun';

  /// Default config segment: sort by quality then size, keep providers default.
  static const String _defaultConfig = 'sort=qualitysize';

  /// Config segment placed in the URL path. Append `realdebrid=<key>` to have
  /// Torrentio resolve direct HTTPS URLs server-side.
  final String config;

  final Dio _dio;

  /// Returns a Torrentio instance whose config also carries a Real-Debrid key,
  /// so streams come back with direct `url`s already unrestricted.
  TorrentioService withRealDebrid(String apiKey) {
    if (apiKey.isEmpty) return this;
    return TorrentioService(dio: _dio, config: '$config|realdebrid=$apiKey');
  }

  Future<List<TorrentStream>> movieStreams(String imdbId) {
    return _streams('movie', imdbId);
  }

  Future<List<TorrentStream>> seriesStreams(String imdbId, int season, int episode) {
    return _streams('series', '$imdbId:$season:$episode');
  }

  Future<List<TorrentStream>> _streams(String type, String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/$config/stream/$type/$id.json');
    final streams = response.data?['streams'] as List?;
    if (streams == null) return const [];
    return streams.whereType<Map<String, dynamic>>().map(TorrentStream.fromJson).toList();
  }

  /// Applies the user's quality / min-seeders filters and sorts best-first.
  static List<TorrentStream> applyFilters(
    List<TorrentStream> streams, {
    String preferredQuality = '',
    int minSeeders = 0,
  }) {
    var result = streams.where((s) => (s.seeders ?? 0) >= minSeeders).toList();
    if (preferredQuality.isNotEmpty) {
      final preferred = result.where((s) => s.quality == preferredQuality).toList();
      if (preferred.isNotEmpty) result = preferred;
    }
    result.sort((a, b) => (b.seeders ?? 0).compareTo(a.seeders ?? 0));
    return result;
  }
}
