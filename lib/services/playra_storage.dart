import 'package:hive_flutter/hive_flutter.dart';

import '../models/player_settings.dart';
import '../models/server_connection.dart';
import '../models/subtitle_style_settings.dart';

/// Centralised storage for the new Playra app data (player settings,
/// resume positions, subtitle style, server list).
///
/// Uses untyped JSON-string boxes to avoid relying on generated adapters.
class PlayraStorage {
  static const String _playerBox = 'playra_player';
  static const String _resumeBox = 'playra_resume';
  static const String _styleBox = 'playra_style';
  static const String _serversBox = 'playra_servers';

  static const String _playerKey = 'settings';
  static const String _styleKey = 'style';

  static Box<String>? _player;
  static Box<int>? _resume;
  static Box<String>? _style;
  static Box<String>? _servers;

  /// Initialise Hive (callable after Hive.initFlutter has been called).
  static Future<void> init() async {
    _player = await Hive.openBox<String>(_playerBox);
    _resume = await Hive.openBox<int>(_resumeBox);
    _style = await Hive.openBox<String>(_styleBox);
    _servers = await Hive.openBox<String>(_serversBox);
  }

  // --- Player settings ---
  static PlayerSettings getPlayerSettings() {
    final raw = _player?.get(_playerKey);
    if (raw == null) return const PlayerSettings();
    try {
      return PlayerSettings.decode(raw);
    } catch (_) {
      return const PlayerSettings();
    }
  }

  static Future<void> savePlayerSettings(PlayerSettings s) async {
    await _player?.put(_playerKey, s.encode());
  }

  // --- Subtitle style ---
  static SubtitleStyleSettings getStyle() {
    final raw = _style?.get(_styleKey);
    if (raw == null) return const SubtitleStyleSettings();
    try {
      return SubtitleStyleSettings.decode(raw);
    } catch (_) {
      return const SubtitleStyleSettings();
    }
  }

  static Future<void> saveStyle(SubtitleStyleSettings s) async {
    await _style?.put(_styleKey, s.encode());
  }

  // --- Resume positions (videoId -> milliseconds) ---
  static int? getResume(String videoId) => _resume?.get(videoId);

  static Future<void> setResume(String videoId, int positionMs) async {
    if (positionMs <= 0) {
      await _resume?.delete(videoId);
    } else {
      await _resume?.put(videoId, positionMs);
    }
  }

  static Future<void> clearResume(String videoId) async {
    await _resume?.delete(videoId);
  }

  static Future<void> clearAllResume() async {
    await _resume?.clear();
  }

  // --- Servers ---
  static List<ServerConnection> getServers() {
    final box = _servers;
    if (box == null) return const [];
    return box.values
        .map((s) {
          try {
            return ServerConnection.decode(s);
          } catch (_) {
            return null;
          }
        })
        .whereType<ServerConnection>()
        .toList();
  }

  static Future<void> saveServer(ServerConnection s) async {
    await _servers?.put(s.id, s.encode());
  }

  static Future<void> deleteServer(String id) async {
    await _servers?.delete(id);
  }
}
