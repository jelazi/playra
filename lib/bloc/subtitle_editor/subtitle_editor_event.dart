import 'package:equatable/equatable.dart';

/// Events for the SubtitleEditorBloc
abstract class SubtitleEditorEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

/// Load and parse subtitle file
class LoadSubtitleFile extends SubtitleEditorEvent {
  final String subtitlePath;
  final String videoPath;

  LoadSubtitleFile({required this.subtitlePath, required this.videoPath});

  @override
  List<Object?> get props => [subtitlePath, videoPath];
}

/// Apply global time shift to all subtitles
class ApplyGlobalShift extends SubtitleEditorEvent {
  final Duration offset;

  ApplyGlobalShift(this.offset);

  @override
  List<Object?> get props => [offset];
}

/// Reset global shift to zero
class ResetGlobalShift extends SubtitleEditorEvent {}

/// Select the subtitle the user is about to pin to a moment in the video
class SelectSubtitleEntry extends SubtitleEditorEvent {
  final int entryIndex;

  SelectSubtitleEntry({required this.entryIndex});

  @override
  List<Object?> get props => [entryIndex];
}

/// Leave the key-picking mode without saving
class ClearSubtitleSelection extends SubtitleEditorEvent {}

/// Pin a subtitle so that it starts exactly at [startTime] in the video
class SetKeyPoint extends SubtitleEditorEvent {
  final int entryIndex;
  final Duration startTime;

  SetKeyPoint({required this.entryIndex, required this.startTime});

  @override
  List<Object?> get props => [entryIndex, startTime];
}

/// Remove a key point
class RemoveKeyPoint extends SubtitleEditorEvent {
  final int entryIndex;

  RemoveKeyPoint({required this.entryIndex});

  @override
  List<Object?> get props => [entryIndex];
}

/// Remove all key points
class ClearKeyPoints extends SubtitleEditorEvent {}

/// Save subtitles to file
class SaveSubtitles extends SubtitleEditorEvent {
  final String? targetPath;

  SaveSubtitles({this.targetPath});

  @override
  List<Object?> get props => [targetPath];
}
