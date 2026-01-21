/// Model pro informace o filmu/seriálu z TMDB
class MediaInfo {
  final int id;
  final String title;
  final String originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double? voteAverage;
  final double? popularity;
  final List<String> genres;
  final MediaType type;

  // Pro seriály
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final String? firstAirDate;

  MediaInfo({
    required this.id,
    required this.title,
    required this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage,
    this.popularity,
    this.genres = const [],
    required this.type,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.firstAirDate,
  });

  factory MediaInfo.fromJson(Map<String, dynamic> json, MediaType type) {
    return MediaInfo(
      id: json['id'] as int,
      title: type == MediaType.movie ? (json['title'] as String?) ?? '' : (json['name'] as String?) ?? '',
      originalTitle: type == MediaType.movie ? (json['original_title'] as String?) ?? '' : (json['original_name'] as String?) ?? '',
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: type == MediaType.movie ? json['release_date'] as String? : json['first_air_date'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      popularity: (json['popularity'] as num?)?.toDouble(),
      genres: (json['genres'] as List?)?.map((g) => g['name'] as String).toList() ?? [],
      type: type,
      numberOfSeasons: json['number_of_seasons'] as int?,
      numberOfEpisodes: json['number_of_episodes'] as int?,
      firstAirDate: json['first_air_date'] as String?,
    );
  }

  String get posterUrl => posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';

  String get backdropUrl => backdropPath != null ? 'https://image.tmdb.org/t/p/original$backdropPath' : '';
}

enum MediaType { movie, tv }
