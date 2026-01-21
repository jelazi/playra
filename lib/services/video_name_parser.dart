import 'package:path/path.dart' as path;

/// Parsování názvu video souboru pro extrakci názvu filmu/seriálu
class VideoNameParser {
  /// Extrahuje název filmu/seriálu z názvu souboru
  static ParsedVideoName parse(String filePath) {
    final fileName = path.basenameWithoutExtension(filePath);

    // Odstranit běžné suffix (kodek, kvalita, release group, atd.)
    var cleanName = fileName;

    // Regex patterny pro detekci různých částí názvu
    final seasonEpisodePattern = RegExp(r'[Ss]\d{1,2}[Ee]\d{1,2}', caseSensitive: false);
    final yearPattern = RegExp(r'\b(19|20)\d{2}\b');
    final qualityPattern = RegExp(r'\b(480p|720p|1080p|2160p|4K|BluRay|WEB-?DL|WEBRip|HDTV|DVDRip)\b', caseSensitive: false);
    final codecPattern = RegExp(r'\b(x264|x265|H\.?264|H\.?265|HEVC|XviD)\b', caseSensitive: false);

    // Najít season/episode info
    final seasonEpisodeMatch = seasonEpisodePattern.firstMatch(cleanName);
    String? seasonEpisode;
    int? season;
    int? episode;

    if (seasonEpisodeMatch != null) {
      seasonEpisode = seasonEpisodeMatch.group(0);
      final seMatch = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,2})').firstMatch(seasonEpisode!);
      if (seMatch != null) {
        season = int.tryParse(seMatch.group(1)!);
        episode = int.tryParse(seMatch.group(2)!);
      }
      // Odstranit season/episode z názvu
      cleanName = cleanName.substring(0, seasonEpisodeMatch.start);
    }

    // Najít rok
    final yearMatch = yearPattern.firstMatch(cleanName);
    int? year;
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(0)!);
      // Odstranit rok z názvu
      cleanName = cleanName.substring(0, yearMatch.start);
    }

    // Odstranit běžné separátory a nahradit je mezerami
    cleanName = cleanName.replaceAll(RegExp(r'[\._\-\+]'), ' ').trim();

    // Odstranit vše po klíčových slovech (kvalita, kodek, atd.)
    final qualityMatch = qualityPattern.firstMatch(cleanName);
    if (qualityMatch != null) {
      cleanName = cleanName.substring(0, qualityMatch.start).trim();
    }

    final codecMatch = codecPattern.firstMatch(cleanName);
    if (codecMatch != null) {
      cleanName = cleanName.substring(0, codecMatch.start).trim();
    }

    // Odstranit čísla velikosti (např. "500MB", "1.5GB")
    cleanName = cleanName.replaceAll(RegExp(r'\b\d+(\.\d+)?\s?(MB|GB|KB)\b', caseSensitive: false), '').trim();

    // Odstranit dvojité mezery
    cleanName = cleanName.replaceAll(RegExp(r'\s+'), ' ').trim();

    final isTV = seasonEpisode != null;

    return ParsedVideoName(originalFileName: fileName, cleanName: cleanName, isTV: isTV, season: season, episode: episode, year: year);
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
