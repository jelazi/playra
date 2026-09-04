import 'package:flutter_test/flutter_test.dart';
import 'package:playra/services/video_name_parser.dart';

void main() {
  group('the recognised-formats table from README.md', () {
    // Each row here is one row of that table. If a row changes, the README is wrong.
    const rows = {
      'The.Matrix.1999.1080p.BluRay.x264.mkv': 'The Matrix (1999)',
      'Inception 2010 720p.mp4': 'Inception (2010)',
      'Avatar-2009-IMAX.avi': 'Avatar (2009)',
      'True.Detective.S01E02.720p.BluRay.mkv': 'True Detective S01E02',
      'Game of Thrones - S08E06 - 4K.mkv': 'Game of Thrones S08E06',
    };

    rows.forEach((fileName, expected) {
      test('$fileName resolves as $expected', () {
        expect(VideoNameParser.parse(fileName).toString(), expected);
      });
    });
  });

  group('movies', () {
    test('pulls the title and year apart', () {
      final parsed = VideoNameParser.parse('The.Matrix.1999.1080p.BluRay.x264.mkv');
      expect(parsed.cleanName, 'The Matrix');
      expect(parsed.year, 1999);
      expect(parsed.isTV, isFalse);
      expect(parsed.season, isNull);
      expect(parsed.episode, isNull);
    });

    test('strips a long chain of release tokens', () {
      final parsed = VideoNameParser.parse('Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.HDR.x265.mkv');
      expect(parsed.cleanName, 'Dune Part Two');
      expect(parsed.year, 2024);
    });

    test('keeps a word that merely starts with a release token', () {
      expect(VideoNameParser.parse('Imaximus.2020.mkv').cleanName, 'Imaximus');
    });

    test('drops bracketed and parenthesised sections', () {
      expect(VideoNameParser.parse('Arrival [2016] (Director Cut).mkv').cleanName, 'Arrival');
    });

    test('reports no year when the name carries none', () {
      final parsed = VideoNameParser.parse('SomeMovie.1080p.mkv');
      expect(parsed.cleanName, 'SomeMovie');
      expect(parsed.year, isNull);
    });
  });

  group('TV episodes', () {
    test('reads the SxxExx marker', () {
      final parsed = VideoNameParser.parse('True.Detective.S01E02.720p.BluRay.mkv');
      expect(parsed.isTV, isTrue);
      expect(parsed.season, 1);
      expect(parsed.episode, 2);
      expect(parsed.cleanName, 'True Detective');
    });

    test('reads the 2x05 marker', () {
      final parsed = VideoNameParser.parse('/media/Breaking Bad/S02/Breaking.Bad.2x05.720p.mkv');
      expect(parsed.season, 2);
      expect(parsed.episode, 5);
      expect(parsed.cleanName, 'Breaking Bad');
    });

    test('is case-insensitive about the marker', () {
      final parsed = VideoNameParser.parse('show.s03e07.mkv');
      expect(parsed.season, 3);
      expect(parsed.episode, 7);
    });

    test('takes the show name from the folder above a season folder', () {
      final parsed = VideoNameParser.parse('/media/True Detective/Season 1/episode.s01e03.mkv');
      expect(parsed.cleanName, 'True Detective');
      expect(parsed.season, 1);
      expect(parsed.episode, 3);
    });

    test('skips a generic folder name when walking up', () {
      final parsed = VideoNameParser.parse('/downloads/Severance/S01/ep.s01e04.mkv');
      expect(parsed.cleanName, 'Severance');
    });

    test('falls back to a season/episode marker on the folder', () {
      final parsed = VideoNameParser.parse('/media/Dark/S02E06/video.mkv');
      expect(parsed.isTV, isTrue);
      expect(parsed.season, 2);
      expect(parsed.episode, 6);
    });
  });

  test('keeps the original file name for display', () {
    final parsed = VideoNameParser.parse('/media/x/The.Matrix.1999.mkv');
    expect(parsed.originalFileName, 'The.Matrix.1999');
  });
}
