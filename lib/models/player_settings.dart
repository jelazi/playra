import 'dart:convert';

const List<String> kDesktopWheelActionOptions = ['none', 'seek', 'volume', 'brightness'];
const List<String> kDesktopDoubleClickActionOptions = [
  'none',
  'fullscreen',
  'fit',
  'toggleControls',
  'seekBackward',
  'seekForward',
  'volumeUp',
  'volumeDown',
  'brightnessUp',
  'brightnessDown',
];
const List<String> kLibraryViewModeOptions = ['structured', 'flat', 'smart'];
const List<String> kLibraryVisualModeOptions = ['list', 'iconsSmall', 'iconsLarge'];

/// Player-related settings.
class PlayerSettings {
  final bool resumePlayback; // remember last position per video
  final bool gesturesEnabled; // brightness/volume gestures
  final bool keepScreenOn;
  final double seekStepSeconds; // double-tap seek step
  final List<String> libraryFolders; // local folders scanned for videos
  final bool desktopShortcutsEnabled;
  final String desktopPlayPauseShortcut;
  final String desktopFullscreenShortcut;
  final String desktopSeekBackwardShortcut;
  final String desktopSeekForwardShortcut;
  final String desktopDoubleClickAction;
  final String desktopWheelAction;
  final double desktopWheelStep;
  final String libraryViewMode;
  final String libraryVisualMode;

  const PlayerSettings({
    this.resumePlayback = true,
    this.gesturesEnabled = true,
    this.keepScreenOn = true,
    this.seekStepSeconds = 10,
    this.libraryFolders = const [],
    this.desktopShortcutsEnabled = true,
    this.desktopPlayPauseShortcut = 'Space',
    this.desktopFullscreenShortcut = 'F',
    this.desktopSeekBackwardShortcut = 'Arrow Left',
    this.desktopSeekForwardShortcut = 'Arrow Right',
    this.desktopDoubleClickAction = 'fullscreen',
    this.desktopWheelAction = 'seek',
    this.desktopWheelStep = 10,
    this.libraryViewMode = 'structured',
    this.libraryVisualMode = 'list',
  });

  PlayerSettings copyWith({
    bool? resumePlayback,
    bool? gesturesEnabled,
    bool? keepScreenOn,
    double? seekStepSeconds,
    List<String>? libraryFolders,
    bool? desktopShortcutsEnabled,
    String? desktopPlayPauseShortcut,
    String? desktopFullscreenShortcut,
    String? desktopSeekBackwardShortcut,
    String? desktopSeekForwardShortcut,
    String? desktopDoubleClickAction,
    String? desktopWheelAction,
    double? desktopWheelStep,
    String? libraryViewMode,
    String? libraryVisualMode,
  }) => PlayerSettings(
    resumePlayback: resumePlayback ?? this.resumePlayback,
    gesturesEnabled: gesturesEnabled ?? this.gesturesEnabled,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    seekStepSeconds: seekStepSeconds ?? this.seekStepSeconds,
    libraryFolders: libraryFolders ?? this.libraryFolders,
    desktopShortcutsEnabled: desktopShortcutsEnabled ?? this.desktopShortcutsEnabled,
    desktopPlayPauseShortcut: desktopPlayPauseShortcut ?? this.desktopPlayPauseShortcut,
    desktopFullscreenShortcut: desktopFullscreenShortcut ?? this.desktopFullscreenShortcut,
    desktopSeekBackwardShortcut: desktopSeekBackwardShortcut ?? this.desktopSeekBackwardShortcut,
    desktopSeekForwardShortcut: desktopSeekForwardShortcut ?? this.desktopSeekForwardShortcut,
    desktopDoubleClickAction: desktopDoubleClickAction ?? this.desktopDoubleClickAction,
    desktopWheelAction: desktopWheelAction ?? this.desktopWheelAction,
    desktopWheelStep: desktopWheelStep ?? this.desktopWheelStep,
    libraryViewMode: libraryViewMode ?? this.libraryViewMode,
    libraryVisualMode: libraryVisualMode ?? this.libraryVisualMode,
  );

  Map<String, dynamic> toJson() => {
    'resumePlayback': resumePlayback,
    'gesturesEnabled': gesturesEnabled,
    'keepScreenOn': keepScreenOn,
    'seekStepSeconds': seekStepSeconds,
    'libraryFolders': libraryFolders,
    'desktopShortcutsEnabled': desktopShortcutsEnabled,
    'desktopPlayPauseShortcut': desktopPlayPauseShortcut,
    'desktopFullscreenShortcut': desktopFullscreenShortcut,
    'desktopSeekBackwardShortcut': desktopSeekBackwardShortcut,
    'desktopSeekForwardShortcut': desktopSeekForwardShortcut,
    'desktopDoubleClickAction': desktopDoubleClickAction,
    'desktopWheelAction': desktopWheelAction,
    'desktopWheelStep': desktopWheelStep,
    'libraryViewMode': libraryViewMode,
    'libraryVisualMode': libraryVisualMode,
  };

  factory PlayerSettings.fromJson(Map<String, dynamic> j) => PlayerSettings(
    resumePlayback: j['resumePlayback'] as bool? ?? true,
    gesturesEnabled: j['gesturesEnabled'] as bool? ?? true,
    keepScreenOn: j['keepScreenOn'] as bool? ?? true,
    seekStepSeconds: (j['seekStepSeconds'] as num?)?.toDouble() ?? 10,
    libraryFolders: (j['libraryFolders'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    desktopShortcutsEnabled: j['desktopShortcutsEnabled'] as bool? ?? true,
    desktopPlayPauseShortcut: (j['desktopPlayPauseShortcut'] as String?) ?? (j['desktopPlayPauseKey'] as String?) ?? 'Space',
    desktopFullscreenShortcut: (j['desktopFullscreenShortcut'] as String?) ?? (j['desktopFullscreenKey'] as String?) ?? 'F',
    desktopSeekBackwardShortcut: (j['desktopSeekBackwardShortcut'] as String?) ?? (j['desktopSeekBackwardKey'] as String?) ?? 'Arrow Left',
    desktopSeekForwardShortcut: (j['desktopSeekForwardShortcut'] as String?) ?? (j['desktopSeekForwardKey'] as String?) ?? 'Arrow Right',
    desktopDoubleClickAction: (j['desktopDoubleClickAction'] as String?) ?? 'fullscreen',
    desktopWheelAction: (j['desktopWheelAction'] as String?) ?? 'seek',
    desktopWheelStep: (j['desktopWheelStep'] as num?)?.toDouble() ?? 10,
    libraryViewMode: (j['libraryViewMode'] as String?) ?? 'structured',
    libraryVisualMode: (j['libraryVisualMode'] as String?) ?? 'list',
  );

  String encode() => jsonEncode(toJson());
  static PlayerSettings decode(String s) => PlayerSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
