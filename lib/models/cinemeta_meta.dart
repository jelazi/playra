/// A movie entry returned by the Cinemeta addon (Stremio metadata catalog).
class CinemetaMeta {
  final String imdbId; // e.g. "tt1234567"
  final String name;
  final String? poster;
  final String? year;
  final String? description;
  final double? imdbRating;

  const CinemetaMeta({
    required this.imdbId,
    required this.name,
    this.poster,
    this.year,
    this.description,
    this.imdbRating,
  });

  factory CinemetaMeta.fromJson(Map<String, dynamic> json) {
    return CinemetaMeta(
      imdbId: (json['imdb_id'] as String?) ?? (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      poster: json['poster'] as String?,
      year: (json['releaseInfo'] as String?) ?? (json['year']?.toString()),
      description: json['description'] as String?,
      imdbRating: double.tryParse('${json['imdbRating'] ?? ''}'),
    );
  }
}
