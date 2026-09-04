import '../models/subtitle.dart';
import '../services/video_name_parser.dart';

/// Scores how well a subtitle matches a video.
class SubtitleRelevanceService {
  /// Parses season and episode numbers out of a subtitle name.
  static SubtitleSeasonInfo? parseSeasonEpisode(String title) {
    // Various formats: S05E01, S5E1, 5x01, 5.01, Season 5 Episode 1
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

  /// Scores a subtitle against a video (0-100).
  /// 100 = exact match (same season and episode)
  /// 80 = same season, different episode
  /// 60 = same show, different season
  /// 40 = similar title
  /// 20 = only the language matches
  static int calculateRelevance(Subtitle subtitle, ParsedVideoName parsedVideo) {
    final subtitleInfo = parseSeasonEpisode(subtitle.title);
    int relevance = 0;

    // Base title match
    final videoNameLower = parsedVideo.cleanName.toLowerCase();
    final subtitleTitleLower = subtitle.title.toLowerCase();

    // Compare the show/movie title
    final videoWords = videoNameLower.split(' ').where((w) => w.length > 2).toList();
    int matchingWords = 0;
    for (final word in videoWords) {
      if (subtitleTitleLower.contains(word)) {
        matchingWords++;
      }
    }

    if (videoWords.isNotEmpty) {
      final nameMatchRatio = matchingWords / videoWords.length;
      relevance += (nameMatchRatio * 40).round(); // Max 40 points for the title match
    }

    // For TV shows compare season and episode
    if (parsedVideo.isTV && parsedVideo.season != null && parsedVideo.episode != null) {
      if (subtitleInfo != null) {
        if (subtitleInfo.season == parsedVideo.season && subtitleInfo.episode == parsedVideo.episode) {
          // Exact match - same season and episode
          relevance += 60; // Max 60 points for an exact episode match
        } else if (subtitleInfo.season == parsedVideo.season) {
          // Same season, different episode
          relevance += 30;
        } else {
          // Different season
          relevance += 10;
        }
      }
    } else {
      // For movies award points for a matching year
      if (parsedVideo.year != null) {
        if (subtitle.title.contains(parsedVideo.year.toString())) {
          relevance += 40;
        }
      } else {
        // Without a year, award points for a strong title match
        relevance += 20;
      }
    }

    return relevance.clamp(0, 100);
  }

  /// Sorts subtitles by relevance and splits them into relevant ones and the rest.
  static SortedSubtitles sortByRelevance(List<Subtitle> subtitles, ParsedVideoName parsedVideo) {
    // Score every subtitle
    final scoredSubtitles = subtitles.map((subtitle) {
      final relevance = calculateRelevance(subtitle, parsedVideo);
      return ScoredSubtitle(subtitle: subtitle, relevance: relevance);
    }).toList();

    // Sort by relevance, highest first
    scoredSubtitles.sort((a, b) => b.relevance.compareTo(a.relevance));

    // Split into relevant (>= 70) and the rest
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

/// Season and episode parsed from a subtitle name.
class SubtitleSeasonInfo {
  final int season;
  final int episode;

  SubtitleSeasonInfo({required this.season, required this.episode});

  @override
  String toString() => 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
}

/// A subtitle with its computed relevance.
class ScoredSubtitle {
  final Subtitle subtitle;
  final int relevance;

  ScoredSubtitle({required this.subtitle, required this.relevance});
}

/// Sorted subtitles, split into relevant ones and the rest.
class SortedSubtitles {
  final List<Subtitle> relevant;
  final List<Subtitle> others;
  final List<Subtitle> allSorted;

  SortedSubtitles({required this.relevant, required this.others, required this.allSorted});

  bool get hasOthers => others.isNotEmpty;
  int get relevantCount => relevant.length;
  int get othersCount => others.length;
}
