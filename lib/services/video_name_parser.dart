import 'package:path/path.dart' as path;

/// Parses a video file name to extract the movie or TV show title.
class VideoNameParser {
  /// Extracts the movie or TV show title from a file name.
  static ParsedVideoName parse(String filePath) {
    final fileName = path.basenameWithoutExtension(filePath);
    final ancestorNames = _ancestorDirectoryNames(filePath, maxDepth: 4);
    final parentDirName = ancestorNames.isNotEmpty ? ancestorNames[0] : '';
    final grandParentDirName = ancestorNames.length > 1 ? ancestorNames[1] : '';

    final seasonEpisodeFromFile = _extractSeasonEpisode(fileName);
    (int, int)? seasonEpisode;
    seasonEpisode = seasonEpisodeFromFile;
    if (seasonEpisode == null) {
      for (final dirName in ancestorNames) {
        seasonEpisode = _extractSeasonEpisode(dirName);
        if (seasonEpisode != null) break;
      }
    }

    final season = seasonEpisode?.$1;
    final episode = seasonEpisode?.$2;
    final isTV = season != null && episode != null;

    final year = _extractYear(fileName);

    var cleanName = _sanitizeTitleCandidate(fileName, removeYear: true);

    // Prefer directory-derived titles when they provide a better signal.
    final directoryCandidate = _deriveDirectoryTitle(ancestorNames, isTV);
    if (isTV) {
      if (_isUsableDirectoryName(directoryCandidate)) {
        cleanName = directoryCandidate!;
      }
    } else {
      if ((cleanName.length < 3 || !RegExp(r'[A-Za-z]').hasMatch(cleanName)) && _isUsableDirectoryName(directoryCandidate)) {
        cleanName = directoryCandidate!;
      }
    }

    if (cleanName.isEmpty) {
      cleanName = _sanitizeTitleCandidate(parentDirName, removeYear: true);
    }
    if (cleanName.isEmpty) {
      cleanName = _sanitizeTitleCandidate(grandParentDirName, removeYear: true);
    }
    if (cleanName.isEmpty) {
      cleanName = fileName.replaceAll(RegExp(r'[\._\-\+]'), ' ').trim();
    }

    return ParsedVideoName(originalFileName: fileName, cleanName: cleanName, isTV: isTV, season: season, episode: episode, year: year);
  }

