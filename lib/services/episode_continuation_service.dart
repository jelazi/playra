import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/video_item.dart';

/// Finds likely next episode files for local TV episode playback.
class EpisodeContinuationService {
  static Future<VideoItem?> findNextEpisode(VideoItem current) async {
    if (current.source != VideoSource.local) return null;

    final currentTag = _extractSeasonEpisodeFromFileName(current.name);
    if (currentTag == null) {
      return null;
    }

    final currentSeriesKey = _seriesKeyFromFileName(current.name);
    if (currentSeriesKey.isEmpty) return null;

    final currentDir = Directory(p.dirname(current.uri));
    if (!await currentDir.exists()) return null;

    final searchRoot = _pickSearchRoot(currentDir);
    if (!await searchRoot.exists()) return null;

    final entries = <VideoItem>[];
    try {
      await for (final entity in searchRoot.list(recursive: true, followLinks: false)) {
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

    final candidates = entries.where((video) {
      if (video.id == current.id) return false;
      final key = _seriesKeyFromFileName(video.name);
      if (key != currentSeriesKey) return false;
      final tag = _extractSeasonEpisodeFromFileName(video.name);
      if (tag == null) return false;
      return tag.$1 > currentTag.$1 || (tag.$1 == currentTag.$1 && tag.$2 > currentTag.$2);
    }).toList();

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final ta = _extractSeasonEpisodeFromFileName(a.name)!;
      final tb = _extractSeasonEpisodeFromFileName(b.name)!;
      final seasonCmp = ta.$1.compareTo(tb.$1);
      if (seasonCmp != 0) return seasonCmp;
      final episodeCmp = ta.$2.compareTo(tb.$2);
      if (episodeCmp != 0) return episodeCmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return candidates.first;
  }

  static Directory _pickSearchRoot(Directory currentDir) {
    final name = p.basename(currentDir.path);
    final isSeasonFolder = RegExp(r'^(season\s*\d+|serie\s*\d+|s\d{1,2}|s\d{1,2}\s*[- ]\s*s?\d{1,2})$', caseSensitive: false).hasMatch(name.replaceAll(RegExp(r'[._\-+]'), ' '));

    if (!isSeasonFolder) return currentDir;
    return Directory(p.dirname(currentDir.path));
  }

  static (int, int)? _extractSeasonEpisodeFromFileName(String fileName) {
    final base = p.basenameWithoutExtension(fileName).replaceAll(RegExp(r'[._\-+]'), ' ');

    final sxe = RegExp(r'\b[Ss](\d{1,2})\s*[Ee](\d{1,2})\b').firstMatch(base);
    if (sxe != null) {
      final s = int.tryParse(sxe.group(1)!);
      final e = int.tryParse(sxe.group(2)!);
      if (s != null && e != null) return (s, e);
    }

    final xFormat = RegExp(r'\b(\d{1,2})x(\d{1,2})\b', caseSensitive: false).firstMatch(base);
    if (xFormat != null) {
      final s = int.tryParse(xFormat.group(1)!);
      final e = int.tryParse(xFormat.group(2)!);
      if (s != null && e != null) return (s, e);
    }

    return null;
  }

  static String _seriesKeyFromFileName(String fileName) {
    var v = p.basenameWithoutExtension(fileName);
    v = v.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    v = v.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    v = v.replaceAll(RegExp(r'[._\-+]+'), ' ');
    v = v.replaceAll(RegExp(r'\b[Ss]\d{1,2}\s*[Ee]\d{1,2}\b'), ' ');
    v = v.replaceAll(RegExp(r'\b\d{1,2}x\d{1,2}\b', caseSensitive: false), ' ');
    v = v.replaceAll(
      RegExp(
        r'\b(480p|576p|720p|1080p|2160p|4k|uhd|hdr|bluray|brrip|bdrip|web\s*-?\s*dl|webrip|hdtv|dvdrip|remux|proper|repack|extended|unrated|x264|x265|h\s*\.?\s*264|h\s*\.?\s*265|hevc|xvid|av1|10bit|8bit|aac|ac3|dts|ddp|atmos|amzn|nf|dsnp|hmax|hulu|itunes|yts|rarbg|yify|ntb|evo|etrg)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    v = v.replaceAll(RegExp(r'\b\d+(\.\d+)?\s?(mb|gb|kb)\b', caseSensitive: false), ' ');
    v = v.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    return v;
  }
}
