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

/// Set the offset for a specific subtitle entry (key-based sync)
class SetKeySubtitleOffset extends SubtitleEditorEvent {
  final int entryIndex;
  final Duration offset;

  SetKeySubtitleOffset({required this.entryIndex, required this.offset});

  @override
  List<Object?> get props => [entryIndex, offset];
}

/// Mark a subtitle as a key point with its current offset
class MarkAsKeyPoint extends SubtitleEditorEvent {
  final int entryIndex;
  final Duration offset;

  MarkAsKeyPoint({required this.entryIndex, required this.offset});

  @override
  List<Object?> get props => [entryIndex, offset];
}

/// Remove a key point
class RemoveKeyPoint extends SubtitleEditorEvent {
  final int entryIndex;

  RemoveKeyPoint({required this.entryIndex});

  @override
  List<Object?> get props => [entryIndex];
}

/// Recalculate all subtitles based on key points (linear interpolation)
class RecalculateFromKeyPoints extends SubtitleEditorEvent {}

/// Save subtitles to file
class SaveSubtitles extends SubtitleEditorEvent {
  final String? targetPath;

  SaveSubtitles({this.targetPath});

  @override
  List<Object?> get props => [targetPath];
}

/// Select a subtitle entry (for key-based sync UI)
class SelectSubtitleEntry extends SubtitleEditorEvent {
  final int entryIndex;

  SelectSubtitleEntry({required this.entryIndex});

  @override
  List<Object?> get props => [entryIndex];
}

/// Adjust the individual offset for the currently selected subtitle in key mode
class AdjustSelectedKeyOffset extends SubtitleEditorEvent {
  final Duration delta;

  AdjustSelectedKeyOffset(this.delta);

  @override
  List<Object?> get props => [delta];
}
