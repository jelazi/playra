import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_info.dart';

/// Downloads and caches small TMDB poster images for local reuse in recents.
class PosterCacheService {
  static final Dio _dio = Dio()
    ..options.connectTimeout = const Duration(seconds: 10)
    ..options.receiveTimeout = const Duration(seconds: 15);

  static Future<String?> cacheSmallPoster(MediaInfo media) async {
    if (media.posterPath == null || media.posterPath!.isEmpty) {
      return null;
    }

    try {
      final dir = await getApplicationSupportDirectory();
      final postersDir = Directory(p.join(dir.path, 'poster_cache'));
      if (!await postersDir.exists()) {
        await postersDir.create(recursive: true);
      }

      final filePath = p.join(postersDir.path, '${media.type.name}_${media.id}_w185.jpg');
      final file = File(filePath);
      if (await file.exists()) {
        return filePath;
      }

      final url = 'https://image.tmdb.org/t/p/w185${media.posterPath}';
      final response = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;

      await file.writeAsBytes(bytes, flush: true);
      return filePath;
    } catch (_) {
      return null;
    }
  }
}
