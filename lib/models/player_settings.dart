import 'dart:convert';

/// Player-related settings.
class PlayerSettings {
  final bool resumePlayback; // remember last position per video
  final bool gesturesEnabled; // brightness/volume gestures
  final bool keepScreenOn;
  final double seekStepSeconds; // double-tap seek step
  final List<String> libraryFolders; // local folders scanned for videos

  const PlayerSettings({this.resumePlayback = true, this.gesturesEnabled = true, this.keepScreenOn = true, this.seekStepSeconds = 10, this.libraryFolders = const []});

  PlayerSettings copyWith({bool? resumePlayback, bool? gesturesEnabled, bool? keepScreenOn, double? seekStepSeconds, List<String>? libraryFolders}) => PlayerSettings(
    resumePlayback: resumePlayback ?? this.resumePlayback,
    gesturesEnabled: gesturesEnabled ?? this.gesturesEnabled,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    seekStepSeconds: seekStepSeconds ?? this.seekStepSeconds,
    libraryFolders: libraryFolders ?? this.libraryFolders,
  );

  Map<String, dynamic> toJson() => {
    'resumePlayback': resumePlayback,
    'gesturesEnabled': gesturesEnabled,
    'keepScreenOn': keepScreenOn,
    'seekStepSeconds': seekStepSeconds,
    'libraryFolders': libraryFolders,
  };

  factory PlayerSettings.fromJson(Map<String, dynamic> j) => PlayerSettings(
    resumePlayback: j['resumePlayback'] as bool? ?? true,
    gesturesEnabled: j['gesturesEnabled'] as bool? ?? true,
    keepScreenOn: j['keepScreenOn'] as bool? ?? true,
    seekStepSeconds: (j['seekStepSeconds'] as num?)?.toDouble() ?? 10,
    libraryFolders: (j['libraryFolders'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );

  String encode() => jsonEncode(toJson());
  static PlayerSettings decode(String s) => PlayerSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
