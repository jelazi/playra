import 'package:equatable/equatable.dart';

import '../../models/subtitle_entry.dart';

/// States for the SubtitleEditorBloc
abstract class SubtitleEditorState extends Equatable {
  @override
  List<Object?> get props => [];
}

class SubtitleEditorInitial extends SubtitleEditorState {}

class SubtitleEditorLoading extends SubtitleEditorState {}

class SubtitleEditorLoaded extends SubtitleEditorState {
  /// Original parsed entries (unmodified)
  final List<SubtitleEntry> originalEntries;

  /// Modified entries (after shifts/interpolation)
  final List<SubtitleEntry> modifiedEntries;

  /// Path to the original subtitle file
  final String subtitlePath;

  /// Path to the video file
  final String videoPath;

  /// Global time shift offset
  final Duration globalShift;

  /// Key points: map of original SRT index -> offset duration
  final Map<int, Duration> keyPoints;

  /// Currently selected subtitle index for key-based editing (-1 = none)
  final int selectedEntryIndex;

  /// Individual offset adjustments for key-based sync (before saving as key)
  /// Map of original SRT index -> current adjustment offset
  final Map<int, Duration> individualOffsets;

  /// Whether key-based recalculation has been applied
  final bool keyRecalculated;

  SubtitleEditorLoaded({
    required this.originalEntries,
    required this.modifiedEntries,
    required this.subtitlePath,
    required this.videoPath,
    this.globalShift = Duration.zero,
    this.keyPoints = const {},
    this.selectedEntryIndex = -1,
    this.individualOffsets = const {},
    this.keyRecalculated = false,
  });

  SubtitleEditorLoaded copyWith({
    List<SubtitleEntry>? originalEntries,
    List<SubtitleEntry>? modifiedEntries,
    String? subtitlePath,
    String? videoPath,
    Duration? globalShift,
    Map<int, Duration>? keyPoints,
    int? selectedEntryIndex,
    Map<int, Duration>? individualOffsets,
    bool? keyRecalculated,
  }) {
    return SubtitleEditorLoaded(
      originalEntries: originalEntries ?? this.originalEntries,
      modifiedEntries: modifiedEntries ?? this.modifiedEntries,
      subtitlePath: subtitlePath ?? this.subtitlePath,
      videoPath: videoPath ?? this.videoPath,
      globalShift: globalShift ?? this.globalShift,
      keyPoints: keyPoints ?? this.keyPoints,
      selectedEntryIndex: selectedEntryIndex ?? this.selectedEntryIndex,
      individualOffsets: individualOffsets ?? this.individualOffsets,
      keyRecalculated: keyRecalculated ?? this.keyRecalculated,
    );
  }

  @override
  List<Object?> get props => [originalEntries, modifiedEntries, subtitlePath, videoPath, globalShift, keyPoints, selectedEntryIndex, individualOffsets, keyRecalculated];
}

class SubtitleEditorError extends SubtitleEditorState {
  final String message;

  SubtitleEditorError(this.message);

  @override
  List<Object?> get props => [message];
}

class SubtitleEditorSaved extends SubtitleEditorState {
  final String savedPath;

  SubtitleEditorSaved(this.savedPath);

  @override
  List<Object?> get props => [savedPath];
}
