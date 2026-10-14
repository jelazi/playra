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

  /// Entries with the key points and the global shift applied
  final List<SubtitleEntry> modifiedEntries;

  /// Path to the original subtitle file
  final String subtitlePath;

  /// Path to the video file
  final String videoPath;

  /// Global time shift offset, applied on top of the key points
  final Duration globalShift;

  /// Key points: map of original SRT index -> offset from the original start time
  final Map<int, Duration> keyPoints;

  /// Subtitle currently being pinned to a moment in the video (-1 = none)
  final int selectedEntryIndex;

  SubtitleEditorLoaded({
    required this.originalEntries,
    required this.modifiedEntries,
    required this.subtitlePath,
    required this.videoPath,
    this.globalShift = Duration.zero,
    this.keyPoints = const {},
    this.selectedEntryIndex = -1,
  });

  bool get isPickingKey => selectedEntryIndex >= 0;

  SubtitleEntry? originalEntry(int srtIndex) {
    for (final entry in originalEntries) {
      if (entry.index == srtIndex) return entry;
    }
    return null;
  }

  SubtitleEntry? modifiedEntry(int srtIndex) {
    for (final entry in modifiedEntries) {
      if (entry.index == srtIndex) return entry;
    }
    return null;
  }

  /// How far the subtitle has moved from its time in the original file.
  Duration totalShiftOf(int srtIndex) {
    final original = originalEntry(srtIndex);
    final modified = modifiedEntry(srtIndex);
    if (original == null || modified == null) return Duration.zero;
    return modified.startTime - original.startTime;
  }

  /// Subtitles that are on screen at [position] with the current timing.
  List<SubtitleEntry> activeAt(Duration position) {
    return modifiedEntries.where((e) => e.startTime <= position && position < e.endTime).toList();
  }

  SubtitleEditorLoaded copyWith({
    List<SubtitleEntry>? originalEntries,
    List<SubtitleEntry>? modifiedEntries,
    String? subtitlePath,
    String? videoPath,
    Duration? globalShift,
    Map<int, Duration>? keyPoints,
    int? selectedEntryIndex,
  }) {
    return SubtitleEditorLoaded(
      originalEntries: originalEntries ?? this.originalEntries,
      modifiedEntries: modifiedEntries ?? this.modifiedEntries,
      subtitlePath: subtitlePath ?? this.subtitlePath,
      videoPath: videoPath ?? this.videoPath,
      globalShift: globalShift ?? this.globalShift,
      keyPoints: keyPoints ?? this.keyPoints,
      selectedEntryIndex: selectedEntryIndex ?? this.selectedEntryIndex,
    );
  }

  @override
  List<Object?> get props => [originalEntries, modifiedEntries, subtitlePath, videoPath, globalShift, keyPoints, selectedEntryIndex];
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
