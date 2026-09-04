import '../models/media_info.dart';
import 'media_cache_service.dart';
import 'playra_storage.dart';
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
  Future<MediaLookupResult?> lookupForFile(String filePath, String language, {String? videoHash}) async {
    final parsed = VideoNameParser.parse(filePath);

    if (videoHash != null && videoHash.isNotEmpty) {
      final byHash = PlayraStorage.getMediaInfoForHash(videoHash);
      if (byHash != null) {
        final info = _mediaInfoFromStoredMap(byHash);
        if (info != null) {
          return MediaLookupResult(mediaInfo: info, parsed: parsed, fromCache: true);
        }
      }
    }

    // Cache hit → refresh details from TMDB in the requested language.
    final cached = MediaCacheService.getMapping(parsed.cleanName);
    if (cached != null) {
      final MediaInfo? details = cached.mediaType == 'movie'
          ? await _tmdb.getMovieDetails(cached.tmdbId, language)
          : await _tmdb.getTVDetails(cached.tmdbId, language);
      final info = details ?? MediaCacheService.cacheToMediaInfo(cached);
      if (videoHash != null && videoHash.isNotEmpty) {
        await PlayraStorage.saveMediaInfoForHash(videoHash, _mediaInfoToStoredMap(info));
      }
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
    if (videoHash != null && videoHash.isNotEmpty) {
      await PlayraStorage.saveMediaInfoForHash(videoHash, _mediaInfoToStoredMap(finalInfo));
    }

    return MediaLookupResult(mediaInfo: finalInfo, parsed: parsed, fromCache: false);
  }

  /// Returns candidate results from TMDB for a manual/override search.
  Future<List<MediaInfo>> searchCandidates(String query, String language, {bool movies = true, bool tv = true}) async {
    return _tmdb.search(query: query, language: language, searchMovies: movies, searchTV: tv);
  }

  /// Fetches localized episode info for a TV episode.
  Future<EpisodeInfo?> fetchEpisodeInfo(int tvId, int season, int episode, String language) =>
      _tmdb.getEpisodeDetails(tvId, season, episode, language: language);

  /// Persists a user-selected [mediaInfo] for [filePath] to the local cache.
  Future<void> saveMapping(String filePath, MediaInfo mediaInfo) async {
    final parsed = VideoNameParser.parse(filePath);
    await MediaCacheService.saveMapping(parsed.cleanName, mediaInfo);
  }

  Map<String, dynamic> _mediaInfoToStoredMap(MediaInfo media) {
    return <String, dynamic>{
      'id': media.id,
      'title': media.title,
      'originalTitle': media.originalTitle,
      'overview': media.overview,
      'posterPath': media.posterPath,
      'backdropPath': media.backdropPath,
      'releaseDate': media.releaseDate,
      'voteAverage': media.voteAverage,
      'popularity': media.popularity,
      'genres': media.genres,
      'type': media.type.name,
      'numberOfSeasons': media.numberOfSeasons,
      'numberOfEpisodes': media.numberOfEpisodes,
      'firstAirDate': media.firstAirDate,
    };
  }

  MediaInfo? _mediaInfoFromStoredMap(Map<String, dynamic> map) {
    try {
      return MediaInfo(
        id: map['id'] as int,
        title: (map['title'] as String?) ?? '',
        originalTitle: (map['originalTitle'] as String?) ?? '',
        overview: map['overview'] as String?,
        posterPath: map['posterPath'] as String?,
        backdropPath: map['backdropPath'] as String?,
        releaseDate: map['releaseDate'] as String?,
        voteAverage: (map['voteAverage'] as num?)?.toDouble(),
        popularity: (map['popularity'] as num?)?.toDouble(),
        genres: (map['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        type: ((map['type'] as String?) ?? 'movie') == 'tv' ? MediaType.tv : MediaType.movie,
        numberOfSeasons: map['numberOfSeasons'] as int?,
        numberOfEpisodes: map['numberOfEpisodes'] as int?,
        firstAirDate: map['firstAirDate'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
