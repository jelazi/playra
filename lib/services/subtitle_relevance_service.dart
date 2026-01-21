import '../models/subtitle.dart';
import '../services/video_name_parser.dart';

/// Služba pro výpočet relevance titulků k videu
class SubtitleRelevanceService {
  /// Parsuje informace o sezóně a epizodě z názvu titulku
  static SubtitleSeasonInfo? parseSeasonEpisode(String title) {
    // Různé formáty: S05E01, S5E1, 5x01, 5.01, Season 5 Episode 1
    final patterns = [
      RegExp(r'[Ss](\d{1,2})[Ee](\d{1,2})'), // S05E01
      RegExp(r'(\d{1,2})[xX](\d{1,2})'), // 5x01
      RegExp(r'[Ss]eason\s*(\d{1,2})\s*[Ee]pisode\s*(\d{1,2})', caseSensitive: false), // Season 5 Episode 1
      RegExp(r'[Ss](\d{1,2})\s*[Ee](\d{1,2})'), // S5 E01
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(title);
      if (match != null) {
        final season = int.tryParse(match.group(1)!);
        final episode = int.tryParse(match.group(2)!);
        if (season != null && episode != null) {
          return SubtitleSeasonInfo(season: season, episode: episode);
        }
      }
    }
    return null;
  }

  /// Vypočítá relevanci titulku k videu (0-100)
  /// 100 = perfektní shoda (stejná sezóna a epizoda)
  /// 80 = stejná sezóna, jiná epizoda
  /// 60 = stejný seriál, jiná sezóna
  /// 40 = podobný název
  /// 20 = pouze jazyk odpovídá
  static int calculateRelevance(Subtitle subtitle, ParsedVideoName parsedVideo) {
    final subtitleInfo = parseSeasonEpisode(subtitle.title);
    int relevance = 0;

    // Základní shoda názvu
    final videoNameLower = parsedVideo.cleanName.toLowerCase();
    final subtitleTitleLower = subtitle.title.toLowerCase();

    // Kontrola shody názvu seriálu/filmu
    final videoWords = videoNameLower.split(' ').where((w) => w.length > 2).toList();
    int matchingWords = 0;
    for (final word in videoWords) {
      if (subtitleTitleLower.contains(word)) {
        matchingWords++;
      }
    }

    if (videoWords.isNotEmpty) {
      final nameMatchRatio = matchingWords / videoWords.length;
      relevance += (nameMatchRatio * 40).round(); // Max 40 bodů za shodu názvu
    }

    // Pro TV seriály kontrola sezóny a epizody
    if (parsedVideo.isTV && parsedVideo.season != null && parsedVideo.episode != null) {
      if (subtitleInfo != null) {
        if (subtitleInfo.season == parsedVideo.season && subtitleInfo.episode == parsedVideo.episode) {
          // Perfektní shoda - stejná sezóna a epizoda
          relevance += 60; // Max 60 bodů za přesnou shodu epizody
        } else if (subtitleInfo.season == parsedVideo.season) {
          // Stejná sezóna, jiná epizoda
          relevance += 30;
        } else {
          // Jiná sezóna
          relevance += 10;
        }
      }
    } else {
      // Pro filmy - pokud není TV, přidáme body za rok
      if (parsedVideo.year != null) {
        if (subtitle.title.contains(parsedVideo.year.toString())) {
          relevance += 40;
        }
      } else {
        // Pokud není rok, přidáme body pokud má vysokou shodu názvu
        relevance += 20;
      }
    }

    return relevance.clamp(0, 100);
  }

  /// Seřadí titulky podle relevance a rozdělí na relevantní a ostatní
  static SortedSubtitles sortByRelevance(List<Subtitle> subtitles, ParsedVideoName parsedVideo) {
    // Vypočítat relevanci pro každý titulek
    final scoredSubtitles = subtitles.map((subtitle) {
      final relevance = calculateRelevance(subtitle, parsedVideo);
      return ScoredSubtitle(subtitle: subtitle, relevance: relevance);
    }).toList();

    // Seřadit podle relevance (nejvyšší první)
    scoredSubtitles.sort((a, b) => b.relevance.compareTo(a.relevance));

    // Rozdělit na relevantní (relevance >= 70) a ostatní
    final relevant = <Subtitle>[];
    final others = <Subtitle>[];

    for (final scored in scoredSubtitles) {
      if (scored.relevance >= 70) {
        relevant.add(scored.subtitle);
      } else {
        others.add(scored.subtitle);
      }
    }

    return SortedSubtitles(relevant: relevant, others: others, allSorted: scoredSubtitles.map((s) => s.subtitle).toList());
  }
}

/// Informace o sezóně a epizodě z názvu titulku
class SubtitleSeasonInfo {
  final int season;
  final int episode;

  SubtitleSeasonInfo({required this.season, required this.episode});

  @override
  String toString() => 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
}

/// Titulek s vypočítanou relevancí
class ScoredSubtitle {
  final Subtitle subtitle;
  final int relevance;

  ScoredSubtitle({required this.subtitle, required this.relevance});
}

/// Seřazené titulky rozdělené na relevantní a ostatní
class SortedSubtitles {
  final List<Subtitle> relevant;
  final List<Subtitle> others;
  final List<Subtitle> allSorted;

  SortedSubtitles({required this.relevant, required this.others, required this.allSorted});

  bool get hasOthers => others.isNotEmpty;
  int get relevantCount => relevant.length;
  int get othersCount => others.length;
}
