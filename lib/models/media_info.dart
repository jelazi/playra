/// Movie or TV show details from TMDB.
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

  // TV shows only
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

/// Details of a single TV episode (overview always fetched in English).
class EpisodeInfo {
  final int season;
  final int episode;
  final String? name;
  final String? overview;
  final String? stillPath;
  final double? voteAverage;
  final String? airDate;

  const EpisodeInfo({required this.season, required this.episode, this.name, this.overview, this.stillPath, this.voteAverage, this.airDate});

  factory EpisodeInfo.fromJson(Map<String, dynamic> j, int season, int episode) => EpisodeInfo(
    season: season,
    episode: episode,
    name: j['name'] as String?,
    overview: j['overview'] as String?,
    stillPath: j['still_path'] as String?,
    voteAverage: (j['vote_average'] as num?)?.toDouble(),
    airDate: j['air_date'] as String?,
  );

  EpisodeInfo copyWith({String? name, String? overview, String? stillPath, double? voteAverage, String? airDate}) => EpisodeInfo(
    season: season,
    episode: episode,
    name: name ?? this.name,
    overview: overview ?? this.overview,
    stillPath: stillPath ?? this.stillPath,
    voteAverage: voteAverage ?? this.voteAverage,
    airDate: airDate ?? this.airDate,
  );

  String get stillUrl => stillPath != null ? 'https://image.tmdb.org/t/p/w300$stillPath' : '';
}
