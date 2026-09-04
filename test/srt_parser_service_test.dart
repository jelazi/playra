import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playra/models/subtitle_entry.dart';
import 'package:playra/services/srt_parser_service.dart';

const _sampleSrt = '''
1
00:00:01,000 --> 00:00:03,000
First line

2
00:00:05,500 --> 00:00:07,250
Second line
split over two rows

3
00:01:00,000 --> 00:01:02,000
Third line
''';

void main() {
  group('parse', () {
    test('reads index, timings and text', () {
      final entries = SrtParserService.parse(_sampleSrt);

      expect(entries, hasLength(3));
      expect(entries[0].index, 1);
      expect(entries[0].startTime, const Duration(seconds: 1));
      expect(entries[0].endTime, const Duration(seconds: 3));
      expect(entries[0].text, 'First line');
    });

    test('keeps multi-row cue text as one entry', () {
      final entries = SrtParserService.parse(_sampleSrt);
      expect(entries[1].text, 'Second line\nsplit over two rows');
      expect(entries[1].startTime, const Duration(seconds: 5, milliseconds: 500));
    });

    test('handles CRLF line endings', () {
      final entries = SrtParserService.parse(_sampleSrt.replaceAll('\n', '\r\n'));
      expect(entries, hasLength(3));
      expect(entries[0].text, 'First line');
    });

    test('accepts a dot as the millisecond separator', () {
      final entries = SrtParserService.parse('1\n00:00:01.500 --> 00:00:02.750\nText\n');
      expect(entries.single.startTime, const Duration(seconds: 1, milliseconds: 500));
      expect(entries.single.endTime, const Duration(seconds: 2, milliseconds: 750));
    });

    test('skips malformed blocks instead of throwing', () {
      const broken = '''
1
not a timestamp
Text

2
00:00:05,000 --> 00:00:06,000
Good one
''';
      final entries = SrtParserService.parse(broken);
      expect(entries, hasLength(1));
      expect(entries.single.text, 'Good one');
    });

    test('returns nothing for empty content', () {
      expect(SrtParserService.parse(''), isEmpty);
    });
  });

  group('formatDuration', () {
    test('pads every field', () {
      expect(SrtParserService.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 456)), '01:02:03,456');
    });

    test('formats zero', () {
      expect(SrtParserService.formatDuration(Duration.zero), '00:00:00,000');
    });

    test('keeps hours past 24 rather than wrapping', () {
      expect(SrtParserService.formatDuration(const Duration(hours: 25, minutes: 1)), '25:01:00,000');
    });
  });

  group('toSrt', () {
    test('round-trips content back through parse', () {
      final original = SrtParserService.parse(_sampleSrt);
      final reparsed = SrtParserService.parse(SrtParserService.toSrt(original));

      expect(reparsed, hasLength(original.length));
      for (var i = 0; i < original.length; i++) {
        expect(reparsed[i].startTime, original[i].startTime);
        expect(reparsed[i].endTime, original[i].endTime);
        expect(reparsed[i].text, original[i].text);
      }
    });

    test('renumbers entries from one', () {
      const entries = [
        SubtitleEntry(index: 7, startTime: Duration(seconds: 1), endTime: Duration(seconds: 2), text: 'a'),
        SubtitleEntry(index: 9, startTime: Duration(seconds: 3), endTime: Duration(seconds: 4), text: 'b'),
      ];
      final parsed = SrtParserService.parse(SrtParserService.toSrt(entries));
      expect(parsed.map((e) => e.index), [1, 2]);
    });
  });

  group('applyGlobalShift', () {
    test('moves every entry forward', () {
      final shifted = SrtParserService.applyGlobalShift(SrtParserService.parse(_sampleSrt), const Duration(seconds: 2));
      expect(shifted[0].startTime, const Duration(seconds: 3));
      expect(shifted[0].endTime, const Duration(seconds: 5));
      expect(shifted[2].startTime, const Duration(minutes: 1, seconds: 2));
    });

    test('clamps at zero rather than going negative', () {
      final shifted = SrtParserService.applyGlobalShift(SrtParserService.parse(_sampleSrt), const Duration(seconds: -10));
      expect(shifted[0].startTime, Duration.zero);
      expect(shifted[0].endTime, Duration.zero);
      expect(shifted[2].startTime, const Duration(seconds: 50));
    });

    test('leaves the text untouched', () {
      final shifted = SrtParserService.applyGlobalShift(SrtParserService.parse(_sampleSrt), const Duration(seconds: 2));
      expect(shifted.map((e) => e.text), SrtParserService.parse(_sampleSrt).map((e) => e.text));
    });
  });

  group('applyKeyBasedSync', () {
    List<SubtitleEntry> fiveEntries() => List.generate(
          5,
          (i) => SubtitleEntry(index: i + 1, startTime: Duration(seconds: i * 10), endTime: Duration(seconds: i * 10 + 2), text: 'line ${i + 1}'),
        );

    test('applies a single key point to everything', () {
      final result = SrtParserService.applyKeyBasedSync(fiveEntries(), {3: const Duration(seconds: 5)});
      expect(result.map((e) => e.startTime.inSeconds), [5, 15, 25, 35, 45]);
    });

    test('interpolates linearly between two key points', () {
      // First entry +1s, last entry +5s: the middle entry lands halfway, at +3s.
      final result = SrtParserService.applyKeyBasedSync(
        fiveEntries(),
        {1: const Duration(seconds: 1), 5: const Duration(seconds: 5)},
      );
      expect(result[0].startTime, const Duration(seconds: 1));
      expect(result[2].startTime, const Duration(seconds: 20 + 3));
      expect(result[4].startTime, const Duration(seconds: 40 + 5));
    });

    test('holds the outer key offsets beyond the key range', () {
      final result = SrtParserService.applyKeyBasedSync(
        fiveEntries(),
        {2: const Duration(seconds: 2), 4: const Duration(seconds: 4)},
      );
      expect(result[0].startTime, const Duration(seconds: 2));
      expect(result[4].startTime, const Duration(seconds: 44));
    });

    test('returns the entries unchanged when there are no key points', () {
      final entries = fiveEntries();
      expect(SrtParserService.applyKeyBasedSync(entries, {}), entries);
    });

    test('ignores key points that match no entry', () {
      final entries = fiveEntries();
      expect(SrtParserService.applyKeyBasedSync(entries, {99: const Duration(seconds: 5)}), entries);
    });
  });

  group('file IO', () {
    late Directory tempDir;

    setUp(() async => tempDir = await Directory.systemTemp.createTemp('playra_srt_test'));
    tearDown(() async => tempDir.delete(recursive: true));

    test('writes and reads a file back', () async {
      final path = '${tempDir.path}/sub.srt';
      final entries = SrtParserService.parse(_sampleSrt);

      await SrtParserService.writeFile(path, entries);
      final loaded = await SrtParserService.parseFile(path);

      expect(loaded.map((e) => e.text), entries.map((e) => e.text));
      expect(loaded.first.startTime, entries.first.startTime);
    });

    test('throws for a missing file', () {
      expect(SrtParserService.parseFile('${tempDir.path}/nope.srt'), throwsA(isA<Exception>()));
    });
  });
}
