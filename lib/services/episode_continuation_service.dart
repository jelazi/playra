import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/video_item.dart';
import 'video_name_parser.dart';

/// Finds likely next episode files for local TV episode playback.
class EpisodeContinuationService {
  static Future<VideoItem?> findNextEpisode(VideoItem current) async {
    if (current.source != VideoSource.local) return null;

    final parsedCurrent = VideoNameParser.parse(current.uri);
    if (!parsedCurrent.isTV || parsedCurrent.season == null || parsedCurrent.episode == null) {
      return null;
    }

    final dir = Directory(p.dirname(current.uri));
    if (!await dir.exists()) return null;

    final entries = <VideoItem>[];
    try {
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
        if (!kSupportedVideoExtensions.contains(ext)) continue;

        final stat = await entity.stat();
        entries.add(
          VideoItem(
            id: entity.path,
            name: name,
            uri: entity.path,
            source: VideoSource.local,
            sizeBytes: stat.size,
            modified: stat.modified,
            folder: p.basename(p.dirname(entity.path)),
          ),
        );
      }
    } catch (_) {
      return null;
    }

    final currentSeriesKey = parsedCurrent.cleanName.trim().toLowerCase();

    final candidates = entries.where((video) {
      final parsed = VideoNameParser.parse(video.uri);
      if (!parsed.isTV || parsed.season == null || parsed.episode == null) return false;
      if (parsed.cleanName.trim().toLowerCase() != currentSeriesKey) return false;
      final season = parsed.season!;
      final episode = parsed.episode!;
      return season > parsedCurrent.season! || (season == parsedCurrent.season! && episode > parsedCurrent.episode!);
    }).toList();

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final pa = VideoNameParser.parse(a.uri);
      final pb = VideoNameParser.parse(b.uri);
      final seasonCmp = pa.season!.compareTo(pb.season!);
      if (seasonCmp != 0) return seasonCmp;
      final episodeCmp = pa.episode!.compareTo(pb.episode!);
      if (episodeCmp != 0) return episodeCmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return candidates.first;
  }
}
