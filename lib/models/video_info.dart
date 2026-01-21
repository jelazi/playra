import 'package:equatable/equatable.dart';

class VideoInfo extends Equatable {
  final String path;
  final String name;
  final String directory;
  final Duration? duration;
  final bool hasDownloadedSubtitles; // From Hive settings
  final bool hasPhysicalSubtitles; // From file system check
  final List<String> subtitleFiles; // Actual subtitle files found

  const VideoInfo({
    required this.path, 
    required this.name, 
    required this.directory, 
    this.duration,
    this.hasDownloadedSubtitles = false,
    this.hasPhysicalSubtitles = false,
    this.subtitleFiles = const [],
  });

  VideoInfo copyWith({
    String? path, 
    String? name, 
    String? directory, 
    Duration? duration,
    bool? hasDownloadedSubtitles,
    bool? hasPhysicalSubtitles,
    List<String>? subtitleFiles,
  }) {
    return VideoInfo(
      path: path ?? this.path, 
      name: name ?? this.name, 
      directory: directory ?? this.directory, 
      duration: duration ?? this.duration,
      hasDownloadedSubtitles: hasDownloadedSubtitles ?? this.hasDownloadedSubtitles,
      hasPhysicalSubtitles: hasPhysicalSubtitles ?? this.hasPhysicalSubtitles,
      subtitleFiles: subtitleFiles ?? this.subtitleFiles,
    );
  }

  String get nameWithoutExtension {
    if (name.contains('.')) {
      return name.substring(0, name.lastIndexOf('.'));
    }
    return name;
  }

  /// Returns true if this video has any kind of subtitles (downloaded or physical)
  bool get hasAnySubtitles => hasDownloadedSubtitles || hasPhysicalSubtitles;

  @override
  List<Object?> get props => [path, name, directory, duration, hasDownloadedSubtitles, hasPhysicalSubtitles, subtitleFiles];
}
