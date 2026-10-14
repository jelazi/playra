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
  /// Subtitles between key points are linearly interpolated by their original
  /// start time, so a drift that grows with playback time is corrected evenly.
  /// Subtitles before the first key point use the first key's offset.
  /// Subtitles after the last key point use the last key's offset.
  static List<SubtitleEntry> applyKeyBasedSync(List<SubtitleEntry> entries, Map<int, Duration> keyPoints) {
    if (entries.isEmpty || keyPoints.isEmpty) return entries;

    final keys = <({Duration at, Duration offset})>[];
    for (final entry in entries) {
      final offset = keyPoints[entry.index];
      if (offset != null) keys.add((at: entry.startTime, offset: offset));
    }
    if (keys.isEmpty) return entries;
    keys.sort((a, b) => a.at.compareTo(b.at));

    return entries.map((entry) => entry.shifted(_offsetAt(entry.startTime, keys))).toList();
  }

  static Duration _offsetAt(Duration time, List<({Duration at, Duration offset})> keys) {
    if (time <= keys.first.at) return keys.first.offset;
    if (time >= keys.last.at) return keys.last.offset;

    for (int k = 0; k < keys.length - 1; k++) {
      final prev = keys[k];
      final next = keys[k + 1];
      if (time > next.at) continue;

      final span = (next.at - prev.at).inMilliseconds;
      if (span == 0) return prev.offset;
      final ratio = (time - prev.at).inMilliseconds / span;
      final offsetMs = prev.offset.inMilliseconds + ((next.offset.inMilliseconds - prev.offset.inMilliseconds) * ratio).round();
      return Duration(milliseconds: offsetMs);
    }
    return keys.last.offset;
  }
}
