import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/video_info.dart';
import '../services/settings_service.dart';

/// Service for checking subtitle file existence and managing subtitle indicators
class SubtitleFileService {
  /// Update VideoInfo with current subtitle status (both from Hive and file system)
  static VideoInfo updateVideoInfoWithSubtitles(VideoInfo videoInfo) {
    // Check Hive settings for download record
    final hasDownloadedRecord = SettingsService.hasDownloadedSubtitles(videoInfo.path);

    // Check file system for physical files
    final fileInfo = checkSubtitleFiles(videoInfo);

    return videoInfo.copyWith(hasDownloadedSubtitles: hasDownloadedRecord, hasPhysicalSubtitles: fileInfo.hasSubtitles, subtitleFiles: fileInfo.subtitleFiles);
  }

  /// Update a list of VideoInfo objects with subtitle status
  static List<VideoInfo> updateVideoListWithSubtitles(List<VideoInfo> videos) {
    return videos.map((video) => updateVideoInfoWithSubtitles(video)).toList();
  }

  /// Check if subtitle files exist physically in the video directory
  /// Returns info about which subtitle files exist
  static SubtitleFileInfo checkSubtitleFiles(VideoInfo videoInfo) {
    final videoDir = Directory(path.dirname(videoInfo.path));
    final videoBaseName = path.basenameWithoutExtension(videoInfo.path);

    if (!videoDir.existsSync()) {
      return SubtitleFileInfo(hasSubtitles: false, subtitleFiles: []);
    }

    final subtitleExtensions = ['.srt', '.sub', '.ass', '.ssa', '.vtt', '.txt'];
    final foundSubtitles = <String>[];

    try {
      final files = videoDir.listSync();

      for (final file in files) {
        if (file is File) {
          final fileName = path.basenameWithoutExtension(file.path);
          final extension = path.extension(file.path).toLowerCase();

          // Check if file has the same base name as video and subtitle extension
          if (fileName == videoBaseName && subtitleExtensions.contains(extension)) {
            foundSubtitles.add(file.path);
          }

          // Also check for files with common subtitle naming patterns
          // e.g., video_name.czech.srt, video_name.cs.srt, video_name.cz.srt
          final languagePatterns = ['czech', 'cs', 'cz', 'english', 'en'];
          for (final pattern in languagePatterns) {
            if (fileName == '$videoBaseName.$pattern' && subtitleExtensions.contains(extension)) {
              foundSubtitles.add(file.path);
            }
          }
        }
      }
    } catch (e) {
      print('Error checking subtitle files: $e');
      return SubtitleFileInfo(hasSubtitles: false, subtitleFiles: []);
    }

    return SubtitleFileInfo(hasSubtitles: foundSubtitles.isNotEmpty, subtitleFiles: foundSubtitles);
  }

  /// Get the expected subtitle file path for a video
  static String getExpectedSubtitlePath(VideoInfo videoInfo, [String extension = '.srt']) {
    final videoDir = path.dirname(videoInfo.path);
    final videoBaseName = path.basenameWithoutExtension(videoInfo.path);
    return path.join(videoDir, '$videoBaseName$extension');
  }

  /// Clean up non-existing video paths from downloaded list
  /// This can be called periodically to maintain the list
  static List<String> filterExistingVideos(List<String> videoPaths) {
    return videoPaths.where((videoPath) {
      final file = File(videoPath);
      return file.existsSync();
    }).toList();
  }
}

/// Information about subtitle files for a video
class SubtitleFileInfo {
  final bool hasSubtitles;
  final List<String> subtitleFiles;

  SubtitleFileInfo({required this.hasSubtitles, required this.subtitleFiles});

  /// Get a user-friendly description of found subtitles
  String get description {
    if (!hasSubtitles) return 'Žádné titulky';

    if (subtitleFiles.length == 1) {
      final ext = path.extension(subtitleFiles.first).replaceFirst('.', '').toUpperCase();
      return 'Titulky ($ext)';
    }

    final extensions = subtitleFiles.map((file) => path.extension(file).replaceFirst('.', '').toUpperCase()).toSet().join(', ');
    return 'Titulky (${subtitleFiles.length}x: $extensions)';
  }
}
