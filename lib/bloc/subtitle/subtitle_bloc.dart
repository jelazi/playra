import 'package:flutter_bloc/flutter_bloc.dart';

import '../../repositories/titulky_repository.dart';
import '../../services/settings_service.dart';
import '../../services/subtitle_relevance_service.dart';
import '../../services/video_name_parser.dart';
import 'subtitle_event.dart';
import 'subtitle_state.dart';

class SubtitleBloc extends Bloc<SubtitleEvent, SubtitleState> {
  final TitulkyRepository _repository;

  SubtitleBloc({required TitulkyRepository repository}) : _repository = repository, super(SubtitleInitial()) {
    on<LoginToTitulky>(_onLoginToTitulky);
    on<AutoLoginToTitulky>(_onAutoLoginToTitulky);
    on<SearchSubtitles>(_onSearchSubtitles);
    on<SearchSubtitlesManual>(_onSearchSubtitlesManual);
    on<LoadMoreSubtitles>(_onLoadMoreSubtitles);
    on<SelectSubtitle>(_onSelectSubtitle);
    on<DownloadSubtitle>(_onDownloadSubtitle);
    on<LogoutFromTitulky>(_onLogoutFromTitulky);
    on<ToggleShowOtherSubtitles>(_onToggleShowOtherSubtitles);
    on<FetchAlternativeSubtitles>(_onFetchAlternativeSubtitles);
  }

  Future<void> _onLoginToTitulky(LoginToTitulky event, Emitter<SubtitleState> emit) async {
    print('🔵 SubtitleBloc: LoginToTitulky event received for username: ${event.username}');
    emit(SubtitleLoggingIn());
    print('🔵 SubtitleBloc: Emitted SubtitleLoggingIn state');
    try {
      print('🔵 SubtitleBloc: Calling repository.login()...');
      final success = await _repository.login(event.username, event.password);
      print('🔵 SubtitleBloc: Login result: $success');
      if (success) {
        print('🔵 SubtitleBloc: Login successful, emitting SubtitleLoggedIn');
        // Save login credentials if requested
        if (event.saveCredentials) {
          await SettingsService.saveCredentials(event.username, event.password);
          print('🔵 SubtitleBloc: Credentials saved');
        }
        emit(SubtitleLoggedIn(event.username));
      } else {
        print('🔵 SubtitleBloc: Login failed, emitting SubtitleLoginFailed');
        emit(SubtitleLoginFailed('auth.login_failed'));
      }
    } catch (e) {
      print('🔴 SubtitleBloc: Login error: $e');
      emit(SubtitleLoginFailed('auth.login_error'));
    }
  }

  /// Auto-login from saved credentials
  Future<void> _onAutoLoginToTitulky(AutoLoginToTitulky event, Emitter<SubtitleState> emit) async {
    print('🔵 SubtitleBloc: AutoLoginToTitulky event received');
    final settings = SettingsService.getSettings();

    if (settings.username == null || settings.username!.isEmpty || settings.password == null || settings.password!.isEmpty) {
      print('🔵 SubtitleBloc: No saved credentials, skipping auto-login');
      return;
    }

    print('🔵 SubtitleBloc: Found saved credentials for: ${settings.username}');
    emit(SubtitleLoggingIn());

    try {
      final success = await _repository.login(settings.username!, settings.password!);
      print('🔵 SubtitleBloc: Auto-login result: $success');
      if (success) {
        print('🔵 SubtitleBloc: Auto-login successful');
        emit(SubtitleLoggedIn(settings.username!));
      } else {
        print('🔵 SubtitleBloc: Auto-login failed, clearing credentials');
        await SettingsService.clearCredentials();
        emit(SubtitleInitial());
      }
    } catch (e) {
      print('🔴 SubtitleBloc: Auto-login error: $e');
      emit(SubtitleInitial());
    }
  }

