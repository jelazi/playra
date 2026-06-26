import '../models/subtitle_entry.dart';

/// Tolerant subtitle parser supporting SRT, WebVTT and ASS/SSA, all converted to
/// [SubtitleEntry] cues for the styled overlay.
class SubtitleParser {
  /// Parses subtitle [content]. [name] (optional file name) helps format detection.
  static List<SubtitleEntry> parse(String content, {String? name}) {
    final lower = (name ?? '').toLowerCase();
    final looksAss = lower.endsWith('.ass') || lower.endsWith('.ssa') || content.contains('[Script Info]') || content.contains('[Events]') || content.contains('Dialogue:');
    if (looksAss) {
      final ass = _parseAss(content);
      if (ass.isNotEmpty) return ass;
    }
    return _parseSrtVtt(content);
  }

  /// Parses SRT and WebVTT (they share the cue/timecode shape). Indices are
  /// optional, and both `,` and `.` millisecond separators are accepted.
  static List<SubtitleEntry> _parseSrtVtt(String content) {
    final entries = <SubtitleEntry>[];
    var normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // Drop a leading WEBVTT header line/block if present.
    if (normalized.trimLeft().startsWith('WEBVTT')) {
      final firstBlank = normalized.indexOf('\n\n');
      if (firstBlank >= 0) normalized = normalized.substring(firstBlank + 2);
    }

    final blocks = normalized.split(RegExp(r'\n\n+'));
    var index = 0;
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.isEmpty) continue;

      // Find the line that contains the timecode arrow.
      final timeLineIdx = lines.indexWhere((l) => l.contains('-->'));
      if (timeLineIdx < 0) continue;

      final parts = lines[timeLineIdx].split('-->');
      if (parts.length < 2) continue;
      final start = _parseTime(parts[0]);
      final end = _parseTime(parts[1]);
      if (start == null || end == null) continue;

      final text = lines.sublist(timeLineIdx + 1).join('\n').trim();
      if (text.isEmpty) continue;

      entries.add(SubtitleEntry(index: ++index, startTime: start, endTime: end, text: _stripTags(text)));
    }
    return entries;
  }

  static List<SubtitleEntry> _parseAss(String content) {
    final entries = <SubtitleEntry>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');

    var startField = 1;
    var endField = 2;
    var textField = 9;
    var index = 0;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('Format:') && line.toLowerCase().contains('text')) {
        final fields = line.substring('Format:'.length).split(',').map((e) => e.trim().toLowerCase()).toList();
        final si = fields.indexOf('start');
        final ei = fields.indexOf('end');
        final ti = fields.indexOf('text');
        if (si >= 0) startField = si;
        if (ei >= 0) endField = ei;
        if (ti >= 0) textField = ti;
        continue;
      }
      if (!line.startsWith('Dialogue:')) continue;

      // Dialogue fields are comma-separated, but the Text field (last) may itself
      // contain commas, so split with a limit up to the text field.
      final body = line.substring('Dialogue:'.length);
      final parts = body.split(',');
      if (parts.length <= textField) continue;
      final start = _parseTime(parts[startField]);
      final end = _parseTime(parts[endField]);
      if (start == null || end == null) continue;
      final text = parts.sublist(textField).join(',');
      final clean = _stripTags(text.replaceAll('\\N', '\n').replaceAll('\\n', '\n'));
      if (clean.isEmpty) continue;
      entries.add(SubtitleEntry(index: ++index, startTime: start, endTime: end, text: clean));
    }
    return entries;
  }

  /// Parses `HH:MM:SS,mmm`, `HH:MM:SS.mmm` or ASS `H:MM:SS.cc` timecodes.
  static Duration? _parseTime(String input) {
    final s = input.trim();
    final m = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})[.,](\d{1,3})').firstMatch(s);
    if (m == null) return null;
    final hours = int.parse(m.group(1)!);
    final minutes = int.parse(m.group(2)!);
    final seconds = int.parse(m.group(3)!);
    final fraction = m.group(4)!;
    // Normalize fraction to milliseconds (ASS uses centiseconds -> 2 digits).
    final ms = int.parse(fraction.padRight(3, '0').substring(0, 3));
    return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: ms);
  }

  static String _stripTags(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '') // <i>, <b>, <font ...>
        .replaceAll(RegExp(r'\{\\[^}]*\}'), '') // ASS override blocks {\an8}
        .trim();
  }
}
