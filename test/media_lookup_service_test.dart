import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:playra/models/media_info.dart';
import 'package:playra/services/media_lookup_service.dart';
import 'package:playra/services/media_sidecar_service.dart';
import 'package:playra/services/tmdb_service.dart';
import 'package:playra/services/video_name_parser.dart';

class _FakeTmdb extends TmdbService {
  final List<String> searches = [];

  static MediaInfo movie(int id, String title) => MediaInfo(id: id, title: title, originalTitle: title, type: MediaType.movie, popularity: id.toDouble());

  @override
  Future<List<MediaInfo>> search({required String query, required String language, bool searchMovies = true, bool searchTV = true, int? year}) async {
    searches.add(query);
    if (!searchMovies) return [MediaInfo(id: 1396, title: 'Perníkový táta', originalTitle: 'Breaking Bad', type: MediaType.tv)];
    return [movie(27205, 'Počátek'), movie(5, 'Méně populární')];
  }

  @override
  Future<MediaInfo?> getMovieDetails(int movieId, String language) async => movie(movieId, 'Detail $movieId ($language)');

  @override
  Future<MediaInfo?> getTVDetails(int tvId, String language) async =>
      MediaInfo(id: tvId, title: 'Perníkový táta', originalTitle: 'Breaking Bad', type: MediaType.tv);

  @override
  Future<EpisodeInfo?> getEpisodeDetails(int tvId, int season, int episode, {String language = 'en-US'}) async =>
      EpisodeInfo(season: season, episode: episode, name: 'Díl $episode');
}

void main() {
  late Directory root;
  late _FakeTmdb tmdb;
  late MediaSidecarService sidecars;
  late MediaLookupService lookup;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('playra_lookup_test');
    tmdb = _FakeTmdb();
    sidecars = MediaSidecarService(locate: (uri) => (store: const LocalSidecarStore(), path: uri), download: (_) async => null);
    lookup = MediaLookupService(tmdb, sidecars: sidecars);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> video(String relative) async {
    final file = File(p.joinAll([root.path, ...relative.split('/')]));
    await file.create(recursive: true);
    return file.path;
  }

  // Sidecar writes after a lookup run in the background on the same queue, so
  // a read returns only once they are done.
  Future<MediaSidecar?> sidecarFor(String path) => sidecars.read(path, VideoNameParser.parse(path));

  test('an .nfo next to the video is used instead of a TMDB search', () async {
    final path = await video('Inception.2010.mkv');
    await File(p.join(root.path, 'Inception.2010.nfo')).writeAsString('<movie><title>Z jiného zařízení</title><uniqueid type="tmdb">27205</uniqueid></movie>');

    final result = await lookup.lookupForFile(path, 'cs');

    expect(tmdb.searches, isEmpty);
    expect(result!.mediaInfo.id, 27205);
    expect(result.mediaInfo.title, 'Detail 27205 (cs)');
    expect(result.fromCache, isTrue);
  });

  test('a new identification is written next to the video', () async {
    final path = await video('Inception.2010.mkv');

    final result = await lookup.lookupForFile(path, 'cs');

    expect(tmdb.searches, ['Inception']);
    expect(result!.mediaInfo.id, 27205);
    expect(result.fromCache, isFalse);
    expect((await sidecarFor(path))!.media.id, 27205);
  });

  test('a manual pick overwrites the .nfo of an automatic guess', () async {
    final path = await video('Inception.2010.mkv');
    await lookup.lookupForFile(path, 'cs');
    await sidecarFor(path);

    final written = await lookup.saveManualPick(path, _FakeTmdb.movie(5, 'Méně populární'), 'cs');

    expect(written, isTrue);
    expect((await sidecarFor(path))!.media.id, 5);
    expect((await lookup.lookupForFile(path, 'cs'))!.mediaInfo.id, 5);
  });

  test('a TV episode gets its episode info and an episode .nfo', () async {
    final path = await video('Breaking Bad/Season 1/Breaking.Bad.S01E03.mkv');

    final result = await lookup.lookupForFile(path, 'cs');

    expect(result!.mediaInfo.type, MediaType.tv);
    expect(result.episode!.name, 'Díl 3');
    final sidecar = await sidecarFor(path);
    expect(sidecar!.media.id, 1396);
    expect(sidecar.episode!.name, 'Díl 3');
    expect(await File(p.join(root.path, 'Breaking Bad', 'tvshow.nfo')).exists(), isTrue);
  });
}
