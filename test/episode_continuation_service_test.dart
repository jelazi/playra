import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:playra/models/video_item.dart';
import 'package:playra/services/episode_continuation_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async => tempDir = await Directory.systemTemp.createTemp('playra_episodes_test'));
  tearDown(() async => tempDir.delete(recursive: true));

  Future<VideoItem> makeVideo(String relativePath) async {
    final file = File(p.join(tempDir.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString('not really a video');
    return VideoItem(
      id: file.path,
      name: p.basename(file.path),
      uri: file.path,
      source: VideoSource.local,
      folder: p.basename(file.parent.path),
    );
  }

  test('finds the next episode in the same folder', () async {
    final current = await makeVideo('Severance/Severance.S01E01.1080p.mkv');
    await makeVideo('Severance/Severance.S01E02.1080p.mkv');
    await makeVideo('Severance/Severance.S01E03.1080p.mkv');

    final next = await EpisodeContinuationService.findNextEpisode(current);
    expect(next?.name, 'Severance.S01E02.1080p.mkv');
  });

  test('skips a gap in the numbering', () async {
    final current = await makeVideo('Severance/Severance.S01E01.mkv');
    await makeVideo('Severance/Severance.S01E04.mkv');

    final next = await EpisodeContinuationService.findNextEpisode(current);
    expect(next?.name, 'Severance.S01E04.mkv');
  });

  test('never goes backwards', () async {
    final current = await makeVideo('Severance/Severance.S01E05.mkv');
    await makeVideo('Severance/Severance.S01E02.mkv');

    expect(await EpisodeContinuationService.findNextEpisode(current), isNull);
  });

  test('rolls over into the next season folder', () async {
    final current = await makeVideo('Dark/Season 1/Dark.S01E10.mkv');
    await makeVideo('Dark/Season 2/Dark.S02E01.mkv');

    final next = await EpisodeContinuationService.findNextEpisode(current);
    expect(next?.name, 'Dark.S02E01.mkv');
  });

  test('prefers the next episode of the same season over the next season', () async {
    final current = await makeVideo('Dark/Season 1/Dark.S01E01.mkv');
    await makeVideo('Dark/Season 1/Dark.S01E02.mkv');
    await makeVideo('Dark/Season 2/Dark.S02E01.mkv');

    final next = await EpisodeContinuationService.findNextEpisode(current);
    expect(next?.name, 'Dark.S01E02.mkv');
  });

  test('ignores a different show sitting in the same folder', () async {
    final current = await makeVideo('Mixed/Severance.S01E01.mkv');
    await makeVideo('Mixed/Breaking.Bad.S01E02.mkv');

    expect(await EpisodeContinuationService.findNextEpisode(current), isNull);
  });

  test('matches across differing release tags', () async {
    final current = await makeVideo('Severance/Severance.S01E01.1080p.WEB-DL.x265.mkv');
    await makeVideo('Severance/Severance.S01E02.720p.BluRay.x264.mkv');

    final next = await EpisodeContinuationService.findNextEpisode(current);
    expect(next?.name, 'Severance.S01E02.720p.BluRay.x264.mkv');
  });

  test('understands the 1x02 marker', () async {
    final current = await makeVideo('Show/Show.1x01.mkv');
    await makeVideo('Show/Show.1x02.mkv');

    final next = await EpisodeContinuationService.findNextEpisode(current);
    expect(next?.name, 'Show.1x02.mkv');
  });

  test('ignores files that are not videos', () async {
    final current = await makeVideo('Severance/Severance.S01E01.mkv');
    await makeVideo('Severance/Severance.S01E02.srt');
    await makeVideo('Severance/Severance.S01E02.nfo');

    expect(await EpisodeContinuationService.findNextEpisode(current), isNull);
  });

  test('returns null for a movie with no episode marker', () async {
    final current = await makeVideo('Movies/The.Matrix.1999.mkv');
    await makeVideo('Movies/Inception.2010.mkv');

    expect(await EpisodeContinuationService.findNextEpisode(current), isNull);
  });

  test('returns null when nothing follows', () async {
    final current = await makeVideo('Severance/Severance.S01E01.mkv');
    expect(await EpisodeContinuationService.findNextEpisode(current), isNull);
  });

  test('returns null for a non-local source', () async {
    const remote = VideoItem(
      id: 'smb://nas/media/Show.S01E01.mkv',
      name: 'Show.S01E01.mkv',
      uri: 'smb://nas/media/Show.S01E01.mkv',
      source: VideoSource.smb,
    );
    expect(await EpisodeContinuationService.findNextEpisode(remote), isNull);
  });

  test('returns null when the folder is gone', () async {
    const missing = VideoItem(
      id: '/definitely/not/here/Show.S01E01.mkv',
      name: 'Show.S01E01.mkv',
      uri: '/definitely/not/here/Show.S01E01.mkv',
      source: VideoSource.local,
    );
    expect(await EpisodeContinuationService.findNextEpisode(missing), isNull);
  });
}
