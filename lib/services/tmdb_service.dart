import 'package:dio/dio.dart';

import '../models/media_info.dart';

/// Služba pro vyhledávání filmů a seriálů v TMDB databázi
class TmdbService {
  final Dio _dio;
  static const String _apiKey = '***REMOVED***'; // Bude potřeba získat API klíč
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  TmdbService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
  }

  /// Vyhledat film nebo seriál podle názvu
  Future<List<MediaInfo>> search({required String query, required String language, bool searchMovies = true, bool searchTV = true, int? year}) async {
    try {
      final results = <MediaInfo>[];

      // Vyhledat filmy
      if (searchMovies) {
        final movieResults = await _searchMovies(query, language, year);
        results.addAll(movieResults);
      }

      // Vyhledat seriály
      if (searchTV) {
        final tvResults = await _searchTV(query, language, year);
        results.addAll(tvResults);
      }

      // Seřadit podle popularity (ne hodnocení!)
      results.sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));

      return results;
    } catch (e) {
      print('TMDB search error: $e');
      return [];
    }
  }

  /// Vyhledat filmy
  Future<List<MediaInfo>> _searchMovies(String query, String language, int? year) async {
    try {
      final params = {'api_key': _apiKey, 'query': query, 'language': language, 'include_adult': 'false'};

      if (year != null) {
        params['year'] = year.toString();
      }

      final response = await _dio.get('/search/movie', queryParameters: params);

      final results = response.data['results'] as List;
      return results.map((json) => MediaInfo.fromJson(json, MediaType.movie)).toList();
    } catch (e) {
      print('Movie search error: $e');
      return [];
    }
  }

  /// Vyhledat seriály
  Future<List<MediaInfo>> _searchTV(String query, String language, int? year) async {
    try {
      final params = {'api_key': _apiKey, 'query': query, 'language': language, 'include_adult': 'false'};

      if (year != null) {
        params['first_air_date_year'] = year.toString();
      }

      final response = await _dio.get('/search/tv', queryParameters: params);

      final results = response.data['results'] as List;
      return results.map((json) => MediaInfo.fromJson(json, MediaType.tv)).toList();
    } catch (e) {
      print('TV search error: $e');
      return [];
    }
  }

  /// Získat detaily o filmu
  Future<MediaInfo?> getMovieDetails(int movieId, String language) async {
    try {
      final response = await _dio.get('/movie/$movieId', queryParameters: {'api_key': _apiKey, 'language': language});

      return MediaInfo.fromJson(response.data, MediaType.movie);
    } catch (e) {
      print('Get movie details error: $e');
      return null;
    }
  }

  /// Získat detaily o seriálu
  Future<MediaInfo?> getTVDetails(int tvId, String language) async {
    try {
      final response = await _dio.get('/tv/$tvId', queryParameters: {'api_key': _apiKey, 'language': language});

      return MediaInfo.fromJson(response.data, MediaType.tv);
    } catch (e) {
      print('Get TV details error: $e');
      return null;
    }
  }
}
