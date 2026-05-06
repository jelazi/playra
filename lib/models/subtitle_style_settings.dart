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

  const SubtitleStyleSettings({
    this.enabled = true,
    this.fontSize = 30,
    this.fontFamily = 'Roboto',
    this.textColor = 0xFFFFFFFF,
    this.backgroundColor = 0x80000000,
    this.outlineColor = 0xFF000000,
    this.outlineWidth = 1.5,
    this.bold = false,
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
  }) => SubtitleStyleSettings(
    enabled: enabled ?? this.enabled,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily ?? this.fontFamily,
    textColor: textColor ?? this.textColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    outlineColor: outlineColor ?? this.outlineColor,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    bold: bold ?? this.bold,
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
  );

  String encode() => jsonEncode(toJson());
  static SubtitleStyleSettings decode(String s) => SubtitleStyleSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// Available font families exposed in the settings UI.
const List<String> kAvailableSubtitleFonts = ['Roboto', 'Arial', 'Helvetica', 'Times New Roman', 'Courier New', 'Verdana', 'Tahoma', 'monospace', 'serif', 'sans-serif'];
