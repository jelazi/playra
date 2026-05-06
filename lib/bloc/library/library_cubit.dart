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

  Future<void> refresh() async {
    await load();
  }

  Future<void> load() async {
    final folders = PlayraStorage.getPlayerSettings().libraryFolders;
    emit(state.copyWith(loading: true, folders: folders, error: null));
    try {
      final videos = await _service.listFolders(folders, recursive: true);
      emit(state.copyWith(loading: false, videos: videos));
    } catch (e) {
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
