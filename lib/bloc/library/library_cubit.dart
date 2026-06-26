import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/video_item.dart';
import '../../services/library_service.dart';
import '../../services/playra_storage.dart';

class LibraryState extends Equatable {
  final bool loading;
  final List<VideoItem> videos;
  final List<String> folders;
  final String? error;

  const LibraryState({this.loading = false, this.videos = const [], this.folders = const [], this.error});

  LibraryState copyWith({bool? loading, List<VideoItem>? videos, List<String>? folders, String? error}) =>
      LibraryState(loading: loading ?? this.loading, videos: videos ?? this.videos, folders: folders ?? this.folders, error: error);

  @override
  List<Object?> get props => [loading, videos, folders, error];
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

  Future<void> _loadInternal({required bool isRetry}) async {
    final folders = PlayraStorage.getLibraryFolders();
    if (!isRetry) {
      emit(state.copyWith(loading: true, folders: folders, error: null));
    }
    try {
      final loadedVideos = await _service.listFolders(folders, recursive: true);

      final videos = loadedVideos.where((video) => kSupportedVideoExtensions.contains(video.extension.toLowerCase())).fold<List<VideoItem>>(<VideoItem>[], (acc, video) {
        if (acc.any((existing) => existing.id == video.id)) return acc;
        acc.add(video);
        return acc;
      });

      // Merge standalone files (opened via the file picker) into the library.
      // Drop entries whose underlying local file no longer exists.
      _mergeStandaloneFiles(videos);

      if (!isClosed) {
        emit(state.copyWith(loading: false, videos: videos, folders: folders));
      }

      // Schedule a background retry if no videos were found but folders are configured.
      if (videos.isEmpty && folders.isNotEmpty) {
        _scheduleRetryIfNeeded(folders);
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(loading: false, error: e.toString()));
      }
      // Retry even after errors (network mounts can fail transiently).
      if (folders.isNotEmpty) {
        _scheduleRetryIfNeeded(folders);
      }
    }
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
