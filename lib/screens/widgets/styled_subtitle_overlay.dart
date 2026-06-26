import 'package:flutter/material.dart';

import '../../models/subtitle_entry.dart';
import '../../models/subtitle_style_settings.dart';

/// Renders subtitle cues as Flutter text on top of the video, fully styled from
/// [SubtitleStyleSettings]. This replaces the player engine's built-in (burned-in)
/// subtitle rendering so colours, outline, background and font stay customizable
/// for both external subtitle files and subtitles extracted from the container.
class StyledSubtitleOverlay extends StatelessWidget {
  const StyledSubtitleOverlay({super.key, required this.cues, required this.position, required this.style, this.delay = Duration.zero});

  /// Active cue list, sorted by start time (may be empty).
  final List<SubtitleEntry> cues;

  /// Current playback position.
  final Duration position;

  /// Subtitle styling settings.
  final SubtitleStyleSettings style;

  /// Subtitle delay. Positive shows subtitles later, negative earlier — matching
  /// the previous mpv `sub-delay` semantics.
  final Duration delay;

  SubtitleEntry? _activeCue() {
    if (!style.enabled || cues.isEmpty) return null;
    // Effective time the cues are compared against: shifting the lookup time by
    // -delay is equivalent to shifting every cue by +delay.
    final t = position - delay;
    for (final cue in cues) {
      if (t >= cue.startTime && t <= cue.endTime) return cue;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cue = _activeCue();
    if (cue == null) return const SizedBox.shrink();

    final outline = style.outlineWidth;
    final shadows = outline > 0
        ? <Shadow>[
            for (final dx in [-outline, 0.0, outline])
              for (final dy in [-outline, 0.0, outline])
                if (dx != 0 || dy != 0) Shadow(offset: Offset(dx, dy), color: Color(style.outlineColor), blurRadius: 0),
          ]
        : null;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, style.bottomPadding),
        child: Container(
          decoration: BoxDecoration(color: Color(style.backgroundColor), borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            _stripTags(cue.text),
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.4,
              fontSize: style.fontSize,
              fontFamily: style.fontFamily,
              color: Color(style.textColor),
              fontWeight: style.bold ? FontWeight.bold : FontWeight.normal,
              shadows: shadows,
            ),
          ),
        ),
      ),
    );
  }

  /// Strips common SRT/ASS inline markup so the styled text stays clean.
  static String _stripTags(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '') // HTML-ish tags (<i>, <b>, <font>)
        .replaceAll(RegExp(r'\{\\[^}]*\}'), '') // ASS override blocks {\an8}
        .trim();
  }
}
