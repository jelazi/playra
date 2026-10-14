import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playra/bloc/subtitle_editor/subtitle_editor_bloc.dart';
import 'package:playra/bloc/subtitle_editor/subtitle_editor_event.dart';
import 'package:playra/bloc/subtitle_editor/subtitle_editor_state.dart';
import 'package:playra/services/srt_parser_service.dart';

const _srt = '''
1
00:00:10,000 --> 00:00:12,000
one

2
00:00:20,000 --> 00:00:22,000
two

3
00:00:30,000 --> 00:00:32,000
three
''';

void main() {
  late Directory tempDir;
  late String subtitlePath;
  late SubtitleEditorBloc bloc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('playra_editor_bloc_test');
    subtitlePath = '${tempDir.path}/movie.srt';
    await File(subtitlePath).writeAsString(_srt);
    bloc = SubtitleEditorBloc();
  });

  tearDown(() async {
    await bloc.close();
    await tempDir.delete(recursive: true);
  });

  /// Loads the fixture and returns the resulting state, so each test can start
  /// from a loaded editor without repeating the wait.
  Future<SubtitleEditorLoaded> loadFixture() async {
    bloc.add(LoadSubtitleFile(subtitlePath: subtitlePath, videoPath: '${tempDir.path}/movie.mkv'));
    await bloc.stream.firstWhere((s) => s is SubtitleEditorLoaded);
    return bloc.state as SubtitleEditorLoaded;
  }

  group('LoadSubtitleFile', () {
    test('goes through Loading to Loaded with the parsed entries', () async {
      expect(bloc.stream, emitsInOrder([isA<SubtitleEditorLoading>(), isA<SubtitleEditorLoaded>()]));

      bloc.add(LoadSubtitleFile(subtitlePath: subtitlePath, videoPath: '/videos/movie.mkv'));
      await bloc.stream.firstWhere((s) => s is SubtitleEditorLoaded);

      final state = bloc.state as SubtitleEditorLoaded;
      expect(state.originalEntries, hasLength(3));
      expect(state.modifiedEntries, hasLength(3));
      expect(state.subtitlePath, subtitlePath);
      expect(state.videoPath, '/videos/movie.mkv');
      expect(state.globalShift, Duration.zero);
      expect(state.keyPoints, isEmpty);
    });

    test('errors on a missing file', () async {
      expect(bloc.stream, emitsInOrder([isA<SubtitleEditorLoading>(), isA<SubtitleEditorError>()]));
      bloc.add(LoadSubtitleFile(subtitlePath: '${tempDir.path}/nope.srt', videoPath: '/videos/movie.mkv'));
      await bloc.stream.firstWhere((s) => s is SubtitleEditorError);
    });

    test('errors on a file with no parsable entries', () async {
      final emptyPath = '${tempDir.path}/empty.srt';
      await File(emptyPath).writeAsString('this is not a subtitle file');

      bloc.add(LoadSubtitleFile(subtitlePath: emptyPath, videoPath: '/videos/movie.mkv'));
      final state = await bloc.stream.firstWhere((s) => s is SubtitleEditorError) as SubtitleEditorError;
      expect(state.message, contains('No subtitle entries'));
    });
  });

  group('global shift', () {
    test('shifts every entry and records the offset', () async {
      await loadFixture();

      bloc.add(ApplyGlobalShift(const Duration(seconds: 2)));
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.globalShift, const Duration(seconds: 2));
      expect(state.modifiedEntries[0].startTime, const Duration(seconds: 12));
      expect(state.modifiedEntries[2].startTime, const Duration(seconds: 32));
      expect(state.originalEntries[0].startTime, const Duration(seconds: 10), reason: 'originals must stay untouched');
    });

    test('accumulates successive shifts', () async {
      await loadFixture();

      bloc.add(ApplyGlobalShift(const Duration(seconds: 2)));
      await bloc.stream.first;
      bloc.add(ApplyGlobalShift(const Duration(seconds: 3)));
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.globalShift, const Duration(seconds: 5));
      expect(state.modifiedEntries[0].startTime, const Duration(seconds: 15));
    });

    test('reset returns to the original timings', () async {
      await loadFixture();

      bloc.add(ApplyGlobalShift(const Duration(seconds: 7)));
      await bloc.stream.first;
      bloc.add(ResetGlobalShift());
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.globalShift, Duration.zero);
      expect(state.modifiedEntries[0].startTime, const Duration(seconds: 10));
    });

    test('ignores events while no file is loaded', () async {
      bloc.add(ApplyGlobalShift(const Duration(seconds: 2)));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<SubtitleEditorInitial>());
    });
  });

  group('key points', () {
    test('selecting an entry enters the picking mode', () async {
      await loadFixture();

      bloc.add(SelectSubtitleEntry(entryIndex: 2));
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.selectedEntryIndex, 2);
      expect(state.isPickingKey, isTrue);
    });

    test('selecting an unknown entry is ignored', () async {
      await loadFixture();

      bloc.add(SelectSubtitleEntry(entryIndex: 99));
      await Future<void>.delayed(Duration.zero);

      expect((bloc.state as SubtitleEditorLoaded).isPickingKey, isFalse);
    });

    test('cancelling the selection leaves the picking mode', () async {
      await loadFixture();

      bloc.add(SelectSubtitleEntry(entryIndex: 2));
      await bloc.stream.first;
      bloc.add(ClearSubtitleSelection());
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.isPickingKey, isFalse);
    });

    test('a key pins the subtitle to the video position and ends the picking', () async {
      await loadFixture();

      bloc.add(SelectSubtitleEntry(entryIndex: 2));
      await bloc.stream.first;
      bloc.add(SetKeyPoint(entryIndex: 2, startTime: const Duration(seconds: 24)));
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.keyPoints, {2: const Duration(seconds: 4)});
      expect(state.isPickingKey, isFalse);
      expect(state.modifiedEntry(2)!.startTime, const Duration(seconds: 24));
      expect(state.totalShiftOf(2), const Duration(seconds: 4));
    });

    test('a single key shifts every subtitle immediately', () async {
      await loadFixture();

      bloc.add(SetKeyPoint(entryIndex: 1, startTime: const Duration(seconds: 11)));
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.modifiedEntries.map((e) => e.startTime.inSeconds), [11, 21, 31]);
    });

    test('two keys interpolate the subtitles between them', () async {
      await loadFixture();

      bloc.add(SetKeyPoint(entryIndex: 1, startTime: const Duration(seconds: 11)));
      await bloc.stream.first;
      bloc.add(SetKeyPoint(entryIndex: 3, startTime: const Duration(seconds: 35)));
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.modifiedEntries[0].startTime, const Duration(seconds: 11));
      expect(state.modifiedEntries[1].startTime, const Duration(seconds: 23));
      expect(state.modifiedEntries[2].startTime, const Duration(seconds: 35));
    });

    test('a key lands exactly where it was placed even with a global shift', () async {
      await loadFixture();

      bloc.add(ApplyGlobalShift(const Duration(seconds: 3)));
      await bloc.stream.first;
      bloc.add(SetKeyPoint(entryIndex: 2, startTime: const Duration(seconds: 25)));
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.keyPoints[2], const Duration(seconds: 2));
      expect(state.modifiedEntry(2)!.startTime, const Duration(seconds: 25));
    });

    test('the global shift moves keyed subtitles too', () async {
      await loadFixture();

      bloc.add(SetKeyPoint(entryIndex: 2, startTime: const Duration(seconds: 25)));
      await bloc.stream.first;
      bloc.add(ApplyGlobalShift(const Duration(seconds: 1)));
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.modifiedEntry(2)!.startTime, const Duration(seconds: 26));
    });

    test('removing a key restores the timing without it', () async {
      await loadFixture();

      bloc.add(SetKeyPoint(entryIndex: 1, startTime: const Duration(seconds: 15)));
      await bloc.stream.first;
      bloc.add(RemoveKeyPoint(entryIndex: 1));
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.keyPoints, isEmpty);
      expect(state.modifiedEntries[0].startTime, const Duration(seconds: 10));
    });

    test('clearing all keys restores the original timing', () async {
      await loadFixture();

      bloc.add(SetKeyPoint(entryIndex: 1, startTime: const Duration(seconds: 15)));
      await bloc.stream.first;
      bloc.add(SetKeyPoint(entryIndex: 3, startTime: const Duration(seconds: 40)));
      await bloc.stream.first;
      bloc.add(ClearKeyPoints());
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.keyPoints, isEmpty);
      expect(state.modifiedEntries.map((e) => e.startTime.inSeconds), [10, 20, 30]);
    });

    test('activeAt returns the subtitle on screen with the current timing', () async {
      await loadFixture();

      bloc.add(SetKeyPoint(entryIndex: 1, startTime: const Duration(seconds: 15)));
      final state = await bloc.stream.first as SubtitleEditorLoaded;

      expect(state.activeAt(const Duration(seconds: 11)), isEmpty);
      expect(state.activeAt(const Duration(seconds: 16)).single.text, 'one');
    });
  });

  group('SaveSubtitles', () {
    test('writes the shifted entries and reloads them', () async {
      await loadFixture();

      bloc.add(ApplyGlobalShift(const Duration(seconds: 5)));
      await bloc.stream.first;

      bloc.add(SaveSubtitles());
      final saved = await bloc.stream.firstWhere((s) => s is SubtitleEditorSaved) as SubtitleEditorSaved;
      expect(saved.savedPath, subtitlePath);

      final reloaded = await bloc.stream.firstWhere((s) => s is SubtitleEditorLoaded) as SubtitleEditorLoaded;
      expect(reloaded.globalShift, Duration.zero, reason: 'the saved timings become the new baseline');

      final onDisk = await SrtParserService.parseFile(subtitlePath);
      expect(onDisk[0].startTime, const Duration(seconds: 15));
      expect(onDisk[2].startTime, const Duration(seconds: 35));
    });

    test('honours an explicit target path and leaves the original alone', () async {
      await loadFixture();
      final targetPath = '${tempDir.path}/copy.srt';

      bloc.add(ApplyGlobalShift(const Duration(seconds: 5)));
      await bloc.stream.first;
      bloc.add(SaveSubtitles(targetPath: targetPath));
      final saved = await bloc.stream.firstWhere((s) => s is SubtitleEditorSaved) as SubtitleEditorSaved;

      expect(saved.savedPath, targetPath);
      expect((await SrtParserService.parseFile(targetPath))[0].startTime, const Duration(seconds: 15));
      expect((await SrtParserService.parseFile(subtitlePath))[0].startTime, const Duration(seconds: 10));
    });

    test('ignores a save while nothing is loaded', () async {
      bloc.add(SaveSubtitles());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<SubtitleEditorInitial>());
    });
  });
}
