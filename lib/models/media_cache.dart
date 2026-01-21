import 'package:hive/hive.dart';

part 'media_cache.g.dart';

/// Cache pro uložení přiřazení názvu videa → TMDB info
@HiveType(typeId: 1)
class MediaCache extends HiveObject {
  @HiveField(0)
  String cleanName; // Např. "True Detective"

  @HiveField(1)
  int tmdbId;

  @HiveField(2)
  String mediaType; // "movie" nebo "tv"

  @HiveField(3)
  String title;

  @HiveField(4)
  String originalTitle;

  @HiveField(5)
  String? overview;

  @HiveField(6)
  String? posterPath;

  @HiveField(7)
  String? releaseDate;

  @HiveField(8)
  double? voteAverage;

  @HiveField(9)
  List<String>? genres;

  @HiveField(10)
  int? numberOfSeasons;

  @HiveField(11)
  int? numberOfEpisodes;

  MediaCache({
    required this.cleanName,
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    required this.originalTitle,
    this.overview,
    this.posterPath,
    this.releaseDate,
    this.voteAverage,
    this.genres,
    this.numberOfSeasons,
    this.numberOfEpisodes,
  });
}
