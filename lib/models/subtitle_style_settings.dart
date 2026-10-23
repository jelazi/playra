import 'dart:convert';

/// Subtitle visual style stored in app settings.
class SubtitleStyleSettings {
  final bool enabled;
  final double fontSize; // logical pixels
  final String fontFamily; // e.g. 'Roboto', 'Arial', 'monospace'
  final int textColor; // ARGB
  final int backgroundColor; // ARGB; 0x00000000 means transparent
  final int outlineColor; // ARGB
  final double outlineWidth; // 0 = no outline
  final bool bold;
  final double bottomPadding; // distance from bottom edge in logical pixels
  final double secondaryFontScale; // secondary (learning) subtitles, relative to fontSize
  final String secondaryPosition; // one of kSecondarySubtitlePositions
  final int secondaryTextColor; // ARGB
  final String horizontalAlign; // one of kSubtitleHorizontalAligns
  final double horizontalOffset; // sideways shift as a fraction of the screen width, -0.4..0.4

  const SubtitleStyleSettings({
    this.enabled = true,
    this.fontSize = 30,
    this.fontFamily = 'Roboto',
    this.textColor = 0xFFFFFFFF,
    this.backgroundColor = 0x80000000,
    this.outlineColor = 0xFF000000,
    this.outlineWidth = 1.5,
    this.bold = false,
    this.bottomPadding = 32,
    this.secondaryFontScale = 0.6,
    this.secondaryPosition = 'below',
    this.secondaryTextColor = 0xFFFFFFFF,
    this.horizontalAlign = 'center',
    this.horizontalOffset = 0,
  });

  SubtitleStyleSettings copyWith({
    bool? enabled,
    double? fontSize,
    String? fontFamily,
    int? textColor,
    int? backgroundColor,
    int? outlineColor,
    double? outlineWidth,
    bool? bold,
    double? bottomPadding,
    double? secondaryFontScale,
    String? secondaryPosition,
    int? secondaryTextColor,
    String? horizontalAlign,
    double? horizontalOffset,
  }) => SubtitleStyleSettings(
    enabled: enabled ?? this.enabled,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily ?? this.fontFamily,
    textColor: textColor ?? this.textColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    outlineColor: outlineColor ?? this.outlineColor,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    bold: bold ?? this.bold,
    bottomPadding: bottomPadding ?? this.bottomPadding,
    secondaryFontScale: secondaryFontScale ?? this.secondaryFontScale,
    secondaryPosition: secondaryPosition ?? this.secondaryPosition,
    secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
    horizontalAlign: horizontalAlign ?? this.horizontalAlign,
    horizontalOffset: horizontalOffset ?? this.horizontalOffset,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'textColor': textColor,
    'backgroundColor': backgroundColor,
    'outlineColor': outlineColor,
    'outlineWidth': outlineWidth,
    'bold': bold,
    'bottomPadding': bottomPadding,
    'secondaryFontScale': secondaryFontScale,
    'secondaryPosition': secondaryPosition,
    'secondaryTextColor': secondaryTextColor,
    'horizontalAlign': horizontalAlign,
    'horizontalOffset': horizontalOffset,
  };

  factory SubtitleStyleSettings.fromJson(Map<String, dynamic> j) => SubtitleStyleSettings(
    enabled: j['enabled'] as bool? ?? true,
    fontSize: (j['fontSize'] as num?)?.toDouble() ?? 30,
    fontFamily: j['fontFamily'] as String? ?? 'Roboto',
    textColor: j['textColor'] as int? ?? 0xFFFFFFFF,
    backgroundColor: j['backgroundColor'] as int? ?? 0x80000000,
    outlineColor: j['outlineColor'] as int? ?? 0xFF000000,
    outlineWidth: (j['outlineWidth'] as num?)?.toDouble() ?? 1.5,
    bold: j['bold'] as bool? ?? false,
    bottomPadding: (j['bottomPadding'] as num?)?.toDouble() ?? 32,
    secondaryFontScale: (j['secondaryFontScale'] as num?)?.toDouble() ?? 0.6,
    secondaryPosition: kSecondarySubtitlePositions.contains(j['secondaryPosition']) ? j['secondaryPosition'] as String : 'below',
    secondaryTextColor: j['secondaryTextColor'] as int? ?? 0xFFFFFFFF,
    horizontalAlign: kSubtitleHorizontalAligns.contains(j['horizontalAlign']) ? j['horizontalAlign'] as String : 'center',
    horizontalOffset: ((j['horizontalOffset'] as num?)?.toDouble() ?? 0).clamp(-0.4, 0.4),
  );

  String encode() => jsonEncode(toJson());
  static SubtitleStyleSettings decode(String s) => SubtitleStyleSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// Where the secondary subtitles go relative to the main ones.
const List<String> kSecondarySubtitlePositions = ['below', 'above', 'top'];

const List<String> kSubtitleHorizontalAligns = ['left', 'center', 'right'];

/// Available font families exposed in the settings UI.
const List<String> kAvailableSubtitleFonts = [
  'Roboto',
  'Arial',
  'Helvetica',
  'Times New Roman',
  'Courier New',
  'Verdana',
  'Tahoma',
  'monospace',
  'serif',
  'sans-serif',
];
