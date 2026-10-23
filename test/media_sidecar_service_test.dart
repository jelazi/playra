import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:playra/models/media_info.dart';
import 'package:playra/services/media_sidecar_service.dart';
import 'package:playra/services/video_name_parser.dart';

MediaInfo _movie() => MediaInfo(
  id: 27205,
  title: 'Počátek',
  originalTitle: 'Inception',
  overview: 'Sny ve snech.',
  posterPath: '/poster.jpg',
  backdropPath: '/backdrop.jpg',
  releaseDate: '2010-07-15',
  voteAverage: 8.4,
  genres: const ['Akční', 'Sci-Fi'],
  type: MediaType.movie,
);

MediaInfo _show({int id = 1396, String title = 'Perníkový táta'}) => MediaInfo(
  id: id,
  title: title,
  originalTitle: 'Breaking Bad',
  overview: 'Učitel chemie.',
  posterPath: '/show.jpg',
  releaseDate: '2008-01-20',
  type: MediaType.tv,
  numberOfSeasons: 5,
  firstAirDate: '2008-01-20',
);

const _episode = EpisodeInfo(season: 1, episode: 2, name: 'Kočka v pytli', overview: 'Walt a Jesse uklízejí.', voteAverage: 8.1, airDate: '2008-01-27');

void main() {
  late Directory root;
  late MediaSidecarService service;
  late List<String> downloads;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('playra_sidecar_test');
    downloads = [];
    service = MediaSidecarService(
      locate: (uri) => (store: const LocalSidecarStore(), path: uri),
      download: (url) async {
        downloads.add(url);
        return [0xFF, 0xD8, 0xFF];
      },
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> video(String relative) async {
    final file = File(p.joinAll([root.path, ...relative.split('/')]));
    await file.create(recursive: true);
    return file.path;
  }

  group('movie', () {
    test('writes <video>.nfo and <video>-poster.jpg and reads them back', () async {
      final path = await video('Filmy/Inception.2010.1080p.mkv');
      final parsed = VideoNameParser.parse(path);

      expect(await service.write(path, parsed, _movie()), isTrue);

      final nfo = File(p.join(root.path, 'Filmy', 'Inception.2010.1080p.nfo'));
      expect(await nfo.exists(), isTrue);
      final xml = await nfo.readAsString();
      expect(xml, contains('<movie>'));
      expect(xml, contains('<uniqueid type="tmdb" default="true">27205</uniqueid>'));
      expect(xml, contains('<title>Počátek</title>'));
      expect(await File(p.join(root.path, 'Filmy', 'Inception.2010.1080p-poster.jpg')).exists(), isTrue);
      expect(downloads.single, 'https://image.tmdb.org/t/p/w780/poster.jpg');

      final read = await service.read(path, parsed);
      expect(read!.media.id, 27205);
      expect(read.media.type, MediaType.movie);
      expect(read.media.title, 'Počátek');
      expect(read.media.originalTitle, 'Inception');
      expect(read.media.posterPath, '/poster.jpg');
      expect(read.media.backdropPath, '/backdrop.jpg');
      expect(read.media.voteAverage, 8.4);
      expect(read.media.genres, ['Akční', 'Sci-Fi']);
      expect(read.episode, isNull);
    });

    test('keeps existing files unless asked to overwrite', () async {
      final path = await video('Inception.mkv');
      final parsed = VideoNameParser.parse(path);
      final nfo = File(p.join(root.path, 'Inception.nfo'));
      await nfo.writeAsString('<movie><title>Ručně</title><uniqueid type="tmdb">1</uniqueid></movie>');

      await service.write(path, parsed, _movie());
      expect(await nfo.readAsString(), contains('Ručně'));

      await service.write(path, parsed, _movie(), overwrite: true);
      expect(await nfo.readAsString(), contains('Počátek'));
    });

    test('reads a Kodi movie.nfo with <tmdbid> and a trailing scraper URL', () async {
      final path = await video('Inception (2010)/Inception.mkv');
      await File(p.join(root.path, 'Inception (2010)', 'movie.nfo')).writeAsString(
        '<?xml version="1.0"?>\n<movie><title>Inception</title><tmdbid>27205</tmdbid><year>2010</year></movie>\nhttps://www.themoviedb.org/movie/27205\n',
      );

      final read = await service.read(path, VideoNameParser.parse(path));
      expect(read!.media.id, 27205);
      expect(read.media.releaseDate, '2010');
    });

    test('ignores an .nfo without a TMDB id', () async {
      final path = await video('Inception.mkv');
      await File(p.join(root.path, 'Inception.nfo')).writeAsString('<movie><title>Inception</title><uniqueid type="imdb">tt1375666</uniqueid></movie>');

      expect(await service.read(path, VideoNameParser.parse(path)), isNull);
    });
  });

  group('series', () {
    test('puts tvshow.nfo above a season folder and an episode .nfo next to the video', () async {
      final path = await video('Serialy/Breaking Bad/Season 1/Breaking.Bad.S01E02.mkv');
      final parsed = VideoNameParser.parse(path);

      await service.write(path, parsed, _show(), episode: _episode);

      final showDir = p.join(root.path, 'Serialy', 'Breaking Bad');
      expect(await File(p.join(showDir, 'tvshow.nfo')).readAsString(), contains('<tvshow>'));
      expect(await File(p.join(showDir, 'poster.jpg')).exists(), isTrue);
      final episodeXml = await File(p.join(showDir, 'Season 1', 'Breaking.Bad.S01E02.nfo')).readAsString();
      expect(episodeXml, contains('<episodedetails>'));
      expect(episodeXml, contains('<title>Kočka v pytli</title>'));
      expect(episodeXml, contains('<showtitle>Perníkový táta</showtitle>'));
      expect(episodeXml, contains('<season>1</season>'));
      expect(episodeXml, contains('<episode>2</episode>'));

      final read = await service.read(path, parsed);
      expect(read!.media.id, 1396);
      expect(read.media.type, MediaType.tv);
      expect(read.episode!.name, 'Kočka v pytli');
      expect(read.episode!.overview, 'Walt a Jesse uklízejí.');
      expect(read.episode!.voteAverage, 8.1);
    });

    test('keeps tvshow.nfo in a lone season folder that has no show folder above it', () async {
      final path = await video('Serialy/Breaking.Bad.S01.1080p/Breaking.Bad.S01E02.mkv');
      final parsed = VideoNameParser.parse(path);

      await service.write(path, parsed, _show(), episode: _episode);

      expect(await File(p.join(root.path, 'Serialy', 'Breaking.Bad.S01.1080p', 'tvshow.nfo')).exists(), isTrue);
      expect(await File(p.join(root.path, 'Serialy', 'tvshow.nfo')).exists(), isFalse);
      expect((await service.read(path, parsed))!.media.id, 1396);
    });

    test('uses the show folder above a release-named season folder', () async {
      final path = await video('Breaking Bad (2008)/Breaking.Bad.S02.720p/Breaking.Bad.S02E01.mkv');

      await service.write(path, VideoNameParser.parse(path), _show());

      expect(await File(p.join(root.path, 'Breaking Bad (2008)', 'tvshow.nfo')).exists(), isTrue);
    });

    test('replaces an episode .nfo left from a different show but keeps one for the same show', () async {
      final path = await video('Breaking Bad/Breaking.Bad.S01E02.mkv');
      final parsed = VideoNameParser.parse(path);
      final episodeNfo = File(p.join(root.path, 'Breaking Bad', 'Breaking.Bad.S01E02.nfo'));

      await episodeNfo.writeAsString('<episodedetails><title>Jiný seriál</title><showtitle>Something Else</showtitle></episodedetails>');
      await service.write(path, parsed, _show(), episode: _episode);
      expect(await episodeNfo.readAsString(), contains('Kočka v pytli'));

      await episodeNfo.writeAsString('<episodedetails><title>Ručně</title><showtitle>Breaking Bad</showtitle></episodedetails>');
      await service.write(path, parsed, _show(), episode: _episode);
      expect(await episodeNfo.readAsString(), contains('Ručně'));
    });
  });

  group('seriesFolder', () {
    String folder(String videoPath) => MediaSidecarService.seriesFolder(p.posix, videoPath, const ['Breaking Bad']);

    test('treats plain season folders as part of the show', () {
      expect(folder('/share/Breaking Bad/Season 2/x.mkv'), '/share/Breaking Bad');
      expect(folder('/share/Breaking Bad/S02/x.mkv'), '/share/Breaking Bad');
      expect(folder('/share/Breaking Bad/2. série/x.mkv'), '/share/Breaking Bad');
      expect(folder('/share/Breaking Bad/Série 2/x.mkv'), '/share/Breaking Bad');
    });

    test('keeps the video folder when it is the show folder or a lone season', () {
      expect(folder('/share/Breaking Bad/x.mkv'), '/share/Breaking Bad');
      expect(folder('/share/Serialy/Breaking.Bad.S01.1080p/x.mkv'), '/share/Serialy/Breaking.Bad.S01.1080p');
      expect(folder('/share/Serialy/2008/x.mkv'), '/share/Serialy/2008');
    });

    test('never climbs to the share root', () {
      expect(folder('/Season 1/x.mkv'), '/Season 1');
    });
  });
}