  static String? _deriveDirectoryTitle(List<String> ancestors, bool isTV) {
    final seasonFolderPattern = RegExp(
      r'^(season\s*\d+|serie\s*\d+|s\d{1,2}|s\d{1,2}\s*[- ]\s*s?\d{1,2}|series\s*\d+\s*[- ]\s*\d+)$',
      caseSensitive: false,
    );

    // Keep close-to-file ordering: parent -> grandparent -> ...
    final cleaned = ancestors
        .map((name) => _sanitizeTitleCandidate(name, removeYear: true))
        .toList();

    if (isTV) {
      // If parent is a season folder, prefer the next usable ancestor.
      if (cleaned.isNotEmpty && seasonFolderPattern.hasMatch(cleaned.first)) {
        for (var i = 1; i < cleaned.length; i++) {
          if (_isUsableDirectoryName(cleaned[i])) return cleaned[i];
        }
      }

      for (final candidate in cleaned) {
        if (_isUsableDirectoryName(candidate) && !seasonFolderPattern.hasMatch(candidate)) {
          return candidate;
        }
      }
      return null;
    }

    for (final candidate in cleaned) {
      if (_isUsableDirectoryName(candidate) && !seasonFolderPattern.hasMatch(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static List<String> _ancestorDirectoryNames(String filePath, {int maxDepth = 4}) {
    final result = <String>[];
    var current = path.dirname(filePath);
    for (var i = 0; i < maxDepth; i++) {
      final base = path.basename(current);
      if (base.isEmpty || base == '.' || base == path.separator) break;
      result.add(base);
      final next = path.dirname(current);
      if (next == current) break;
      current = next;
    }
    return result;
  }

  static bool _isUsableDirectoryName(String? value) {
    if (value == null || value.isEmpty) return false;
    final lowered = value.trim().toLowerCase();
    const generic = {
      'media',
      'movie',
      'movies',
      'video',
      'videos',
      'serial',
      'serialy',
      'series',
      'shows',
      'tv',
      'downloads',
      'download',
      'new',
      'temp',
      'tmp',
    };
    if (generic.contains(lowered)) return false;
    return RegExp(r'[A-Za-z]').hasMatch(value);
  }

  static String _sanitizeTitleCandidate(String input, {required bool removeYear}) {
    var value = input;
    value = value.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    value = value.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    value = value.replaceAll(RegExp(r'[\._\-\+]+'), ' ');

    // Remove season/episode markers in multiple common formats.
    value = value.replaceAll(RegExp(r'\b[Ss]\d{1,2}\s*[Ee]\d{1,2}\b'), ' ');
    value = value.replaceAll(RegExp(r'\b\d{1,2}x\d{1,2}\b', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\b[Ss]\d{1,2}\s*[-–]\s*[Ss]?\d{1,2}\b'), ' ');
    value = value.replaceAll(RegExp(r'\b[Ee]\d{1,2}\s*[-–]\s*[Ee]?\d{1,2}\b'), ' ');
    value = value.replaceAll(RegExp(r'\bseasons?\s*\d{1,2}\s*[-–]\s*\d{1,2}\b', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\bseries\s*\d{1,2}\s*[-–]\s*\d{1,2}\b', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\bseason\s*\d{1,2}\b', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\bserie\s*\d{1,2}\b', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\b[Ss]\d{1,2}\b'), ' ');

    // Remove release/encoding/source tokens often present in file or folder names.
    value = value.replaceAll(
      RegExp(
        r'\b(480p|576p|720p|1080p|1440p|2160p|4k|uhd|hdr|hdr10|dolby\s*vision|dv|'
        r'bluray|brrip|bdrip|web\s*-?\s*dl|webrip|hdtv|dvdrip|remux|proper|repack|extended|unrated|imax|'
        r'x264|x265|h\s*\.?\s*264|h\s*\.?\s*265|hevc|xvid|av1|10bit|8bit|'
        r'aac|ac3|dts|ddp|ddp\s*\d(?:[\s\._-]*\d)?|atmos|dual\s*audio|multi|'
        r'amzn|nf|dsnp|hmax|hulu|itunes|yts|rarbg|yify|ntb|evo|etrg)\b',
        caseSensitive: false,
      ),
      ' ',
    );

    // Remove common channel layout leftovers.
    value = value.replaceAll(RegExp(r'\b(2[\s\._-]*0|5[\s\._-]*1|7[\s\._-]*1)\b', caseSensitive: false), ' ');

    // Remove file size markers.
    value = value.replaceAll(RegExp(r'\b\d+(\.\d+)?\s?(mb|gb|kb)\b', caseSensitive: false), ' ');

    if (removeYear) {
      value = value.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    }

    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value;
  }

  static (int, int)? _extractSeasonEpisode(String input) {
    final normalized = input.replaceAll(RegExp(r'[\._\-\+]'), ' ');

    final sxe = RegExp(r'\b[Ss](\d{1,2})\s*[Ee](\d{1,2})\b').firstMatch(normalized);
    if (sxe != null) {
      final season = int.tryParse(sxe.group(1)!);
      final episode = int.tryParse(sxe.group(2)!);
      if (season != null && episode != null) return (season, episode);
    }

    final xFormat = RegExp(r'\b(\d{1,2})x(\d{1,2})\b', caseSensitive: false).firstMatch(normalized);
    if (xFormat != null) {
      final season = int.tryParse(xFormat.group(1)!);
      final episode = int.tryParse(xFormat.group(2)!);
      if (season != null && episode != null) return (season, episode);
    }

    return null;
  }

  static int? _extractYear(String input) {
    final yearMatch = RegExp(r'\b(19|20)\d{2}\b').firstMatch(input);
    return yearMatch != null ? int.tryParse(yearMatch.group(0)!) : null;
  }
}

class ParsedVideoName {
  final String originalFileName;
  final String cleanName;
  final bool isTV;
  final int? season;
  final int? episode;
  final int? year;

  ParsedVideoName({required this.originalFileName, required this.cleanName, required this.isTV, this.season, this.episode, this.year});

  @override
  String toString() {
    final parts = [cleanName];
    if (year != null) parts.add('($year)');
    if (isTV && season != null && episode != null) {
      parts.add('S${season!.toString().padLeft(2, '0')}E${episode!.toString().padLeft(2, '0')}');
    }
    return parts.join(' ');
  }
}