  Future<void> _onSearchSubtitles(SearchSubtitles event, Emitter<SubtitleState> emit) async {
    // Parse video name to extract season/episode
    final parsedVideo = VideoNameParser.parse(event.videoInfo.path);
    print('🔵 Parsed video: ${parsedVideo.cleanName}, isTV: ${parsedVideo.isTV}, S${parsedVideo.season}E${parsedVideo.episode}');

    // Build search query - add season/episode if exists
    String searchQuery = parsedVideo.cleanName;
    if (parsedVideo.isTV && parsedVideo.season != null && parsedVideo.episode != null) {
      final seasonStr = parsedVideo.season.toString().padLeft(2, '0');
      final episodeStr = parsedVideo.episode.toString().padLeft(2, '0');
      searchQuery = '${parsedVideo.cleanName} S${seasonStr}E$episodeStr';
    }
    print('🔵 Search query: $searchQuery');

    emit(SubtitleSearching(event.videoInfo, searchQuery: searchQuery));
    try {
      // Get preferred language from settings
      final settings = SettingsService.getSettings();
      final languageFilter = settings.preferredSubtitleLanguage ?? 'cs';

      final subtitles = await _repository.searchSubtitles(searchQuery, languageFilter: languageFilter == 'all' ? null : languageFilter);

      if (subtitles.isEmpty) {
        emit(SubtitleError('subtitle.no_results'));
      } else {
        // Sort subtitles by relevance
        final sortedSubtitles = SubtitleRelevanceService.sortByRelevance(subtitles, parsedVideo);
        print('🔵 Sorted subtitles: ${sortedSubtitles.relevantCount} relevant, ${sortedSubtitles.othersCount} others');

        // If we have exactly 25 results, there probably is another page
        final hasMore = subtitles.length >= 25;

        emit(
          SubtitleSearchResults(
            videoInfo: event.videoInfo,
            subtitles: subtitles,
            sortedSubtitles: sortedSubtitles,
            showOthers: false,
            searchQuery: searchQuery,
            currentPage: 1,
            hasMore: hasMore,
          ),
        );
      }
    } catch (e) {
      print('🔴 SubtitleBloc: Search error: $e');
      emit(SubtitleError('subtitle.search_error'));
    }
  }

  /// Manual search with custom query
  Future<void> _onSearchSubtitlesManual(SearchSubtitlesManual event, Emitter<SubtitleState> emit) async {
    final parsedVideo = VideoNameParser.parse(event.videoInfo.path);
    final searchQuery = event.query.trim();

    print('🔵 Manual search query: $searchQuery');
    emit(SubtitleSearching(event.videoInfo, searchQuery: searchQuery));

    try {
      final settings = SettingsService.getSettings();
      final languageFilter = settings.preferredSubtitleLanguage ?? 'cs';

      final subtitles = await _repository.searchSubtitles(searchQuery, languageFilter: languageFilter == 'all' ? null : languageFilter);

      if (subtitles.isEmpty) {
        emit(SubtitleError('subtitle.no_results'));
      } else {
        final sortedSubtitles = SubtitleRelevanceService.sortByRelevance(subtitles, parsedVideo);
        print('🔵 Sorted subtitles: ${sortedSubtitles.relevantCount} relevant, ${sortedSubtitles.othersCount} others');

        final hasMore = subtitles.length >= 25;

        emit(
          SubtitleSearchResults(
            videoInfo: event.videoInfo,
            subtitles: subtitles,
            sortedSubtitles: sortedSubtitles,
            showOthers: false,
            searchQuery: searchQuery,
            currentPage: 1,
            hasMore: hasMore,
          ),
        );
      }
    } catch (e) {
      print('🔴 SubtitleBloc: Manual search error: $e');
      emit(SubtitleError('subtitle.search_error'));
    }
  }

  /// Load next page of results
  Future<void> _onLoadMoreSubtitles(LoadMoreSubtitles event, Emitter<SubtitleState> emit) async {
    if (state is! SubtitleSearchResults) return;

    final currentState = state as SubtitleSearchResults;
    if (!currentState.hasMore || currentState.isLoadingMore) return;

    emit(currentState.copyWith(isLoadingMore: true));

    try {
      final settings = SettingsService.getSettings();
      final languageFilter = settings.preferredSubtitleLanguage ?? 'cs';
      final nextPage = currentState.currentPage + 1;

      print('🔵 Loading page $nextPage for query: ${currentState.searchQuery}');

      final newSubtitles = await _repository.searchSubtitles(currentState.searchQuery, languageFilter: languageFilter == 'all' ? null : languageFilter, page: nextPage);

      if (newSubtitles.isEmpty) {
        emit(currentState.copyWith(hasMore: false, isLoadingMore: false));
      } else {
        // Add new subtitles to existing ones
        final allSubtitles = [...currentState.subtitles, ...newSubtitles];

        // Re-sort all subtitles
        final parsedVideo = VideoNameParser.parse(currentState.videoInfo.path);
        final sortedSubtitles = SubtitleRelevanceService.sortByRelevance(allSubtitles, parsedVideo);

        final hasMore = newSubtitles.length >= 25;

        emit(currentState.copyWith(subtitles: allSubtitles, sortedSubtitles: sortedSubtitles, currentPage: nextPage, hasMore: hasMore, isLoadingMore: false));

        print('🔵 Loaded ${newSubtitles.length} more subtitles. Total: ${allSubtitles.length}');
      }
    } catch (e) {
      print('🔴 SubtitleBloc: Load more error: $e');
      emit(currentState.copyWith(isLoadingMore: false));
    }
  }

