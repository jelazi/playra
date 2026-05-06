import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
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

  void _debugLog(String message) {
    if (kDebugMode) {
      print('[LibraryCubit] $message');
      debugPrint('[LibraryCubit] $message');
    }
  }

  Future<void> refresh() async {
    await load();
  }

  Future<void> load() async {
    final folders = PlayraStorage.getPlayerSettings().libraryFolders;
    emit(state.copyWith(loading: true, folders: folders, error: null));
    try {
      final loadedVideos = await _service.listFolders(folders, recursive: true);
      _debugLog('Loaded raw items count=${loadedVideos.length} folders=${folders.join(', ')}');
      for (final item in loadedVideos.take(50)) {
        _debugLog('Raw item: name=${item.name} ext=${item.extension} uri=${item.uri}');
      }

      final videos = loadedVideos
          .where((video) {
            final accepted = kSupportedVideoExtensions.contains(video.extension);
            if (!accepted) {
              _debugLog('Rejecting non-video item in cubit: name=${video.name} ext=${video.extension} uri=${video.uri}');
            }
            return accepted;
          })
          .fold<List<VideoItem>>(<VideoItem>[], (acc, video) {
            if (acc.any((existing) => existing.id == video.id)) return acc;
            acc.add(video);
            return acc;
          });
      _debugLog('Emitting filtered videos count=${videos.length} items=${videos.take(50).map((e) => e.name).join(', ')}');
      emit(state.copyWith(loading: false, videos: videos));
    } catch (e) {
      _debugLog('Load failed: $e');
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> addFolder(String folder) async {
    final settings = PlayraStorage.getPlayerSettings();
    if (settings.libraryFolders.contains(folder)) return;
    final updated = settings.copyWith(libraryFolders: [...settings.libraryFolders, folder]);
    await PlayraStorage.savePlayerSettings(updated);
    await load();
  }

  Future<void> removeFolder(String folder) async {
    final settings = PlayraStorage.getPlayerSettings();
    final updated = settings.copyWith(libraryFolders: settings.libraryFolders.where((f) => f != folder).toList());
    await PlayraStorage.savePlayerSettings(updated);
    await load();
  }
}
