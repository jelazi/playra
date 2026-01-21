import 'package:equatable/equatable.dart';

class Subtitle extends Equatable {
  final String id;
  final String title;
  final String language;
  final String format; // srt, sub, etc.
  final String downloadUrl;
  final String? rating;
  final String? uploader;
  final String? details;
  final String? downloadCount;
  final String? movieName;
  final bool isSynced;

  const Subtitle({
    required this.id,
    required this.title,
    required this.language,
    required this.format,
    required this.downloadUrl,
    this.rating,
    this.uploader,
    this.details,
    this.downloadCount,
    this.movieName,
    this.isSynced = false,
  });

  factory Subtitle.fromJson(Map<String, dynamic> json) {
    return Subtitle(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      language: json['language']?.toString() ?? 'cs',
      format: json['format']?.toString() ?? 'srt',
      downloadUrl: json['downloadUrl']?.toString() ?? '',
      rating: json['rating']?.toString(),
      uploader: json['uploader']?.toString(),
      details: json['details']?.toString(),
      downloadCount: json['downloadCount']?.toString(),
      movieName: json['movieName']?.toString(),
      isSynced: json['isSynced'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'language': language,
      'format': format,
      'downloadUrl': downloadUrl,
      'rating': rating,
      'uploader': uploader,
      'details': details,
      'downloadCount': downloadCount,
      'movieName': movieName,
      'isSynced': isSynced,
    };
  }

  Subtitle copyWith({String? id, String? title, String? language, String? format, String? downloadUrl, String? rating, String? uploader, String? details, bool? isSynced}) {
    return Subtitle(
      id: id ?? this.id,
      title: title ?? this.title,
      language: language ?? this.language,
      format: format ?? this.format,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      rating: rating ?? this.rating,
      uploader: uploader ?? this.uploader,
      details: details ?? this.details,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  List<Object?> get props => [id, title, language, format, downloadUrl, rating, uploader, details, isSynced];
}
