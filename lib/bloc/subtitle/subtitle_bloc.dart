import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/subtitle.dart';
import '../../models/video_info.dart';
import '../../repositories/titulky_repository.dart';
import '../../services/media_cache_service.dart';
import '../../services/settings_service.dart';
import '../../services/subtitle_relevance_service.dart';
import '../../services/video_name_parser.dart';
import 'subtitle_event.dart';
import 'subtitle_state.dart';

class SubtitleBloc extends Bloc<SubtitleEvent, SubtitleState> {
  final TitulkyRepository _repository;
  int _searchToken = 0;

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
    on<CancelSubtitleSearch>(_onCancelSubtitleSearch);
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
    final token = _beginNewSearch();

    // Parse video name to extract season/episode
    final parsedVideo = VideoNameParser.parse(event.videoInfo.path);
    print('🔵 Parsed video: ${parsedVideo.cleanName}, isTV: ${parsedVideo.isTV}, S${parsedVideo.season}E${parsedVideo.episode}');

    final preferredTitle = _resolvePreferredSearchTitle(parsedVideo.cleanName);
    final searchQueries = _buildProgressiveQueries(baseTitle: preferredTitle, parsedVideo: parsedVideo);

    final firstQuery = searchQueries.isNotEmpty ? searchQueries.first : preferredTitle;
    print('🔵 Search queries (${searchQueries.length}): $searchQueries');

    emit(SubtitleSearching(event.videoInfo, searchQuery: firstQuery));
    try {
      await _ensureAuthenticated();

      // Get preferred language from settings
      final settings = SettingsService.getSettings();
      final languageFilter = settings.preferredSubtitleLanguage ?? 'cs';
      final normalizedLang = languageFilter == 'all' ? null : languageFilter;

      final result = await _searchWithProgressiveFallback(event.videoInfo, searchQueries, normalizedLang, token, emit);
      _throwIfSearchCancelled(token);

      final subtitles = result.subtitles;
      final effectiveQuery = result.query;

      if (subtitles.isEmpty) {
        emit(SubtitleError('subtitle.no_results_after_fallback'));
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
            searchQuery: effectiveQuery,
            currentPage: 1,
            hasMore: hasMore,
          ),
        );

