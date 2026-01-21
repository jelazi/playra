import 'package:hive_flutter/hive_flutter.dart';

import '../models/media_cache.dart';
import '../models/media_info.dart';

/// Služba pro správu cache přiřazení video názvů → TMDB info
class MediaCacheService {
  static const String _boxName = 'media_cache';
  static Box<MediaCache>? _box;

  static Future<void> init() async {
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MediaCacheAdapter());
    }
    _box = await Hive.openBox<MediaCache>(_boxName);
  }

  /// Uložit přiřazení názvu → media info
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

  /// Získat uložené info pro název
  static MediaCache? getMapping(String cleanName) {
    return _box?.get(cleanName.toLowerCase().trim());
  }

  /// Převést MediaCache na MediaInfo
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

  /// Smazat přiřazení
  static Future<void> deleteMapping(String cleanName) async {
    await _box?.delete(cleanName.toLowerCase().trim());
  }

  /// Smazat všechny přiřazení
  static Future<void> clearAll() async {
    await _box?.clear();
  }

  /// Získat všechny uložené názvy
  static List<String> getAllMappings() {
    return _box?.keys.cast<String>().toList() ?? [];
  }
}
