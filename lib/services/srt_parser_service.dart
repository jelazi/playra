import 'dart:io';

import '../models/subtitle_entry.dart';

/// Service for parsing and writing SRT subtitle files.
class SrtParserService {
  /// Parses an SRT file from the given path and returns a list of [SubtitleEntry].
  static Future<List<SubtitleEntry>> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Subtitle file not found: $filePath');
    }
    final content = await file.readAsString();
    return parse(content);
  }

  /// Parses SRT content string and returns a list of [SubtitleEntry].
  static List<SubtitleEntry> parse(String content) {
    final entries = <SubtitleEntry>[];
    // Normalize line endings
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // Split into blocks separated by empty lines
    final blocks = normalized.split(RegExp(r'\n\n+'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;

      // First line: index number
      final index = int.tryParse(lines[0].trim());
      if (index == null) continue;

      // Second line: time range
      final timeParts = lines[1].trim().split(' --> ');
      if (timeParts.length != 2) continue;

      final startTime = _parseDuration(timeParts[0].trim());
      final endTime = _parseDuration(timeParts[1].trim());
      if (startTime == null || endTime == null) continue;

      // Remaining lines: subtitle text
      final text = lines.sublist(2).join('\n').trim();
      if (text.isEmpty) continue;

      entries.add(SubtitleEntry(index: index, startTime: startTime, endTime: endTime, text: text));
    }

    return entries;
  }

  /// Parses an SRT duration string like "01:02:03,456" into a [Duration].
  static Duration? _parseDuration(String timeStr) {
    // Format: HH:MM:SS,mmm or HH:MM:SS.mmm
    final regex = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})');
    final match = regex.firstMatch(timeStr);
    if (match == null) return null;

    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final millis = int.parse(match.group(4)!);

    return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: millis);
  }

  /// Formats a [Duration] to SRT time string format "HH:MM:SS,mmm".
  static String formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds,$millis';
  }

  /// Converts a list of [SubtitleEntry] back to SRT file format string.
  static String toSrt(List<SubtitleEntry> entries) {
    final buffer = StringBuffer();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      buffer.writeln(i + 1);
      buffer.writeln('${formatDuration(entry.startTime)} --> ${formatDuration(entry.endTime)}');
      buffer.writeln(entry.text);
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Writes subtitle entries to an SRT file.
  static Future<void> writeFile(String filePath, List<SubtitleEntry> entries) async {
    final file = File(filePath);
    await file.writeAsString(toSrt(entries));
  }

  /// Applies a global time shift to all entries.
  static List<SubtitleEntry> applyGlobalShift(List<SubtitleEntry> entries, Duration offset) {
    return entries.map((e) => e.shifted(offset)).toList();
  }

  /// Applies key-based interpolation to subtitle entries.
  ///
  /// [entries] - All subtitle entries
  /// [keyPoints] - Map of entry index to the offset that should be applied at that point.
  ///               The key is the original entry index, the value is the time offset.
  ///
  /// Subtitles between key points are linearly interpolated.
  /// Subtitles before the first key point use the first key's offset ratio.
  /// Subtitles after the last key point use the last key's offset ratio.
  static List<SubtitleEntry> applyKeyBasedSync(List<SubtitleEntry> entries, Map<int, Duration> keyPoints) {
    if (entries.isEmpty || keyPoints.isEmpty) return entries;

    // Sort key point indices
    final sortedKeys = keyPoints.keys.toList()..sort();

    // Find entry indices in the list (entries are 1-indexed in SRT)
    // Create a mapping from entry list index to entry
    final result = List<SubtitleEntry>.from(entries);

    // Convert keyPoints to use list indices instead of SRT indices
    // Find list index for each key entry
    final keyListIndices = <int, Duration>{};
    for (final srtIndex in sortedKeys) {
      final listIndex = entries.indexWhere((e) => e.index == srtIndex);
      if (listIndex != -1) {
        keyListIndices[listIndex] = keyPoints[srtIndex]!;
      }
    }

    if (keyListIndices.isEmpty) return entries;

    final sortedListKeys = keyListIndices.keys.toList()..sort();

    for (int i = 0; i < entries.length; i++) {
      Duration offset;

      if (sortedListKeys.length == 1) {
        // Only one key point - apply the same offset to all
        offset = keyListIndices[sortedListKeys.first]!;
      } else if (i <= sortedListKeys.first) {
        // Before or at first key point - use first key's offset
        offset = keyListIndices[sortedListKeys.first]!;
      } else if (i >= sortedListKeys.last) {
        // After or at last key point - use last key's offset
        offset = keyListIndices[sortedListKeys.last]!;
      } else {
        // Between two key points - linear interpolation
        int prevKey = sortedListKeys.first;
        int nextKey = sortedListKeys.last;

        for (int k = 0; k < sortedListKeys.length - 1; k++) {
          if (i >= sortedListKeys[k] && i <= sortedListKeys[k + 1]) {
            prevKey = sortedListKeys[k];
            nextKey = sortedListKeys[k + 1];
            break;
          }
        }

        final prevOffset = keyListIndices[prevKey]!;
        final nextOffset = keyListIndices[nextKey]!;

        // Linear interpolation between the two key points
        final totalRange = nextKey - prevKey;
        final position = i - prevKey;
        final ratio = position / totalRange;

        final offsetMs = prevOffset.inMilliseconds + ((nextOffset.inMilliseconds - prevOffset.inMilliseconds) * ratio).round();
        offset = Duration(milliseconds: offsetMs);
      }

      result[i] = entries[i].shifted(offset);
    }

    return result;
  }
}
