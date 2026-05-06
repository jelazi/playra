import '../models/media_info.dart';
import 'media_cache_service.dart';
import 'tmdb_service.dart';
import 'video_name_parser.dart';

/// Result of an automatic media lookup for a local video file.
class MediaLookupResult {
  final MediaInfo mediaInfo;
  final ParsedVideoName parsed;

  /// True if the result came from the local Hive cache.
  final bool fromCache;

  const MediaLookupResult({required this.mediaInfo, required this.parsed, required this.fromCache});
}

/// Provides TMDB media lookups with a local Hive cache layer.
///
/// This is the extracted core of the lookup logic previously embedded in
/// [VideoLibraryScreen] so it can be reused from [MediaInfoScreen] and
/// [HomeScreen].
class MediaLookupService {
  final TmdbService _tmdb;

  MediaLookupService(this._tmdb);

  /// Looks up media info for [filePath].
  ///
  /// - If a mapping is already cached, details are refreshed from TMDB and
  ///   returned immediately.
  /// - Otherwise the top TMDB result (by popularity) is used automatically
  ///   and cached — no user interaction required.
  /// - Returns `null` if no result could be found.
  Future<MediaLookupResult?> lookupForFile(String filePath, String language) async {
    final parsed = VideoNameParser.parse(filePath);

    // Cache hit → refresh details from TMDB in the requested language.
    final cached = MediaCacheService.getMapping(parsed.cleanName);
    if (cached != null) {
      final MediaInfo? details = cached.mediaType == 'movie' ? await _tmdb.getMovieDetails(cached.tmdbId, language) : await _tmdb.getTVDetails(cached.tmdbId, language);
      final info = details ?? MediaCacheService.cacheToMediaInfo(cached);
      return MediaLookupResult(mediaInfo: info, parsed: parsed, fromCache: true);
    }

    // No cache: search TMDB.
    final results = await _tmdb.search(query: parsed.cleanName, language: language, searchMovies: !parsed.isTV, searchTV: parsed.isTV, year: parsed.year);

    if (results.isEmpty) return null;

    // Auto-pick top result by popularity.
    final best = results.reduce((a, b) => (a.popularity ?? 0) >= (b.popularity ?? 0) ? a : b);

    // Fetch full details.
    final MediaInfo? details = best.type == MediaType.movie ? await _tmdb.getMovieDetails(best.id, language) : await _tmdb.getTVDetails(best.id, language);

    final finalInfo = details ?? best;

    // Persist to cache.
    await MediaCacheService.saveMapping(parsed.cleanName, finalInfo);

    return MediaLookupResult(mediaInfo: finalInfo, parsed: parsed, fromCache: false);
  }

  /// Returns candidate results from TMDB for a manual/override search.
  Future<List<MediaInfo>> searchCandidates(String query, String language, {bool movies = true, bool tv = true}) async {
    return _tmdb.search(query: query, language: language, searchMovies: movies, searchTV: tv);
  }

  /// Fetches English episode synopsis for a TV episode.
  Future<EpisodeInfo?> fetchEpisodeInfo(int tvId, int season, int episode) => _tmdb.getEpisodeDetails(tvId, season, episode);

  /// Persists a user-selected [mediaInfo] for [filePath] to the local cache.
  Future<void> saveMapping(String filePath, MediaInfo mediaInfo) async {
    final parsed = VideoNameParser.parse(filePath);
    await MediaCacheService.saveMapping(parsed.cleanName, mediaInfo);
  }
}
