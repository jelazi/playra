import 'dart:async';

import '../models/media_info.dart';
import 'media_cache_service.dart';
import 'media_sidecar_service.dart';
import 'playra_storage.dart';
import 'tmdb_service.dart';
import 'video_name_parser.dart';

/// Result of an automatic media lookup for a local video file.
class MediaLookupResult {
  final MediaInfo mediaInfo;
  final ParsedVideoName parsed;

  /// True if the result came from the local Hive cache or the `.nfo` next to the video.
  final bool fromCache;

  /// The episode, for a TV file whose season and episode are known.
  final EpisodeInfo? episode;

  const MediaLookupResult({required this.mediaInfo, required this.parsed, required this.fromCache, this.episode});
}

/// Provides TMDB media lookups with a local Hive cache layer and `.nfo`
/// sidecar files shared with other devices and players.
///
/// This is the extracted core of the lookup logic previously embedded in
/// [VideoLibraryScreen] so it can be reused from [MediaInfoScreen] and
/// [HomeScreen].
class MediaLookupService {
  final TmdbService _tmdb;
  final MediaSidecarService _sidecars;

  MediaLookupService(this._tmdb, {MediaSidecarService? sidecars}) : _sidecars = sidecars ?? MediaSidecarService();

  /// Looks up media info for [filePath].
  ///
  /// - An `.nfo` next to the video wins: its TMDB id is refreshed from TMDB
  ///   (or used as stored when offline).
  /// - Otherwise a mapping already cached for this file or name is used.
  /// - Otherwise the top TMDB result (by popularity) is used automatically
  ///   and cached — no user interaction required.
  /// - Whatever was found is written next to the video as `.nfo` files
  ///   unless they already exist.
  /// - Returns `null` if no result could be found.
  Future<MediaLookupResult?> lookupForFile(String filePath, String language, {String? videoHash}) async {
    final parsed = VideoNameParser.parse(filePath);

    final sidecar = await _sidecars.read(filePath, parsed);
    if (sidecar != null) {
      final info = await _details(sidecar.media, language) ?? sidecar.media;
      await _remember(parsed, info, videoHash);
      final episode = await _episodeFor(info, parsed, language) ?? sidecar.episode;
      unawaited(_sidecars.write(filePath, parsed, info, episode: episode));
      return MediaLookupResult(mediaInfo: info, parsed: parsed, fromCache: true, episode: episode);
    }

    if (videoHash != null && videoHash.isNotEmpty) {
      final byHash = PlayraStorage.getMediaInfoForHash(videoHash);
      if (byHash != null) {
        final info = _mediaInfoFromStoredMap(byHash);
        if (info != null) {
          return _finish(filePath, parsed, info, language, fromCache: true);
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
      return _finish(filePath, parsed, info, language, fromCache: true);
    }

    // No cache: search TMDB.
    final results = await _tmdb.search(query: parsed.cleanName, language: language, searchMovies: !parsed.isTV, searchTV: parsed.isTV, year: parsed.year);

    if (results.isEmpty) return null;

    // Auto-pick top result by popularity.
    final best = results.reduce((a, b) => (a.popularity ?? 0) >= (b.popularity ?? 0) ? a : b);

    final finalInfo = await _details(best, language) ?? best;
    await _remember(parsed, finalInfo, videoHash);

    return _finish(filePath, parsed, finalInfo, language, fromCache: false);
  }

  /// Returns candidate results from TMDB for a manual/override search.
  Future<List<MediaInfo>> searchCandidates(String query, String language, {bool movies = true, bool tv = true}) async {
    return _tmdb.search(query: query, language: language, searchMovies: movies, searchTV: tv);
  }

  /// Fetches localized episode info for a TV episode.
  Future<EpisodeInfo?> fetchEpisodeInfo(int tvId, int season, int episode, String language) =>
      _tmdb.getEpisodeDetails(tvId, season, episode, language: language);

  /// Stores a user-selected [picked] for [filePath] and overwrites the `.nfo`
  /// files next to it. Returns false when they could not be written.
  Future<bool> saveManualPick(String filePath, MediaInfo picked, String language, {String? videoHash}) async {
    final parsed = VideoNameParser.parse(filePath);
    final info = await _details(picked, language) ?? picked;
    await _remember(parsed, info, videoHash);
    final episode = await _episodeFor(info, parsed, language);
    return _sidecars.write(filePath, parsed, info, episode: episode, overwrite: true);
  }

  Future<MediaLookupResult> _finish(String filePath, ParsedVideoName parsed, MediaInfo info, String language, {required bool fromCache}) async {
    final episode = await _episodeFor(info, parsed, language);
    unawaited(_sidecars.write(filePath, parsed, info, episode: episode));
    return MediaLookupResult(mediaInfo: info, parsed: parsed, fromCache: fromCache, episode: episode);
  }

  Future<MediaInfo?> _details(MediaInfo media, String language) =>
      media.type == MediaType.movie ? _tmdb.getMovieDetails(media.id, language) : _tmdb.getTVDetails(media.id, language);

  Future<EpisodeInfo?> _episodeFor(MediaInfo media, ParsedVideoName parsed, String language) async {
    if (media.type != MediaType.tv || parsed.season == null || parsed.episode == null) return null;
    return _tmdb.getEpisodeDetails(media.id, parsed.season!, parsed.episode!, language: language);
  }

  Future<void> _remember(ParsedVideoName parsed, MediaInfo info, String? videoHash) async {
    await MediaCacheService.saveMapping(parsed.cleanName, info);
    if (videoHash != null && videoHash.isNotEmpty) {
      await PlayraStorage.saveMediaInfoForHash(videoHash, _mediaInfoToStoredMap(info));
    }
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
