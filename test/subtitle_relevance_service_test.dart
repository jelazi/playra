import 'package:flutter_test/flutter_test.dart';
import 'package:playra/models/subtitle.dart';
import 'package:playra/services/subtitle_relevance_service.dart';
import 'package:playra/services/video_name_parser.dart';

Subtitle _sub(String title, {String? id}) => Subtitle(id: id ?? title, title: title, language: 'cs', format: 'srt', downloadUrl: 'https://example.test/$title');

void main() {
  group('parseSeasonEpisode', () {
    test('reads S05E01', () {
      final info = SubtitleRelevanceService.parseSeasonEpisode('Show S05E01 CZ')!;
      expect(info.season, 5);
      expect(info.episode, 1);
    });

    test('reads 5x01', () {
      final info = SubtitleRelevanceService.parseSeasonEpisode('Show 5x01')!;
      expect(info.season, 5);
      expect(info.episode, 1);
    });

    test('reads "Season 5 Episode 1"', () {
      final info = SubtitleRelevanceService.parseSeasonEpisode('Show Season 5 Episode 1')!;
      expect(info.season, 5);
      expect(info.episode, 1);
    });

    test('reads a spaced S5 E01', () {
      final info = SubtitleRelevanceService.parseSeasonEpisode('Show S5 E01')!;
      expect(info.season, 5);
      expect(info.episode, 1);
    });

    test('returns null when there is no marker', () {
      expect(SubtitleRelevanceService.parseSeasonEpisode('Just A Movie 2019'), isNull);
    });

    test('formats itself back as SxxExx', () {
      expect(SubtitleRelevanceService.parseSeasonEpisode('Show 5x01').toString(), 'S05E01');
    });
  });

  group('calculateRelevance for a TV episode', () {
    final video = VideoNameParser.parse('True.Detective.S01E02.720p.mkv');

    test('scores the exact episode highest', () {
      expect(SubtitleRelevanceService.calculateRelevance(_sub('True Detective S01E02'), video), 100);
    });

    test('scores the same season, different episode below the exact match', () {
      expect(SubtitleRelevanceService.calculateRelevance(_sub('True Detective S01E05'), video), 70);
    });

    test('scores a different season lower still', () {
      expect(SubtitleRelevanceService.calculateRelevance(_sub('True Detective S02E02'), video), 50);
    });

    test('scores a title-only match on the show name', () {
      expect(SubtitleRelevanceService.calculateRelevance(_sub('True Detective'), video), 40);
    });

    test('gives no title credit to an unrelated show with the right episode', () {
      expect(SubtitleRelevanceService.calculateRelevance(_sub('Unrelated Show S01E02'), video), 60);
    });

    test('scores a completely unrelated subtitle at zero', () {
      expect(SubtitleRelevanceService.calculateRelevance(_sub('Something Entirely Different'), video), 0);
    });
  });

  group('calculateRelevance for a movie', () {
    test('rewards a matching year', () {
      final video = VideoNameParser.parse('The.Matrix.1999.1080p.mkv');
      expect(SubtitleRelevanceService.calculateRelevance(_sub('The Matrix 1999'), video), 80);
      expect(SubtitleRelevanceService.calculateRelevance(_sub('The Matrix'), video), 40);
    });

    test('awards a flat bonus when the video name carries no year', () {
      final video = VideoNameParser.parse('SomeMovie.1080p.mkv');
      expect(SubtitleRelevanceService.calculateRelevance(_sub('SomeMovie'), video), 60);
    });

    test('never exceeds 100', () {
      final video = VideoNameParser.parse('The.Matrix.1999.mkv');
      expect(SubtitleRelevanceService.calculateRelevance(_sub('The Matrix 1999 Remastered'), video), lessThanOrEqualTo(100));
    });
  });

  group('sortByRelevance', () {
    final video = VideoNameParser.parse('True.Detective.S01E02.720p.mkv');

    test('orders by score, highest first', () {
      final sorted = SubtitleRelevanceService.sortByRelevance([_sub('True Detective'), _sub('True Detective S01E02'), _sub('True Detective S02E02')], video);
      expect(sorted.allSorted.map((s) => s.title), ['True Detective S01E02', 'True Detective S02E02', 'True Detective']);
    });

    test('splits at a score of 70', () {
      final sorted = SubtitleRelevanceService.sortByRelevance([
        _sub('True Detective S01E02'), // 100
        _sub('True Detective S01E05'), // 70 - the boundary counts as relevant
        _sub('True Detective S02E02'), // 50
      ], video);
      expect(sorted.relevant.map((s) => s.title), ['True Detective S01E02', 'True Detective S01E05']);
      expect(sorted.others.map((s) => s.title), ['True Detective S02E02']);
      expect(sorted.relevantCount, 2);
      expect(sorted.othersCount, 1);
      expect(sorted.hasOthers, isTrue);
    });

    test('reports no others when everything is relevant', () {
      final sorted = SubtitleRelevanceService.sortByRelevance([_sub('True Detective S01E02')], video);
      expect(sorted.hasOthers, isFalse);
      expect(sorted.others, isEmpty);
    });

    test('keeps every input in allSorted', () {
      final input = [_sub('True Detective S01E02'), _sub('Nothing Alike'), _sub('True Detective')];
      final sorted = SubtitleRelevanceService.sortByRelevance(input, video);
      expect(sorted.allSorted, hasLength(input.length));
      expect(sorted.relevant.length + sorted.others.length, input.length);
    });

    test('handles an empty list', () {
      final sorted = SubtitleRelevanceService.sortByRelevance([], video);
      expect(sorted.allSorted, isEmpty);
      expect(sorted.relevant, isEmpty);
      expect(sorted.others, isEmpty);
    });
  });
}
