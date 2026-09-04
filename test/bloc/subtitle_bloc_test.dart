import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playra/bloc/subtitle/subtitle_bloc.dart';
import 'package:playra/bloc/subtitle/subtitle_event.dart';
import 'package:playra/bloc/subtitle/subtitle_state.dart';
import 'package:playra/models/subtitle.dart';
import 'package:playra/models/video_info.dart';
import 'package:playra/repositories/titulky_repository.dart';

class MockTitulkyRepository extends Mock implements TitulkyRepository {}

Subtitle _sub(String title, {String? id}) => Subtitle(id: id ?? title, title: title, language: 'cs', format: 'srt', downloadUrl: 'https://example.test/$title');

const _video = VideoInfo(path: '/media/True.Detective.S01E02.720p.mkv', name: 'True.Detective.S01E02.720p.mkv', directory: '/media');

void main() {
  late MockTitulkyRepository repository;
  late SubtitleBloc bloc;

  setUpAll(() {
    registerFallbackValue(_sub('fallback'));
  });

  setUp(() {
    repository = MockTitulkyRepository();
    bloc = SubtitleBloc(repository: repository);
  });

  tearDown(() async => bloc.close());

  /// SettingsService is never initialised here, so its Hive box stays null and
  /// every read falls back to defaults while every write is a no-op. That keeps
  /// these tests free of platform channels.
  group('login', () {
    test('emits LoggingIn then LoggedIn on success', () async {
      when(() => repository.login('user', 'pass')).thenAnswer((_) async => true);

      expect(bloc.stream, emitsInOrder([isA<SubtitleLoggingIn>(), isA<SubtitleLoggedIn>().having((s) => s.username, 'username', 'user')]));

      bloc.add(LoginToTitulky('user', 'pass'));
      await bloc.stream.firstWhere((s) => s is SubtitleLoggedIn);
      verify(() => repository.login('user', 'pass')).called(1);
    });

    test('emits LoginFailed when the site rejects the credentials', () async {
      when(() => repository.login(any(), any())).thenAnswer((_) async => false);

      bloc.add(LoginToTitulky('user', 'wrong'));
      final state = await bloc.stream.firstWhere((s) => s is SubtitleLoginFailed) as SubtitleLoginFailed;
      expect(state.message, 'auth.login_failed');
    });

    test('emits LoginFailed when the repository throws', () async {
      when(() => repository.login(any(), any())).thenThrow(Exception('network down'));

      bloc.add(LoginToTitulky('user', 'pass'));
      final state = await bloc.stream.firstWhere((s) => s is SubtitleLoginFailed) as SubtitleLoginFailed;
      expect(state.message, 'auth.login_error');
    });
  });

  group('auto-login', () {
    test('does nothing without saved credentials', () async {
      bloc.add(AutoLoginToTitulky());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state, isA<SubtitleInitial>());
      verifyNever(() => repository.login(any(), any()));
    });
  });

  group('logout', () {
    test('clears the repository session and returns to the initial state', () async {
      when(() => repository.logout()).thenAnswer((_) async {});

      bloc.add(LogoutFromTitulky());
      await bloc.stream.firstWhere((s) => s is SubtitleInitial);

      verify(() => repository.logout()).called(1);
    });
  });

  group('search', () {
    test('asks the site for the title plus the SxxExx marker', () async {
      when(() => repository.isLoggedIn).thenReturn(true);
      when(
        () => repository.searchSubtitles(
          any(),
          languageFilter: any(named: 'languageFilter'),
          page: any(named: 'page'),
          alternativeSearch: any(named: 'alternativeSearch'),
        ),
      ).thenAnswer((_) async => [_sub('True Detective S01E02 CZ')]);
      when(() => repository.getAlternativeSubtitles(any())).thenAnswer(
        (invocation) async => AlternativeSubtitlesResult(enhancedOriginal: invocation.positionalArguments.first as Subtitle, alternatives: const []),
      );

      bloc.add(SearchSubtitles(_video));
      await bloc.stream.firstWhere((s) => s is SubtitleSearchResults);

      verify(() => repository.searchSubtitles('True Detective S01E02', languageFilter: 'cs')).called(1);
    });

    test('emits results sorted by relevance', () async {
      when(() => repository.isLoggedIn).thenReturn(true);
      when(
        () => repository.searchSubtitles(
          any(),
          languageFilter: any(named: 'languageFilter'),
          page: any(named: 'page'),
          alternativeSearch: any(named: 'alternativeSearch'),
        ),
      ).thenAnswer((_) async => [_sub('True Detective S02E02'), _sub('True Detective S01E02')]);
      when(() => repository.getAlternativeSubtitles(any())).thenAnswer(
        (invocation) async => AlternativeSubtitlesResult(enhancedOriginal: invocation.positionalArguments.first as Subtitle, alternatives: const []),
      );

      bloc.add(SearchSubtitles(_video));
      final state = await bloc.stream.firstWhere((s) => s is SubtitleSearchResults) as SubtitleSearchResults;

      expect(state.videoInfo, _video);
      expect(state.sortedSubtitles!.allSorted.first.title, 'True Detective S01E02');
      expect(state.sortedSubtitles!.relevant.map((s) => s.title), ['True Detective S01E02']);
      expect(state.sortedSubtitles!.others.map((s) => s.title), ['True Detective S02E02']);
    });

    test('merges the "search differently" results when the first page is thin', () async {
      when(() => repository.isLoggedIn).thenReturn(true);
      when(
        () => repository.searchSubtitles(
          any(),
          languageFilter: any(named: 'languageFilter'),
          page: any(named: 'page'),
          alternativeSearch: false,
        ),
      ).thenAnswer((_) async => [_sub('True Detective S01E02', id: 'a')]);
      when(
        () => repository.searchSubtitles(
          any(),
          languageFilter: any(named: 'languageFilter'),
          page: any(named: 'page'),
          alternativeSearch: true,
        ),
      ).thenAnswer((_) async => [_sub('True Detective S01E02', id: 'a'), _sub('True Detective S01E02 alt', id: 'b')]);
      when(() => repository.getAlternativeSubtitles(any())).thenAnswer(
        (invocation) async => AlternativeSubtitlesResult(enhancedOriginal: invocation.positionalArguments.first as Subtitle, alternatives: const []),
      );

      bloc.add(SearchSubtitles(_video));
      final state = await bloc.stream.firstWhere((s) => s is SubtitleSearchResults) as SubtitleSearchResults;

      expect(state.subtitles.map((s) => s.id), ['a', 'b'], reason: 'the duplicate id must be filtered out');
    });

    test('reports that a login is required when there is no session', () async {
      when(() => repository.isLoggedIn).thenReturn(false);

      bloc.add(SearchSubtitles(_video));
      final state = await bloc.stream.firstWhere((s) => s is SubtitleError) as SubtitleError;

      expect(state.message, 'subtitle.login_required_for_search');
      verifyNever(() => repository.searchSubtitles(any(), languageFilter: any(named: 'languageFilter')));
    });

    test('reports a generic error when the site fails', () async {
      when(() => repository.isLoggedIn).thenReturn(true);
      when(
        () => repository.searchSubtitles(
          any(),
          languageFilter: any(named: 'languageFilter'),
          page: any(named: 'page'),
          alternativeSearch: any(named: 'alternativeSearch'),
        ),
      ).thenThrow(Exception('502 from titulky.com'));

      bloc.add(SearchSubtitles(_video));
      final state = await bloc.stream.firstWhere((s) => s is SubtitleError) as SubtitleError;
      expect(state.message, 'subtitle.search_error');
    });

    test('reports no results after every fallback query', () async {
      when(() => repository.isLoggedIn).thenReturn(true);
      when(
        () => repository.searchSubtitles(
          any(),
          languageFilter: any(named: 'languageFilter'),
          page: any(named: 'page'),
          alternativeSearch: any(named: 'alternativeSearch'),
        ),
      ).thenAnswer((_) async => const []);

      bloc.add(SearchSubtitles(_video));
      final state = await bloc.stream.firstWhere((s) => s is SubtitleError) as SubtitleError;
      expect(state.message, 'subtitle.no_results_after_fallback');
    });

    test('a manual query overrides the parsed title', () async {
      when(() => repository.isLoggedIn).thenReturn(true);
      when(
        () => repository.searchSubtitles(
          any(),
          languageFilter: any(named: 'languageFilter'),
          page: any(named: 'page'),
          alternativeSearch: any(named: 'alternativeSearch'),
        ),
      ).thenAnswer((_) async => [_sub('Detektiv S01E02')]);
      when(() => repository.getAlternativeSubtitles(any())).thenAnswer(
        (invocation) async => AlternativeSubtitlesResult(enhancedOriginal: invocation.positionalArguments.first as Subtitle, alternatives: const []),
      );

      bloc.add(SearchSubtitlesManual(_video, 'Temný případ'));
      await bloc.stream.firstWhere((s) => s is SubtitleSearchResults);

      verify(() => repository.searchSubtitles('Temný případ S01E02', languageFilter: 'cs')).called(1);
    });
  });

  group('cancel', () {
    test('stops an in-flight search', () async {
      when(() => repository.isLoggedIn).thenReturn(true);
      when(
        () => repository.searchSubtitles(
          any(),
          languageFilter: any(named: 'languageFilter'),
          page: any(named: 'page'),
          alternativeSearch: any(named: 'alternativeSearch'),
        ),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return [_sub('True Detective S01E02')];
      });

      bloc.add(SearchSubtitles(_video));
      await bloc.stream.firstWhere((s) => s is SubtitleSearching);
      bloc.add(CancelSubtitleSearch());

      final state = await bloc.stream.firstWhere((s) => s is SubtitleError) as SubtitleError;
      expect(state.message, 'subtitle.search_stopped');
    });

    test('does nothing when no search is running', () async {
      bloc.add(CancelSubtitleSearch());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<SubtitleInitial>());
    });
  });

  group('results interaction', () {
    Future<void> searchWith(List<Subtitle> found) async {
      when(() => repository.isLoggedIn).thenReturn(true);
      when(
        () => repository.searchSubtitles(
          any(),
          languageFilter: any(named: 'languageFilter'),
          page: any(named: 'page'),
          alternativeSearch: any(named: 'alternativeSearch'),
        ),
      ).thenAnswer((_) async => found);
      when(() => repository.getAlternativeSubtitles(any())).thenAnswer(
        (invocation) async => AlternativeSubtitlesResult(enhancedOriginal: invocation.positionalArguments.first as Subtitle, alternatives: const []),
      );

      bloc.add(SearchSubtitles(_video));
      await bloc.stream.firstWhere((s) => s is SubtitleSearchResults);
      // The search emits a second results state once alternatives are merged in;
      // let it land so the next stream event belongs to the test's own action.
      await pumpEventQueue();
    }

    test('toggling others flips which subtitles are displayed', () async {
      await searchWith([_sub('True Detective S01E02'), _sub('True Detective S02E02')]);

      final before = bloc.state as SubtitleSearchResults;
      expect(before.showOthers, isFalse);
      expect(before.displayedSubtitles.map((s) => s.title), ['True Detective S01E02']);
      expect(before.hasHiddenSubtitles, isTrue);
      expect(before.hiddenCount, 1);

      bloc.add(ToggleShowOtherSubtitles());
      final after = await bloc.stream.first as SubtitleSearchResults;

      expect(after.showOthers, isTrue);
      expect(after.displayedSubtitles.map((s) => s.title), ['True Detective S01E02', 'True Detective S02E02']);
      expect(after.hasHiddenSubtitles, isFalse);
    });

    test('selecting a subtitle records it without losing the results', () async {
      await searchWith([_sub('True Detective S01E02')]);
      final target = (bloc.state as SubtitleSearchResults).subtitles.first;

      bloc.add(SelectSubtitle(target));
      final state = await bloc.stream.first as SubtitleSearchResults;

      expect(state.selectedSubtitle, target);
      expect(state.subtitles, hasLength(1));
    });

    test('toggling is ignored before any search', () async {
      bloc.add(ToggleShowOtherSubtitles());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<SubtitleInitial>());
    });
  });

  group('download', () {
    test('emits Downloaded with the merge details of a multi-disc archive', () async {
      when(
        () => repository.saveSubtitleWithVideo(
          subtitle: any(named: 'subtitle'),
          videoPath: any(named: 'videoPath'),
        ),
      ).thenAnswer((_) async => SubtitleSaveResult(path: '/media/True.Detective.S01E02.720p.srt', partCount: 2, merged: true));

      final target = _sub('True Detective S01E02');
      bloc.add(DownloadSubtitle(target, _video));

      final state = await bloc.stream.firstWhere((s) => s is SubtitleDownloaded) as SubtitleDownloaded;
      expect(state.path, '/media/True.Detective.S01E02.720p.srt');
      expect(state.partCount, 2);
      expect(state.merged, isTrue);
      expect(state.wasMultiPart, isTrue);
    });

    test('emits an error when the repository returns nothing', () async {
      when(
        () => repository.saveSubtitleWithVideo(
          subtitle: any(named: 'subtitle'),
          videoPath: any(named: 'videoPath'),
        ),
      ).thenAnswer((_) async => null);

      bloc.add(DownloadSubtitle(_sub('x'), _video));
      final state = await bloc.stream.firstWhere((s) => s is SubtitleError) as SubtitleError;
      expect(state.message, 'subtitle.download_error');
    });

    test('emits an error when the download throws', () async {
      when(
        () => repository.saveSubtitleWithVideo(
          subtitle: any(named: 'subtitle'),
          videoPath: any(named: 'videoPath'),
        ),
      ).thenThrow(Exception('daily limit reached'));

      bloc.add(DownloadSubtitle(_sub('x'), _video));
      final state = await bloc.stream.firstWhere((s) => s is SubtitleError) as SubtitleError;
      expect(state.message, 'subtitle.download_error');
    });
  });
}
