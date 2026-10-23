import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/video_item.dart';
import '../../services/library_service.dart';
import '../../services/playra_storage.dart';

class LibraryState extends Equatable {
  /// Nothing to show yet: no earlier scan is stored.
  final bool loading;

  /// A scan is running while the videos from the last one are shown.
  final bool refreshing;
  final List<VideoItem> videos;
  final List<String> folders;
  final String? error;

  const LibraryState({this.loading = false, this.refreshing = false, this.videos = const [], this.folders = const [], this.error});

  LibraryState copyWith({bool? loading, bool? refreshing, List<VideoItem>? videos, List<String>? folders, String? error}) => LibraryState(
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    videos: videos ?? this.videos,
    folders: folders ?? this.folders,
    error: error,
  );

  @override
  List<Object?> get props => [loading, refreshing, videos, folders, error];
}

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit(this._service) : super(const LibraryState());

  final LibraryService _service;

  // Retry delays for background scans when initial load returns empty.
  static const List<Duration> _retryDelays = [Duration(seconds: 4), Duration(seconds: 12), Duration(seconds: 30), Duration(seconds: 60)];

  Timer? _retryTimer;
  int _retryAttempt = 0;

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
  }

  void _scheduleRetryIfNeeded(List<String> folders) {
    if (folders.isEmpty) return;
    if (_retryAttempt >= _retryDelays.length) return;

    final delay = _retryDelays[_retryAttempt];
    _retryAttempt++;
    _retryTimer = Timer(delay, () async {
      if (isClosed) return;
      await _loadInternal(isRetry: true);
    });
  }

  Future<void> refresh() async {
    _cancelRetry();
    await load();
  }

  Future<void> load() async {
    _cancelRetry();
    await _loadInternal(isRetry: false);
  }

  /// Shows the last scan straight away and replaces it folder by folder as
  /// the new scan finishes; a folder that is unreachable keeps its last
  /// known videos.
  Future<void> _loadInternal({required bool isRetry}) async {
    final folders = PlayraStorage.getLibraryFolders();
    final previous = state.videos.isNotEmpty ? state.videos : PlayraStorage.getLibrarySnapshot();
    if (!isRetry) {
      final shown = _compose(folders, const {}, previous);
      emit(state.copyWith(loading: shown.isEmpty, refreshing: true, videos: shown, folders: folders, error: null));
    }
    try {
      final scanned = <String, List<VideoItem>>{};
      for (final folder in folders) {
        final result = await _service.scanFolder(folder);
        if (isClosed) return;
        if (result == null) continue;
        scanned[folder] = result;
        final partial = _compose(folders, scanned, previous);
        await PlayraStorage.saveLibrarySnapshot(partial);
        if (!isClosed && partial.isNotEmpty) emit(state.copyWith(loading: false, videos: partial));
      }

      final videos = _compose(folders, scanned, previous);
      if (folders.isEmpty) await PlayraStorage.saveLibrarySnapshot(videos);

      // Merge standalone files (opened via the file picker) into the library.
      // Drop entries whose underlying local file no longer exists.
      _mergeStandaloneFiles(videos);

      if (!isClosed) {
        emit(state.copyWith(loading: false, refreshing: false, videos: videos, folders: folders));
      }

      // Schedule a background retry if no videos were found but folders are configured.
      if (videos.isEmpty && folders.isNotEmpty) {
        _scheduleRetryIfNeeded(folders);
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(loading: false, refreshing: false, error: e.toString()));
      }
      // Retry even after errors (network mounts can fail transiently).
      if (folders.isNotEmpty) {
        _scheduleRetryIfNeeded(folders);
      }
    }
  }

  /// The library in folder order: a folder's fresh scan where there is one,
  /// otherwise its videos from [previous].
  List<VideoItem> _compose(List<String> folders, Map<String, List<VideoItem>> scanned, List<VideoItem> previous) {
    final seen = <String>{};
    final out = <VideoItem>[];
    for (final folder in folders) {
      final videos = scanned[folder] ?? previous.where((v) => _isInFolder(v.id, folder));
      for (final video in videos) {
        if (!kSupportedVideoExtensions.contains(video.extension.toLowerCase())) continue;
        if (seen.add(video.id)) out.add(video);
      }
    }
    return out;
  }

  bool _isInFolder(String videoId, String folder) {
    final prefix = folder.endsWith('/') || folder.endsWith(Platform.pathSeparator)
        ? folder
        : '$folder${folder.startsWith('smb://') ? '/' : Platform.pathSeparator}';
    return videoId.startsWith(prefix);
  }

  /// Merges standalone files into [videos], skipping duplicates and pruning
  /// local files that no longer exist on disk.
  void _mergeStandaloneFiles(List<VideoItem> videos) {
    final standalone = PlayraStorage.getStandaloneFiles();
    for (final file in standalone) {
      if (!kSupportedVideoExtensions.contains(file.extension.toLowerCase())) continue;
      if (file.source == VideoSource.local && !File(file.uri).existsSync()) {
        unawaited(PlayraStorage.removeStandaloneFile(file.id));
        continue;
      }
      if (videos.any((existing) => existing.id == file.id)) continue;
      videos.add(file);
    }
  }

  Future<void> addFolder(String folder) async {
    _cancelRetry();
    await PlayraStorage.addLibraryFolder(folder);
    await load();
  }

  Future<void> removeFolder(String folder) async {
    _cancelRetry();
    await PlayraStorage.removeLibraryFolder(folder);
    await load();
  }

  @override
  Future<void> close() {
    _cancelRetry();
    return super.close();
  }
}