        // Flatten alternatives into the main list in the background
        await _enrichWithFlatAlternatives(emit, parsedVideo);
      }
    } on _SearchCancelledException {
      // Ignore; explicit cancel handler already emitted a user-facing state.
    } catch (e) {
      print('🔴 SubtitleBloc: Search error: $e');
      emit(SubtitleError(_mapSearchErrorToMessageKey(e)));
    }
  }

  /// Manual search with custom query
  Future<void> _onSearchSubtitlesManual(SearchSubtitlesManual event, Emitter<SubtitleState> emit) async {
    final token = _beginNewSearch();
    final parsedVideo = VideoNameParser.parse(event.videoInfo.path);
    final manualQuery = event.query.trim();
    final searchQueries = _buildProgressiveQueries(baseTitle: manualQuery, parsedVideo: parsedVideo);
    final firstQuery = searchQueries.isNotEmpty ? searchQueries.first : manualQuery;

    print('🔵 Manual search queries (${searchQueries.length}): $searchQueries');
    emit(SubtitleSearching(event.videoInfo, searchQuery: firstQuery));

    try {
      await _ensureAuthenticated();

      final settings = SettingsService.getSettings();
      final languageFilter = settings.preferredSubtitleLanguage ?? 'cs';
      final normalizedLang = languageFilter == 'all' ? null : languageFilter;

      final result = await _searchWithProgressiveFallback(event.videoInfo, searchQueries, normalizedLang, token, emit);
      _throwIfSearchCancelled(token);

      final subtitles = result.subtitles;
      final effectiveQuery = result.query;

      if (subtitles.isEmpty) {
        emit(SubtitleError('subtitle.no_results_after_fallback'));
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
            searchQuery: effectiveQuery,
            currentPage: 1,
            hasMore: hasMore,
          ),
        );

        await _enrichWithFlatAlternatives(emit, parsedVideo);
      }
    } on _SearchCancelledException {
      // Ignore; explicit cancel handler already emitted a user-facing state.
    } catch (e) {
      print('🔴 SubtitleBloc: Manual search error: $e');
      emit(SubtitleError(_mapSearchErrorToMessageKey(e)));
    }
  }

  Future<_SearchResultWithQuery> _searchWithProgressiveFallback(VideoInfo videoInfo, List<String> queries, String? languageFilter, int token, Emitter<SubtitleState> emit) async {
    if (queries.isEmpty) {
      return const _SearchResultWithQuery([], '');
    }

    for (final query in queries) {
      _throwIfSearchCancelled(token);
      emit(SubtitleSearching(videoInfo, searchQuery: query));
      final subtitles = await _fetchSubtitlesWithFallback(query, languageFilter);
      _throwIfSearchCancelled(token);
      if (subtitles.isNotEmpty) {
        return _SearchResultWithQuery(subtitles, query);
      }
    }

    return _SearchResultWithQuery(const [], queries.last);
  }

  /// Runs primary search and, if results are scarce, transparently appends the
  /// "Vyhledat jinak" (fsf=1) results. Duplicates are filtered by subtitle id.
  Future<List<Subtitle>> _fetchSubtitlesWithFallback(String query, String? languageFilter) async {
    final primary = await _repository.searchSubtitles(query, languageFilter: languageFilter);

    // Site offers "Vyhledat jinak" (alternative/fuzzy search) when few results
    // are returned. Trigger it automatically for <= 3 primary results.
    if (primary.length > 3) {
      return primary;
    }

    try {
      final alternative = await _repository.searchSubtitles(query, languageFilter: languageFilter, alternativeSearch: true);
      if (alternative.isEmpty) return primary;

      final seen = primary.map((s) => s.id).toSet();
      final merged = <Subtitle>[...primary];
      for (final s in alternative) {
        if (seen.add(s.id)) merged.add(s);
      }
      print('🔵 Merged fsf=1 results: +${merged.length - primary.length} extra (total ${merged.length})');
      return merged;
    } catch (e) {
      print('🟡 Alternative search (fsf=1) failed: $e');
      return primary;
    }
  }

  /// Fetches the "Alternativní titulky" table for each result and merges those
  /// subtitles into the main list so the UI shows every variant flat, without
  /// the user needing to open a card to discover them.
  Future<void> _enrichWithFlatAlternatives(Emitter<SubtitleState> emit, ParsedVideoName parsedVideo) async {
    if (state is! SubtitleSearchResults) return;
    final baseState = state as SubtitleSearchResults;
    final baseQuery = baseState.searchQuery;

    // Fetch in parallel (user has premium; all requests are cookie-authenticated)
    final futures = baseState.subtitles.map<Future<AlternativeSubtitlesResult>>((s) async {
      try {
        return await _repository.getAlternativeSubtitles(s);
      } catch (e) {
        return AlternativeSubtitlesResult(enhancedOriginal: s, alternatives: const []);
      }
    });

    final results = await Future.wait(futures);

    // Bail out if user moved on to a different search in the meantime
    if (state is! SubtitleSearchResults) return;
    final currentState = state as SubtitleSearchResults;
    if (currentState.searchQuery != baseQuery) return;

    final enhancedById = <String, Subtitle>{};
    for (final r in results) {
      enhancedById[r.enhancedOriginal.id] = r.enhancedOriginal;
    }

    final seen = currentState.subtitles.map((s) => s.id).toSet();
    final extras = <Subtitle>[];
    for (final r in results) {
      for (final alt in r.alternatives) {
        if (seen.add(alt.id)) extras.add(alt);
      }
    }

    // Replace originals with their enhanced versions where available.
    final enrichedOriginals = currentState.subtitles.map((s) => enhancedById[s.id] ?? s).toList();

    final allSubtitles = <Subtitle>[...enrichedOriginals, ...extras];
    final sorted = SubtitleRelevanceService.sortByRelevance(allSubtitles, parsedVideo);
    print('🔵 Flattened alternatives: +${extras.length} (total ${allSubtitles.length})');

    emit(currentState.copyWith(subtitles: allSubtitles, sortedSubtitles: sorted));
  }

  /// Load next page of results
  Future<void> _onLoadMoreSubtitles(LoadMoreSubtitles event, Emitter<SubtitleState> emit) async {
    if (state is! SubtitleSearchResults) return;

    final currentState = state as SubtitleSearchResults;
    if (!currentState.hasMore || currentState.isLoadingMore) return;

    emit(currentState.copyWith(isLoadingMore: true));

    try {
      await _ensureAuthenticated();

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

  Future<void> _ensureAuthenticated() async {
    if (_repository.isLoggedIn) return;

    final settings = SettingsService.getSettings();
    final username = settings.username;
    final password = settings.password;

    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      throw Exception('Missing saved titulky.com credentials');
    }

    final success = await _repository.login(username, password);
    if (!success) {
      throw Exception('Auto-login failed');
    }
  }

  void _onCancelSubtitleSearch(CancelSubtitleSearch event, Emitter<SubtitleState> emit) {
    _cancelCurrentSearch();
    if (state is SubtitleSearching) {
      emit(SubtitleError('subtitle.search_stopped'));
    }
  }

  int _beginNewSearch() {
    _searchToken += 1;
    return _searchToken;
  }

  void _cancelCurrentSearch() {
    _searchToken += 1;
  }

  void _throwIfSearchCancelled(int token) {
    if (token != _searchToken) {
      throw const _SearchCancelledException();
    }
  }

  String _resolvePreferredSearchTitle(String cleanName) {
    final cached = MediaCacheService.getMapping(cleanName);
    final preferred = cached?.title.trim();
    if (preferred != null && preferred.isNotEmpty) {
      return preferred;
    }
    return cleanName;
  }

  List<String> _buildProgressiveQueries({required String baseTitle, required ParsedVideoName parsedVideo}) {
    final normalized = baseTitle.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return const [];

    String? suffix;
    if (parsedVideo.isTV && parsedVideo.season != null && parsedVideo.episode != null) {
      final seasonStr = parsedVideo.season.toString().padLeft(2, '0');
      final episodeStr = parsedVideo.episode.toString().padLeft(2, '0');
      suffix = 'S${seasonStr}E$episodeStr';
    }

    final words = normalized.split(' ');
    final queries = <String>[];
    for (var count = words.length; count >= 1; count--) {
      final core = words.take(count).join(' ').trim();
      if (core.isEmpty) continue;
      final q = suffix == null ? core : '$core $suffix';
      if (!queries.contains(q)) {
        queries.add(q);
      }
    }

    return queries;
  }

  String _mapSearchErrorToMessageKey(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('missing saved titulky.com credentials') || raw.contains('auto-login failed')) {
      return 'subtitle.login_required_for_search';
    }
    return 'subtitle.search_error';
  }

  Future<void> _onSelectSubtitle(SelectSubtitle event, Emitter<SubtitleState> emit) async {
    if (state is SubtitleSearchResults) {
      final currentState = state as SubtitleSearchResults;
      emit(currentState.copyWith(selectedSubtitle: event.subtitle));
    }
  }

  Future<void> _onDownloadSubtitle(DownloadSubtitle event, Emitter<SubtitleState> emit) async {
    // Save previous state to restore after download
    final previousState = state is SubtitleSearchResults ? state as SubtitleSearchResults : null;

    emit(SubtitleDownloading(event.subtitle));
    try {
      final result = await _repository.saveSubtitleWithVideo(subtitle: event.subtitle, videoPath: event.videoInfo.path);

      if (result != null) {
        // Save the information that subtitles were downloaded for this video
        await SettingsService.markVideoWithSubtitles(event.videoInfo.path);
        print('🔵 SubtitleBloc: Marked video ${event.videoInfo.path} as having downloaded subtitles');

        emit(SubtitleDownloaded(event.subtitle, result.path, partCount: result.partCount, merged: result.merged));

        // Restore previous SubtitleSearchResults state after a brief delay
        // This preserves the selection and alternatives when returning from player
        if (previousState != null) {
          await Future.delayed(const Duration(milliseconds: 100));
          emit(previousState.copyWith(selectedSubtitle: event.subtitle));
          print('🔵 SubtitleBloc: Restored SubtitleSearchResults state with selection preserved');
        }
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
      print('🔵 Fetching alternative subtitles and enhanced details for: ${event.subtitle.title}');

      final result = await _repository.getAlternativeSubtitles(event.subtitle);

      print('🔵 Found ${result.alternatives.length} alternative subtitles');
      print('🔵 Enhanced original subtitle with details: ${result.enhancedOriginal.uploader != null || result.enhancedOriginal.details != null}');

      // Filter out duplicates that are already in the main list
      final existingIds = currentState.subtitles.map((s) => s.id).toSet();
      final newAlternatives = result.alternatives.where((alt) => !existingIds.contains(alt.id)).toList();

      print('🔵 New alternatives (not in main list): ${newAlternatives.length}');

      // Get current state again in case it changed
      if (state is SubtitleSearchResults) {
        final updatedState = state as SubtitleSearchResults;
        emit(updatedState.copyWith(enhancedOriginal: result.enhancedOriginal, alternativeSubtitles: newAlternatives, isLoadingAlternatives: false));
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

class _SearchResultWithQuery {
  final List<Subtitle> subtitles;
  final String query;

  const _SearchResultWithQuery(this.subtitles, this.query);
}

class _SearchCancelledException implements Exception {
  const _SearchCancelledException();
}
