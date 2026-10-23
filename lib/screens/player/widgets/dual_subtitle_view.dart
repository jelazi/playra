import 'dart:math';

import 'package:flutter/material.dart';

/// Which subtitle track, if any, is picture-based and drawn by mpv into the video.
enum BitmapSubtitleRole { none, primary, secondary }

/// The player's text subtitles: the main line, and the secondary track as a
/// smaller line below it, above it or at the top of the screen.
///
/// Used instead of media_kit's own subtitle view, which renders both lines in
/// one style and keeps showing a line after its track is turned off or
/// switched to a picture-based one (mpv stops reporting the text instead of
/// clearing it). Picture-based tracks are drawn by mpv into the bottom of the
/// picture, so their line is not shown here and the text is moved out of
/// their way: above them when they are the secondary track, below the picture
/// when they are the main one.
class DualSubtitleView extends StatelessWidget {
  const DualSubtitleView({
    super.key,
    required this.subtitles,
    required this.initialSubtitles,
    required this.style,
    required this.showSecondary,
    required this.secondaryScale,
    required this.padding,
    this.secondaryColor,
    this.secondaryPosition = 'below',
    this.horizontalAlign = 'center',
    this.horizontalOffset = 0,
    this.bitmapRole = BitmapSubtitleRole.none,
    this.videoSize,
    this.fit = BoxFit.contain,
    this.zoom = 1.0,
  });

  /// The player's `[main, secondary]` subtitle text, as media_kit reports it.
  final Stream<List<String>> subtitles;
  final List<String> initialSubtitles;
  final TextStyle style;
  final bool showSecondary;
  final double secondaryScale;
  final EdgeInsets padding;
  final Color? secondaryColor;

  /// 'below' or 'above' the main line, or 'top' of the screen.
  final String secondaryPosition;

  /// 'left', 'center' or 'right'.
  final String horizontalAlign;

  /// Sideways shift as a fraction of the available width.
  final double horizontalOffset;
  final BitmapSubtitleRole bitmapRole;

  /// The video's own resolution, used to find where the picture sits on screen.
  final Size? videoSize;
  final BoxFit fit;
  final double zoom;

  // media_kit's view scales text against a 1080p frame; matching it keeps
  // subtitles the size they had with that view.
  static const double _referenceArea = 1920.0 * 1080.0;

  // Blu-ray and DVD subtitles sit in roughly the bottom fifth of the picture.
  static const double _bitmapBandFraction = 0.22;

  static const double _topMargin = 24;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          final textScaler = TextScaler.linear(sqrt((area.width * area.height / _referenceArea).clamp(0.0, 1.0)));
          return StreamBuilder<List<String>>(
            stream: subtitles,
            initialData: initialSubtitles,
            builder: (context, snapshot) {
              final lines = snapshot.data ?? const <String>[];
              final primary = bitmapRole != BitmapSubtitleRole.primary && lines.isNotEmpty ? lines[0].trim() : '';
              final secondary = showSecondary && bitmapRole != BitmapSubtitleRole.secondary && lines.length > 1 ? lines[1].trim() : '';

              final primaryText = primary.isEmpty ? null : _text(primary, style, textScaler);
              final secondaryText = secondary.isEmpty
                  ? null
                  : _text(secondary, style.copyWith(fontSize: (style.fontSize ?? 30) * secondaryScale, color: secondaryColor), textScaler);

              final secondaryOnTop = secondaryPosition == 'top';
              final bottomLines = [
                if (secondaryPosition == 'above' && secondaryText != null) secondaryText,
                ?primaryText,
                if (secondaryPosition == 'below' && secondaryText != null) secondaryText,
              ];

              return Stack(
                children: [
                  if (bottomLines.isNotEmpty)
                    Positioned.fill(
                      child: _block(bottomLines, padding.copyWith(bottom: _bottomPadding(area, secondaryOnly: primaryText == null)), area, top: false),
                    ),
                  if (secondaryOnTop && secondaryText != null)
                    Positioned.fill(child: _block([secondaryText], padding.copyWith(top: _topMargin), area, top: true)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _text(String text, TextStyle style, TextScaler textScaler) => Text(text, style: style, textAlign: _textAlign, textScaler: textScaler);

  Widget _block(List<Widget> lines, EdgeInsets padding, Size area, {required bool top}) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment(_alignX, top ? -1 : 1),
        child: Transform.translate(
          offset: Offset(horizontalOffset * area.width, 0),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: _crossAxis, children: lines),
        ),
      ),
    );
  }

  double get _alignX => switch (horizontalAlign) {
    'left' => -1,
    'right' => 1,
    _ => 0,
  };

  TextAlign get _textAlign => switch (horizontalAlign) {
    'left' => TextAlign.left,
    'right' => TextAlign.right,
    _ => TextAlign.center,
  };

  CrossAxisAlignment get _crossAxis => switch (horizontalAlign) {
    'left' => CrossAxisAlignment.start,
    'right' => CrossAxisAlignment.end,
    _ => CrossAxisAlignment.center,
  };

  /// [secondaryOnly]: the bottom block holds just the secondary line, under a
  /// picture-based main track.
  double _bottomPadding(Size area, {required bool secondaryOnly}) {
    if (bitmapRole == BitmapSubtitleRole.none) return padding.bottom;
    final picture = _pictureRect(area);
    if (picture == null) return padding.bottom;
    final belowPicture = max(0.0, area.height - picture.bottom);
    final aboveBitmapBand = max(padding.bottom, belowPicture + picture.height * _bitmapBandFraction);
    if (bitmapRole == BitmapSubtitleRole.secondary) return aboveBitmapBand;
    if (secondaryOnly && secondaryPosition == 'above') return aboveBitmapBand;
    return min(padding.bottom, max(4.0, belowPicture / 4));
  }

  Rect? _pictureRect(Size area) {
    final source = videoSize;
    if (source == null || source.isEmpty || area.isEmpty) return null;
    final fitted = applyBoxFit(fit, source, area).destination;
    final scaled = Size(fitted.width * zoom, fitted.height * zoom);
    return Rect.fromCenter(center: area.center(Offset.zero), width: scaled.width, height: scaled.height);
  }
}
