import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:playra/models/video_info.dart';
import 'package:playra/services/subtitle_file_service.dart';

void main() {
  late Directory dir;

  VideoInfo video(String fileName) {
    final path = p.join(dir.path, fileName);
    return VideoInfo(path: path, name: fileName, directory: dir.path);
  }

  File touch(String fileName) => File(p.join(dir.path, fileName))..writeAsStringSync('');

  setUp(() {
    dir = Directory.systemTemp.createTempSync('playra_subtitle_files');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('checkSubtitleFiles', () {
    test('finds a subtitle sharing the video base name', () {
      touch('movie.mp4');
      touch('movie.srt');

      final info = SubtitleFileService.checkSubtitleFiles(video('movie.mp4'));

      expect(info.hasSubtitles, isTrue);
      expect(info.subtitleFiles.single, endsWith('movie.srt'));
    });

    test('reports no subtitles for a bare video file', () {
      touch('movie.mp4');

      final info = SubtitleFileService.checkSubtitleFiles(video('movie.mp4'));

      expect(info.hasSubtitles, isFalse);
      expect(info.subtitleFiles, isEmpty);
    });

    test('accepts every supported subtitle extension', () {
      touch('movie.mp4');
      for (final ext in ['srt', 'sub', 'ass', 'ssa', 'vtt', 'txt']) {
        touch('movie.$ext');
      }

      final info = SubtitleFileService.checkSubtitleFiles(video('movie.mp4'));

      expect(info.subtitleFiles, hasLength(6));
    });

    test('picks up language-suffixed variants', () {
      touch('movie.mp4');
      touch('movie.cs.srt');
      touch('movie.english.srt');

      final info = SubtitleFileService.checkSubtitleFiles(video('movie.mp4'));

      expect(info.subtitleFiles, hasLength(2));
    });

    test('ignores subtitles belonging to a different video', () {
      touch('movie.mp4');
      touch('other_movie.srt');

      final info = SubtitleFileService.checkSubtitleFiles(video('movie.mp4'));

      expect(info.hasSubtitles, isFalse);
    });

    test('ignores an unsupported extension next to the video', () {
      touch('movie.mp4');
      touch('movie.pdf');

      final info = SubtitleFileService.checkSubtitleFiles(video('movie.mp4'));

      expect(info.hasSubtitles, isFalse);
    });

    test('returns empty rather than throwing when the directory is gone', () {
      final missing = VideoInfo(path: p.join(dir.path, 'nowhere', 'movie.mp4'), name: 'movie.mp4', directory: p.join(dir.path, 'nowhere'));

      final info = SubtitleFileService.checkSubtitleFiles(missing);

      expect(info.hasSubtitles, isFalse);
      expect(info.subtitleFiles, isEmpty);
    });
  });

  group('getExpectedSubtitlePath', () {
    test('swaps the video extension for .srt by default', () {
      final path = SubtitleFileService.getExpectedSubtitlePath(video('movie.mkv'));

      expect(path, p.join(dir.path, 'movie.srt'));
    });

    test('honours an explicit extension', () {
      final path = SubtitleFileService.getExpectedSubtitlePath(video('movie.mkv'), '.ass');

      expect(path, p.join(dir.path, 'movie.ass'));
    });

    test('keeps dots that are part of the file name', () {
      final path = SubtitleFileService.getExpectedSubtitlePath(video('The.Movie.2024.mkv'));

      expect(path, p.join(dir.path, 'The.Movie.2024.srt'));
    });
  });

  group('filterExistingVideos', () {
    test('drops paths that no longer exist', () {
      final present = touch('present.mp4').path;
      final gone = p.join(dir.path, 'gone.mp4');

      final kept = SubtitleFileService.filterExistingVideos([present, gone]);

      expect(kept, [present]);
    });

    test('returns an empty list unchanged', () {
      expect(SubtitleFileService.filterExistingVideos([]), isEmpty);
    });
  });
}