  Future<void> _onSelectSubtitle(SelectSubtitle event, Emitter<SubtitleState> emit) async {
    if (state is SubtitleSearchResults) {
      final currentState = state as SubtitleSearchResults;
      emit(currentState.copyWith(selectedSubtitle: event.subtitle));
    }
  }

  Future<void> _onDownloadSubtitle(DownloadSubtitle event, Emitter<SubtitleState> emit) async {
    emit(SubtitleDownloading(event.subtitle));
    try {
      final path = await _repository.saveSubtitleWithVideo(subtitle: event.subtitle, videoPath: event.videoInfo.path);

      if (path != null) {
        // Save the information that subtitles were downloaded for this video
        await SettingsService.markVideoWithSubtitles(event.videoInfo.path);
        print('🔵 SubtitleBloc: Marked video ${event.videoInfo.path} as having downloaded subtitles');

        emit(SubtitleDownloaded(event.subtitle, path));
      } else {
        emit(SubtitleError('subtitle.download_error'));
      }
    } catch (e) {
      print('🔴 SubtitleBloc: Download error: $e');
      emit(SubtitleError('subtitle.download_error'));
    }
  }

  Future<void> _onLogoutFromTitulky(LogoutFromTitulky event, Emitter<SubtitleState> emit) async {
    print('🔵 SubtitleBloc: Logout, clearing credentials');
    await _repository.logout();
    await SettingsService.clearCredentials();
    emit(SubtitleInitial());
  }

  void _onToggleShowOtherSubtitles(ToggleShowOtherSubtitles event, Emitter<SubtitleState> emit) {
    if (state is SubtitleSearchResults) {
      final currentState = state as SubtitleSearchResults;
      emit(currentState.copyWith(showOthers: !currentState.showOthers));
    }
  }

  /// Fetch alternative subtitles for a selected subtitle
  Future<void> _onFetchAlternativeSubtitles(FetchAlternativeSubtitles event, Emitter<SubtitleState> emit) async {
    if (state is! SubtitleSearchResults) return;

    final currentState = state as SubtitleSearchResults;

    // Set loading state and select the subtitle
    emit(currentState.copyWith(selectedSubtitle: event.subtitle, isLoadingAlternatives: true, clearAlternatives: true));

    try {
      print('🔵 Fetching alternative subtitles for: ${event.subtitle.title}');

      final alternatives = await _repository.getAlternativeSubtitles(event.subtitle);

      if (alternatives.isNotEmpty) {
        print('🔵 Found ${alternatives.length} alternative subtitles');

        // Filter out duplicates that are already in the main list
        final existingIds = currentState.subtitles.map((s) => s.id).toSet();
        final newAlternatives = alternatives.where((alt) => !existingIds.contains(alt.id)).toList();

        print('🔵 New alternatives (not in main list): ${newAlternatives.length}');

        // Get current state again in case it changed
        if (state is SubtitleSearchResults) {
          final updatedState = state as SubtitleSearchResults;
          emit(updatedState.copyWith(alternativeSubtitles: newAlternatives, isLoadingAlternatives: false));
        }
      } else {
        print('🔵 No alternative subtitles found');
        if (state is SubtitleSearchResults) {
          final updatedState = state as SubtitleSearchResults;
          emit(updatedState.copyWith(alternativeSubtitles: [], isLoadingAlternatives: false));
        }
      }
    } catch (e) {
      print('🔴 Error fetching alternative subtitles: $e');
      if (state is SubtitleSearchResults) {
        final updatedState = state as SubtitleSearchResults;
        emit(updatedState.copyWith(isLoadingAlternatives: false));
      }
    }
  }
}
