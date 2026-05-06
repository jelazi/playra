import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/player_settings.dart';
import '../models/server_connection.dart';
import '../models/subtitle_style_settings.dart';
import '../models/video_item.dart';

/// Centralised storage for the new Playra app data (player settings,
/// resume positions, subtitle style, server list, recently played).
///
/// Uses untyped JSON-string boxes to avoid relying on generated adapters.
class PlayraStorage {
  static const String _playerBox = 'playra_player';
  static const String _resumeBox = 'playra_resume';
  static const String _styleBox = 'playra_style';
  static const String _serversBox = 'playra_servers';

  static const String _playerKey = 'settings';
  static const String _styleKey = 'style';
  static const String _recentsKey = 'recents';

  static const int _maxRecents = 20;

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

  // --- Recently played ---

  /// Reads the ordered list of recently played items (newest first).
  static List<VideoItem> getRecent() {
    final raw = _player?.get(_recentsKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) {
            try {
              return VideoItem.fromJson(e as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<VideoItem>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Adds [video] to the front of the recents list and trims to [_maxRecents].
  static Future<void> addRecent(VideoItem video) async {
    final list = getRecent().toList();
    // Remove duplicate
    list.removeWhere((v) => v.id == video.id);
    list.insert(0, video);
    if (list.length > _maxRecents) list.removeRange(_maxRecents, list.length);
    await _player?.put(_recentsKey, jsonEncode(list.map((v) => v.toJson()).toList()));
  }

  static Future<void> clearRecent() async {
    await _player?.delete(_recentsKey);
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
