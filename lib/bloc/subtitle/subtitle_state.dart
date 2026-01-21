import 'package:equatable/equatable.dart';

import '../../models/subtitle.dart';
import '../../models/video_info.dart';
import '../../services/subtitle_relevance_service.dart';

abstract class SubtitleState extends Equatable {
  @override
  List<Object?> get props => [];
}

class SubtitleInitial extends SubtitleState {}

class SubtitleLoggingIn extends SubtitleState {}

class SubtitleLoggedIn extends SubtitleState {
  final String username;

  SubtitleLoggedIn(this.username);

  @override
  List<Object> get props => [username];
}

class SubtitleLoginFailed extends SubtitleState {
  final String message;

  SubtitleLoginFailed(this.message);

  @override
  List<Object> get props => [message];
}

class SubtitleSearching extends SubtitleState {
  final VideoInfo videoInfo;
  final String? searchQuery;

  SubtitleSearching(this.videoInfo, {this.searchQuery});

  @override
  List<Object?> get props => [videoInfo, searchQuery];
}

class SubtitleSearchResults extends SubtitleState {
  final VideoInfo videoInfo;
  final List<Subtitle> subtitles;
  final Subtitle? selectedSubtitle;
  final SortedSubtitles? sortedSubtitles;
  final bool showOthers;
  final String searchQuery;
  final int currentPage;
  final bool hasMore;
  final bool isLoadingMore;

  SubtitleSearchResults({
    required this.videoInfo,
    required this.subtitles,
    this.selectedSubtitle,
    this.sortedSubtitles,
    this.showOthers = false,
    required this.searchQuery,
    this.currentPage = 1,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  /// Returns subtitles to display (relevant + others if shown)
  List<Subtitle> get displayedSubtitles {
    if (sortedSubtitles == null) return subtitles;
    if (showOthers) return sortedSubtitles!.allSorted;
    return sortedSubtitles!.relevant.isEmpty ? sortedSubtitles!.allSorted : sortedSubtitles!.relevant;
  }

  /// Number of hidden subtitles
  int get hiddenCount => sortedSubtitles?.othersCount ?? 0;

  /// Has hidden subtitles?
  bool get hasHiddenSubtitles => !showOthers && (sortedSubtitles?.hasOthers ?? false);

  SubtitleSearchResults copyWith({
    VideoInfo? videoInfo,
    List<Subtitle>? subtitles,
    Subtitle? selectedSubtitle,
    SortedSubtitles? sortedSubtitles,
    bool? showOthers,
    String? searchQuery,
    int? currentPage,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return SubtitleSearchResults(
      videoInfo: videoInfo ?? this.videoInfo,
      subtitles: subtitles ?? this.subtitles,
      selectedSubtitle: selectedSubtitle ?? this.selectedSubtitle,
      sortedSubtitles: sortedSubtitles ?? this.sortedSubtitles,
      showOthers: showOthers ?? this.showOthers,
      searchQuery: searchQuery ?? this.searchQuery,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => [videoInfo, subtitles, selectedSubtitle, sortedSubtitles, showOthers, searchQuery, currentPage, hasMore, isLoadingMore];
}

class SubtitleDownloading extends SubtitleState {
  final Subtitle subtitle;

  SubtitleDownloading(this.subtitle);

  @override
  List<Object> get props => [subtitle];
}

class SubtitleDownloaded extends SubtitleState {
  final Subtitle subtitle;
  final String path;

  SubtitleDownloaded(this.subtitle, this.path);

  @override
  List<Object> get props => [subtitle, path];
}

class SubtitleError extends SubtitleState {
  final String message;

  SubtitleError(this.message);

  @override
  List<Object> get props => [message];
}
