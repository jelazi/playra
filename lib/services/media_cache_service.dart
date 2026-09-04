import 'package:hive_flutter/hive_flutter.dart';

import '../models/media_cache.dart';
import '../models/media_info.dart';

/// Manages the cache mapping video names to TMDB info.
class MediaCacheService {
  static const String _boxName = 'media_cache';
  static Box<MediaCache>? _box;

  static Future<void> init() async {
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MediaCacheAdapter());
    }
    _box = await Hive.openBox<MediaCache>(_boxName);
  }

  /// Stores a name → media info mapping.
  static Future<void> saveMapping(String cleanName, MediaInfo mediaInfo) async {
    final cache = MediaCache(
      cleanName: cleanName.toLowerCase().trim(),
      tmdbId: mediaInfo.id,
      mediaType: mediaInfo.type == MediaType.movie ? 'movie' : 'tv',
      title: mediaInfo.title,
      originalTitle: mediaInfo.originalTitle,
      overview: mediaInfo.overview,
      posterPath: mediaInfo.posterPath,
      releaseDate: mediaInfo.releaseDate,
      voteAverage: mediaInfo.voteAverage,
      genres: mediaInfo.genres,
      numberOfSeasons: mediaInfo.numberOfSeasons,
      numberOfEpisodes: mediaInfo.numberOfEpisodes,
    );

    await _box?.put(cleanName.toLowerCase().trim(), cache);
  }

  /// Returns the stored info for a name.
  static MediaCache? getMapping(String cleanName) {
    return _box?.get(cleanName.toLowerCase().trim());
  }

  /// Converts a MediaCache entry into MediaInfo.
  static MediaInfo cacheToMediaInfo(MediaCache cache) {
    return MediaInfo(
      id: cache.tmdbId,
      title: cache.title,
      originalTitle: cache.originalTitle,
      overview: cache.overview,
      posterPath: cache.posterPath,
      releaseDate: cache.releaseDate,
      voteAverage: cache.voteAverage,
      genres: cache.genres ?? [],
      type: cache.mediaType == 'movie' ? MediaType.movie : MediaType.tv,
      numberOfSeasons: cache.numberOfSeasons,
      numberOfEpisodes: cache.numberOfEpisodes,
    );
  }

  /// Deletes a single mapping.
  static Future<void> deleteMapping(String cleanName) async {
    await _box?.delete(cleanName.toLowerCase().trim());
  }

  /// Deletes every mapping.
  static Future<void> clearAll() async {
    await _box?.clear();
  }

  /// Returns every stored name.
  static List<String> getAllMappings() {
    return _box?.keys.cast<String>().toList() ?? [];
  }
}
