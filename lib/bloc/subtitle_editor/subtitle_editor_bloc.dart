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
    on<SelectSubtitleEntry>(_onSelectSubtitleEntry);
    on<ClearSubtitleSelection>(_onClearSubtitleSelection);
    on<SetKeyPoint>(_onSetKeyPoint);
    on<RemoveKeyPoint>(_onRemoveKeyPoint);
    on<ClearKeyPoints>(_onClearKeyPoints);
    on<SaveSubtitles>(_onSaveSubtitles);
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

    emit(_withTiming(currentState, globalShift: currentState.globalShift + event.offset));
  }

  void _onResetGlobalShift(ResetGlobalShift event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;

    emit(_withTiming(currentState, globalShift: Duration.zero));
  }

  void _onSelectSubtitleEntry(SelectSubtitleEntry event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;
    if (currentState.originalEntry(event.entryIndex) == null) return;

    emit(currentState.copyWith(selectedEntryIndex: event.entryIndex));
  }

  void _onClearSubtitleSelection(ClearSubtitleSelection event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;

    emit(currentState.copyWith(selectedEntryIndex: -1));
  }

  void _onSetKeyPoint(SetKeyPoint event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;
    final original = currentState.originalEntry(event.entryIndex);
    if (original == null) return;

    final newKeyPoints = Map<int, Duration>.from(currentState.keyPoints);
    newKeyPoints[event.entryIndex] = event.startTime - original.startTime - currentState.globalShift;

    emit(_withTiming(currentState, keyPoints: newKeyPoints, selectedEntryIndex: -1));
  }

  void _onRemoveKeyPoint(RemoveKeyPoint event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;

    final newKeyPoints = Map<int, Duration>.from(currentState.keyPoints)..remove(event.entryIndex);

    emit(_withTiming(currentState, keyPoints: newKeyPoints));
  }

  void _onClearKeyPoints(ClearKeyPoints event, Emitter<SubtitleEditorState> emit) {
    final currentState = state;
    if (currentState is! SubtitleEditorLoaded) return;

    emit(_withTiming(currentState, keyPoints: const {}, selectedEntryIndex: -1));
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

  SubtitleEditorLoaded _withTiming(SubtitleEditorLoaded current, {Duration? globalShift, Map<int, Duration>? keyPoints, int? selectedEntryIndex}) {
    final shift = globalShift ?? current.globalShift;
    final keys = keyPoints ?? current.keyPoints;
    final List<SubtitleEntry> synced = SrtParserService.applyKeyBasedSync(current.originalEntries, keys);
    return current.copyWith(
      globalShift: shift,
      keyPoints: keys,
      selectedEntryIndex: selectedEntryIndex,
      modifiedEntries: SrtParserService.applyGlobalShift(synced, shift),
    );
  }
}
