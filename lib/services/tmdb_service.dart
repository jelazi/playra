import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../models/media_info.dart';
import 'translation_service.dart';

/// Služba pro vyhledávání filmů a seriálů v TMDB databázi
class TmdbService {
  final Dio _dio;
  final TranslationService _translator;
  static const String _apiKey = '***REMOVED***'; // Bude potřeba získat API klíč
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  TmdbService({Dio? dio, TranslationService? translator}) : _dio = dio ?? Dio(), _translator = translator ?? TranslationService() {
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
      debugPrint('TMDB search error: $e');
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
      debugPrint('Movie search error: $e');
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
      debugPrint('TV search error: $e');
      return [];
    }
  }

  /// Získat detaily o filmu
  Future<MediaInfo?> getMovieDetails(int movieId, String language) async {
    try {
      final response = await _dio.get('/movie/$movieId', queryParameters: {'api_key': _apiKey, 'language': language});

      return MediaInfo.fromJson(response.data, MediaType.movie);
    } catch (e) {
      debugPrint('Get movie details error: $e');
      return null;
    }
  }

  /// Získat detaily o seriálu
  Future<MediaInfo?> getTVDetails(int tvId, String language) async {
    try {
      final response = await _dio.get('/tv/$tvId', queryParameters: {'api_key': _apiKey, 'language': language});

      return MediaInfo.fromJson(response.data, MediaType.tv);
    } catch (e) {
      debugPrint('Get TV details error: $e');
      return null;
    }
  }

  /// Fetch episode details including localized episode metadata.
  /// Falls back to English and machine translation when the localized TMDB
  /// episode text is missing.
  Future<EpisodeInfo?> getEpisodeDetails(int tvId, int season, int episode, {String language = 'en-US'}) async {
    try {
      final localizedResponse = await _dio.get('/tv/$tvId/season/$season/episode/$episode', queryParameters: {'api_key': _apiKey, 'language': language});
      final localized = EpisodeInfo.fromJson(localizedResponse.data as Map<String, dynamic>, season, episode);

      if (language.toLowerCase().startsWith('en')) {
        return localized;
      }

      final needsNameTranslation = (localized.name == null || localized.name!.trim().isEmpty);
      final needsOverviewTranslation = (localized.overview == null || localized.overview!.trim().isEmpty);

      if (!needsNameTranslation && !needsOverviewTranslation) {
        return localized;
      }

      final englishResponse = await _dio.get('/tv/$tvId/season/$season/episode/$episode', queryParameters: {'api_key': _apiKey, 'language': 'en-US'});
      final english = EpisodeInfo.fromJson(englishResponse.data as Map<String, dynamic>, season, episode);

      final translatedName = needsNameTranslation && english.name != null
          ? await _translator.translateText(english.name!, targetLanguage: _normalizeLanguage(language), sourceLanguage: 'en')
          : null;
      final translatedOverview = needsOverviewTranslation && english.overview != null
          ? await _translator.translateText(english.overview!, targetLanguage: _normalizeLanguage(language), sourceLanguage: 'en')
          : null;

      return localized.copyWith(
        name: localized.name?.trim().isNotEmpty == true ? localized.name : translatedName ?? english.name,
        overview: localized.overview?.trim().isNotEmpty == true ? localized.overview : translatedOverview ?? english.overview,
        stillPath: localized.stillPath ?? english.stillPath,
        voteAverage: localized.voteAverage ?? english.voteAverage,
        airDate: localized.airDate ?? english.airDate,
      );
    } catch (e) {
      debugPrint('Get episode details error: $e');
      return null;
    }
  }

  String _normalizeLanguage(String language) {
    if (language.contains('-')) {
      return language.split('-').first.toLowerCase();
    }
    if (language.contains('_')) {
      return language.split('_').first.toLowerCase();
    }
    return language.toLowerCase();
  }
}
