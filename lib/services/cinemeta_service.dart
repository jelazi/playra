import 'package:dio/dio.dart';

import '../models/cinemeta_meta.dart';

/// Maps a movie title to its IMDB id (needed by Torrentio) using the public
/// Cinemeta addon from the Stremio ecosystem. Requires no API key.
class CinemetaService {
  CinemetaService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ));

  static const String _baseUrl = 'https://v3-cinemeta.strem.io';

  final Dio _dio;

  /// Searches movies by free-text [query]. Returns an ordered list of matches.
  Future<List<CinemetaMeta>> searchMovies(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final response = await _dio.get<Map<String, dynamic>>('/catalog/movie/top/search=${Uri.encodeComponent(trimmed)}.json');
    final metas = response.data?['metas'] as List?;
    if (metas == null) return const [];

    return metas
        .whereType<Map<String, dynamic>>()
        .map(CinemetaMeta.fromJson)
        .where((m) => m.imdbId.startsWith('tt'))
        .toList();
  }

  /// Fetches full metadata for a movie by IMDB id (optional richer details).
  Future<CinemetaMeta?> movieMeta(String imdbId) async {
    final response = await _dio.get<Map<String, dynamic>>('/meta/movie/$imdbId.json');
    final meta = response.data?['meta'] as Map<String, dynamic>?;
    if (meta == null) return null;
    return CinemetaMeta.fromJson(meta);
  }
}
