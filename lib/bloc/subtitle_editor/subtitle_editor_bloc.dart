import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/subtitle_entry.dart';
import '../../services/srt_parser_service.dart';
import 'subtitle_editor_event.dart';
import 'subtitle_editor_state.dart';

/// BLoC for the subtitle editor functionality.
///
/// Handles global time shift, key-based synchronization,
/// and saving modified subtitles.
class SubtitleEditorBloc extends Bloc<SubtitleEditorEvent, SubtitleEditorState> {
  SubtitleEditorBloc() : super(SubtitleEditorInitial()) {
    on<LoadSubtitleFile>(_onLoadSubtitleFile);
    on<ApplyGlobalShift>(_onApplyGlobalShift);
    on<ResetGlobalShift>(_onResetGlobalShift);
    on<MarkAsKeyPoint>(_onMarkAsKeyPoint);
    on<RemoveKeyPoint>(_onRemoveKeyPoint);
    on<RecalculateFromKeyPoints>(_onRecalculateFromKeyPoints);
    on<SaveSubtitles>(_onSaveSubtitles);
    on<SelectSubtitleEntry>(_onSelectSubtitleEntry);
    on<AdjustSelectedKeyOffset>(_onAdjustSelectedKeyOffset);
  }

  Future<void> _onLoadSubtitleFile(LoadSubtitleFile event, Emitter<SubtitleEditorState> emit) async {
    emit(SubtitleEditorLoading());
    try {
      final entries = await SrtParserService.parseFile(event.subtitlePath);
      if (entries.isEmpty) {
        emit(SubtitleEditorError('No subtitle entries found in file'));
        return;
      }
      emit(SubtitleEditorLoaded(originalEntries: entries, modifiedEntries: List.from(entries), subtitlePath: event.subtitlePath, videoPath: event.videoPath));
    } catch (e) {
      emit(SubtitleEditorError('Failed to parse subtitle file: $e'));
    }
  }

  void _onApplyGlobalShift(ApplyGlobalShift event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;

    final newShift = currentState.globalShift + event.offset;
    final modified = SrtParserService.applyGlobalShift(currentState.originalEntries, newShift);

    emit(currentState.copyWith(globalShift: newShift, modifiedEntries: modified));
  }

  void _onResetGlobalShift(ResetGlobalShift event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;

    emit(currentState.copyWith(globalShift: Duration.zero, modifiedEntries: List.from(currentState.originalEntries)));
  }

  void _onSelectSubtitleEntry(SelectSubtitleEntry event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;

    emit(currentState.copyWith(selectedEntryIndex: event.entryIndex));
  }

  void _onAdjustSelectedKeyOffset(AdjustSelectedKeyOffset event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;
    if (currentState.selectedEntryIndex < 0) return;

    final srtIndex = currentState.selectedEntryIndex;
    final currentOffset = currentState.individualOffsets[srtIndex] ?? Duration.zero;
    final newOffset = currentOffset + event.delta;

    final newOffsets = Map<int, Duration>.from(currentState.individualOffsets);
    newOffsets[srtIndex] = newOffset;

    emit(currentState.copyWith(individualOffsets: newOffsets));
  }

  void _onMarkAsKeyPoint(MarkAsKeyPoint event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;

    final newKeyPoints = Map<int, Duration>.from(currentState.keyPoints);
    final offset = currentState.individualOffsets[event.entryIndex] ?? event.offset;
    newKeyPoints[event.entryIndex] = offset;

    emit(currentState.copyWith(keyPoints: newKeyPoints, keyRecalculated: false));
  }

  void _onRemoveKeyPoint(RemoveKeyPoint event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;

    final newKeyPoints = Map<int, Duration>.from(currentState.keyPoints);
    newKeyPoints.remove(event.entryIndex);

    emit(currentState.copyWith(keyPoints: newKeyPoints, keyRecalculated: false));
  }

  void _onRecalculateFromKeyPoints(RecalculateFromKeyPoints event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;
    if (currentState.keyPoints.isEmpty) return;

    final recalculated = SrtParserService.applyKeyBasedSync(currentState.originalEntries, currentState.keyPoints);

    emit(currentState.copyWith(modifiedEntries: recalculated, keyRecalculated: true));
  }

  Future<void> _onSaveSubtitles(SaveSubtitles event, Emitter<SubtitleEditorState> emit) async {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;

    try {
      final targetPath = event.targetPath ?? currentState.subtitlePath;
      await SrtParserService.writeFile(targetPath, currentState.modifiedEntries);

      // Re-emit loaded state with saved path, then saved state
      emit(SubtitleEditorSaved(targetPath));

      // Reload to continue editing if needed
      final entries = await SrtParserService.parseFile(targetPath);
      emit(SubtitleEditorLoaded(originalEntries: entries, modifiedEntries: List.from(entries), subtitlePath: targetPath, videoPath: currentState.videoPath));
    } catch (e) {
      emit(SubtitleEditorError('Failed to save subtitles: $e'));
    }
  }

  /// Helper to generate a temporary SRT file with current modifications
  /// for the video player to display.
  Future<String> generateTempSubtitleFile(List<SubtitleEntry> entries, String originalPath) async {
    final tempPath = '$originalPath.temp.srt';
    await SrtParserService.writeFile(tempPath, entries);
    return tempPath;
  }
}
