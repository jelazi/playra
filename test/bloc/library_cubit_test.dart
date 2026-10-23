import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:playra/bloc/library/library_cubit.dart';
import 'package:playra/models/video_item.dart';
import 'package:playra/services/library_service.dart';
import 'package:playra/services/playra_storage.dart';

class _FakeLibraryService extends LibraryService {
  final Map<String, Completer<List<VideoItem>?>> scans = {};

  @override
  Future<List<VideoItem>?> scanFolder(String folder, {bool recursive = true}) => (scans[folder] ??= Completer<List<VideoItem>?>()).future;
}

VideoItem _video(String folder, String name) => VideoItem(id: '$folder/$name', name: name, uri: '$folder/$name', source: VideoSource.smb);

void main() {
  const movies = 'smb://nas/share/Filmy';
  const shows = 'smb://nas/share/Serialy';

  late Directory tempDir;
  late _FakeLibraryService service;
  late LibraryCubit cubit;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('playra_library_cubit_test');
    Hive.init(tempDir.path);
    await PlayraStorage.init();
    await PlayraStorage.setLibraryFolders([movies, shows]);
    service = _FakeLibraryService();
    cubit = LibraryCubit(service);
  });

  tearDown(() async {
    await cubit.close();
    await Hive.deleteFromDisk();
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('shows the stored library at once and replaces it folder by folder', () async {
    await PlayraStorage.saveLibrarySnapshot([_video(movies, 'Old.mkv'), _video(shows, 'Show.S01E01.mkv')]);

    final loading = cubit.load();
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.refreshing, isTrue);
    expect(cubit.state.videos.map((v) => v.name), ['Old.mkv', 'Show.S01E01.mkv']);

    service.scans[movies]!.complete([_video(movies, 'New.mkv')]);
    await pumpEventQueue();
    expect(cubit.state.videos.map((v) => v.name), ['New.mkv', 'Show.S01E01.mkv']);
    expect(cubit.state.refreshing, isTrue);

    service.scans[shows]!.complete([_video(shows, 'Show.S01E02.mkv')]);
    await loading;
    expect(cubit.state.refreshing, isFalse);
    expect(cubit.state.videos.map((v) => v.name), ['New.mkv', 'Show.S01E02.mkv']);
    expect(PlayraStorage.getLibrarySnapshot().map((v) => v.name), ['New.mkv', 'Show.S01E02.mkv']);
  });

  test('an unreachable folder keeps its last known videos', () async {
    await PlayraStorage.saveLibrarySnapshot([_video(movies, 'Old.mkv'), _video(shows, 'Show.S01E01.mkv')]);

    final loading = cubit.load();
    service.scans[movies]!.complete(null);
    await pumpEventQueue();
    service.scans[shows]!.complete([]);
    await loading;

    expect(cubit.state.videos.map((v) => v.name), ['Old.mkv']);
  });

  test('without a stored library the first scan shows a loading state', () async {
    final loading = cubit.load();
    expect(cubit.state.loading, isTrue);

    service.scans[movies]!.complete([_video(movies, 'New.mkv')]);
    await pumpEventQueue();
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.videos.map((v) => v.name), ['New.mkv']);

    service.scans[shows]!.complete([]);
    await loading;
  });
}
