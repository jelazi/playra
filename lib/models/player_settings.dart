import 'dart:convert';

const List<String> kDesktopShortcutKeyOptions = ['Space', 'KeyF', 'Enter', 'ArrowLeft', 'ArrowRight', 'KeyJ', 'KeyK', 'KeyL', 'KeyA', 'KeyS', 'KeyD'];

const List<String> kDesktopWheelActionOptions = ['none', 'seek', 'volume', 'brightness'];
const List<String> kDesktopModifierOptions = ['none', 'ctrl', 'alt', 'shift', 'meta'];
const List<String> kLibraryViewModeOptions = ['structured', 'flat', 'smart'];

/// Player-related settings.
class PlayerSettings {
  final bool resumePlayback; // remember last position per video
  final bool gesturesEnabled; // brightness/volume gestures
  final bool keepScreenOn;
  final double seekStepSeconds; // double-tap seek step
  final List<String> libraryFolders; // local folders scanned for videos
  final bool desktopShortcutsEnabled;
  final String desktopPlayPauseKey;
  final String desktopFullscreenKey;
  final String desktopSeekBackwardKey;
  final String desktopSeekForwardKey;
  final String desktopWheelAction;
  final double desktopWheelStep;
  final String desktopShortcutModifier;
  final String desktopDoubleClickModifier;
  final String libraryViewMode;

  const PlayerSettings({
    this.resumePlayback = true,
    this.gesturesEnabled = true,
    this.keepScreenOn = true,
    this.seekStepSeconds = 10,
    this.libraryFolders = const [],
    this.desktopShortcutsEnabled = true,
    this.desktopPlayPauseKey = 'Space',
    this.desktopFullscreenKey = 'KeyF',
    this.desktopSeekBackwardKey = 'ArrowLeft',
    this.desktopSeekForwardKey = 'ArrowRight',
    this.desktopWheelAction = 'seek',
    this.desktopWheelStep = 10,
    this.desktopShortcutModifier = 'none',
    this.desktopDoubleClickModifier = 'none',
    this.libraryViewMode = 'structured',
  });

  PlayerSettings copyWith({
    bool? resumePlayback,
    bool? gesturesEnabled,
    bool? keepScreenOn,
    double? seekStepSeconds,
    List<String>? libraryFolders,
    bool? desktopShortcutsEnabled,
    String? desktopPlayPauseKey,
    String? desktopFullscreenKey,
    String? desktopSeekBackwardKey,
    String? desktopSeekForwardKey,
    String? desktopWheelAction,
    double? desktopWheelStep,
    String? desktopShortcutModifier,
    String? desktopDoubleClickModifier,
    String? libraryViewMode,
  }) => PlayerSettings(
    resumePlayback: resumePlayback ?? this.resumePlayback,
    gesturesEnabled: gesturesEnabled ?? this.gesturesEnabled,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    seekStepSeconds: seekStepSeconds ?? this.seekStepSeconds,
    libraryFolders: libraryFolders ?? this.libraryFolders,
    desktopShortcutsEnabled: desktopShortcutsEnabled ?? this.desktopShortcutsEnabled,
    desktopPlayPauseKey: desktopPlayPauseKey ?? this.desktopPlayPauseKey,
    desktopFullscreenKey: desktopFullscreenKey ?? this.desktopFullscreenKey,
    desktopSeekBackwardKey: desktopSeekBackwardKey ?? this.desktopSeekBackwardKey,
    desktopSeekForwardKey: desktopSeekForwardKey ?? this.desktopSeekForwardKey,
    desktopWheelAction: desktopWheelAction ?? this.desktopWheelAction,
    desktopWheelStep: desktopWheelStep ?? this.desktopWheelStep,
    desktopShortcutModifier: desktopShortcutModifier ?? this.desktopShortcutModifier,
    desktopDoubleClickModifier: desktopDoubleClickModifier ?? this.desktopDoubleClickModifier,
    libraryViewMode: libraryViewMode ?? this.libraryViewMode,
  );

  Map<String, dynamic> toJson() => {
    'resumePlayback': resumePlayback,
    'gesturesEnabled': gesturesEnabled,
    'keepScreenOn': keepScreenOn,
    'seekStepSeconds': seekStepSeconds,
    'libraryFolders': libraryFolders,
    'desktopShortcutsEnabled': desktopShortcutsEnabled,
    'desktopPlayPauseKey': desktopPlayPauseKey,
    'desktopFullscreenKey': desktopFullscreenKey,
    'desktopSeekBackwardKey': desktopSeekBackwardKey,
    'desktopSeekForwardKey': desktopSeekForwardKey,
    'desktopWheelAction': desktopWheelAction,
    'desktopWheelStep': desktopWheelStep,
    'desktopShortcutModifier': desktopShortcutModifier,
    'desktopDoubleClickModifier': desktopDoubleClickModifier,
    'libraryViewMode': libraryViewMode,
  };

  factory PlayerSettings.fromJson(Map<String, dynamic> j) => PlayerSettings(
    resumePlayback: j['resumePlayback'] as bool? ?? true,
    gesturesEnabled: j['gesturesEnabled'] as bool? ?? true,
    keepScreenOn: j['keepScreenOn'] as bool? ?? true,
    seekStepSeconds: (j['seekStepSeconds'] as num?)?.toDouble() ?? 10,
    libraryFolders: (j['libraryFolders'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    desktopShortcutsEnabled: j['desktopShortcutsEnabled'] as bool? ?? true,
    desktopPlayPauseKey: (j['desktopPlayPauseKey'] as String?) ?? 'Space',
    desktopFullscreenKey: (j['desktopFullscreenKey'] as String?) ?? 'KeyF',
    desktopSeekBackwardKey: (j['desktopSeekBackwardKey'] as String?) ?? 'ArrowLeft',
    desktopSeekForwardKey: (j['desktopSeekForwardKey'] as String?) ?? 'ArrowRight',
    desktopWheelAction: (j['desktopWheelAction'] as String?) ?? 'seek',
    desktopWheelStep: (j['desktopWheelStep'] as num?)?.toDouble() ?? 10,
    desktopShortcutModifier: (j['desktopShortcutModifier'] as String?) ?? 'none',
    desktopDoubleClickModifier: (j['desktopDoubleClickModifier'] as String?) ?? 'none',
    libraryViewMode: (j['libraryViewMode'] as String?) ?? 'structured',
  );

  String encode() => jsonEncode(toJson());
  static PlayerSettings decode(String s) => PlayerSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
