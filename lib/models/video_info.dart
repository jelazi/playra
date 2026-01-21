import 'package:equatable/equatable.dart';

class VideoInfo extends Equatable {
  final String path;
  final String name;
  final String directory;
  final Duration? duration;

  const VideoInfo({required this.path, required this.name, required this.directory, this.duration});

  VideoInfo copyWith({String? path, String? name, String? directory, Duration? duration}) {
    return VideoInfo(path: path ?? this.path, name: name ?? this.name, directory: directory ?? this.directory, duration: duration ?? this.duration);
  }

  String get nameWithoutExtension {
    if (name.contains('.')) {
      return name.substring(0, name.lastIndexOf('.'));
    }
    return name;
  }

  @override
  List<Object?> get props => [path, name, directory, duration];
}
