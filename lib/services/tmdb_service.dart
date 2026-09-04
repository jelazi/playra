import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../models/media_info.dart';
import 'secret_store.dart';
import 'translation_service.dart';

/// Searches the TMDB database for movies and TV shows.
class TmdbService {
  final Dio _dio;
  final TranslationService _translator;

  /// Optional build-time key: `--dart-define=TMDB_API_KEY=...`.
  static const String _apiKeyDefine = String.fromEnvironment('TMDB_API_KEY');
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  /// Resolves the TMDB key: a build-time define wins, otherwise the key the
  /// user entered in Settings. Empty when neither is set.
  static String get _apiKey {
    if (_apiKeyDefine.isNotEmpty) return _apiKeyDefine.trim();
    return SecretStore.tmdbApiKey;
  }

  /// Without a key every TMDB lookup returns empty, so callers can tell
  /// "nothing found" apart from "not configured".
  static bool get isConfigured => _apiKey.isNotEmpty;

  /// True when the key was baked in at build time and Settings cannot override it.
  static bool get isKeyFixedAtBuildTime => _apiKeyDefine.trim().isNotEmpty;

  /// TMDB v3 keys are 32 hexadecimal characters; catching a malformed one here
  /// keeps a mistyped key from being stored and silently failing every lookup.
  static bool isWellFormedKey(String key) => RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(key.trim());

  TmdbService({Dio? dio, TranslationService? translator}) : _dio = dio ?? Dio(), _translator = translator ?? TranslationService() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
  }

  /// Asks TMDB whether [key] is accepted, so Settings can reject a bad key
  /// before storing it.
  Future<bool> verifyKey(String key) async {
    final candidate = key.trim();
    if (!isWellFormedKey(candidate)) return false;
    try {
      final response = await _dio.get('/authentication', queryParameters: {'api_key': candidate});
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('TMDB key verification failed: ${_redact(e, candidate)}');
      return false;
    }
  }

  /// Dio puts the full request URI — query string included — into its error
  /// messages, so anything logged has to have the key stripped out first.
  static String _redact(Object error, [String? key]) {
    final secret = key ?? _apiKey;
    final text = error.toString();
    return secret.isEmpty ? text : text.replaceAll(secret, '***');
  }

  /// Searches for a movie or TV show by title.
  Future<List<MediaInfo>> search({required String query, required String language, bool searchMovies = true, bool searchTV = true, int? year}) async {
    if (!isConfigured) {
      debugPrint('TMDB: no API key. Add one in Settings, or pass --dart-define=TMDB_API_KEY=<key>.');
      return [];
    }

    try {
      final results = <MediaInfo>[];

      // Movies
      if (searchMovies) {
        final movieResults = await _searchMovies(query, language, year);
        results.addAll(movieResults);
      }

      // TV shows
      if (searchTV) {
        final tvResults = await _searchTV(query, language, year);
        results.addAll(tvResults);
      }

      // Sort by popularity, not by rating.
      results.sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));

      return results;
    } catch (e) {
      debugPrint('TMDB search error: ${_redact(e)}');
      return [];
    }
  }

  /// Searches for movies.
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
      debugPrint('Movie search error: ${_redact(e)}');
      return [];
    }
  }

  /// Searches for TV shows.
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
      debugPrint('TV search error: ${_redact(e)}');
      return [];
    }
  }

  /// Fetches movie details.
  Future<MediaInfo?> getMovieDetails(int movieId, String language) async {
    try {
      final response = await _dio.get('/movie/$movieId', queryParameters: {'api_key': _apiKey, 'language': language});

      return MediaInfo.fromJson(response.data, MediaType.movie);
    } catch (e) {
      debugPrint('Get movie details error: ${_redact(e)}');
      return null;
    }
  }

  /// Fetches TV show details.
  Future<MediaInfo?> getTVDetails(int tvId, String language) async {
    try {
      final response = await _dio.get('/tv/$tvId', queryParameters: {'api_key': _apiKey, 'language': language});

      return MediaInfo.fromJson(response.data, MediaType.tv);
    } catch (e) {
      debugPrint('Get TV details error: ${_redact(e)}');
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
      debugPrint('Get episode details error: ${_redact(e)}');
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
