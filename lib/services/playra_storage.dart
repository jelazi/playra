import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/player_settings.dart';
import '../models/server_connection.dart';
import '../models/subtitle_style_settings.dart';
import '../models/video_item.dart';
import 'video_name_parser.dart';

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
  static const String _trackPrefsKey = 'track_prefs';
  static const String _recentPosterByVideoKey = 'recent_posters_by_video';
  static const String _recentPosterBySeriesKey = 'recent_posters_by_series';
  static const String _lastOpenedDirectoryKey = 'last_opened_directory';

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

  static Future<void> removeRecent(String videoId) async {
    final list = getRecent().toList();
    list.removeWhere((v) => v.id == videoId);
    await _player?.put(_recentsKey, jsonEncode(list.map((v) => v.toJson()).toList()));
  }

  // --- Track preferences (videoId -> audio/subtitle track key) ---

  static Map<String, dynamic> _getTrackPrefsMap() {
    final raw = _player?.get(_trackPrefsKey);
    if (raw == null) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> _saveTrackPrefsMap(Map<String, dynamic> map) async {
    await _player?.put(_trackPrefsKey, jsonEncode(map));
  }

  static String? getPreferredAudioTrackKey(String videoId) {
    final all = _getTrackPrefsMap();
    final pref = all[videoId];
    if (pref is! Map) return null;
    final value = pref['audio'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static String? getPreferredSubtitleTrackKey(String videoId) {
    final all = _getTrackPrefsMap();
    final pref = all[videoId];
    if (pref is! Map) return null;
    final value = pref['subtitle'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static Future<void> savePreferredAudioTrackKey(String videoId, String? trackKey) async {
    final all = _getTrackPrefsMap();
    final pref = (all[videoId] is Map) ? Map<String, dynamic>.from(all[videoId] as Map) : <String, dynamic>{};
    if (trackKey == null || trackKey.isEmpty) {
      pref.remove('audio');
    } else {
      pref['audio'] = trackKey;
    }
    if (pref.isEmpty) {
      all.remove(videoId);
    } else {
      all[videoId] = pref;
    }
    await _saveTrackPrefsMap(all);
  }

  static Future<void> savePreferredSubtitleTrackKey(String videoId, String? trackKey) async {
    final all = _getTrackPrefsMap();
    final pref = (all[videoId] is Map) ? Map<String, dynamic>.from(all[videoId] as Map) : <String, dynamic>{};
    if (trackKey == null || trackKey.isEmpty) {
      pref.remove('subtitle');
    } else {
      pref['subtitle'] = trackKey;
    }
    if (pref.isEmpty) {
      all.remove(videoId);
    } else {
      all[videoId] = pref;
    }
    await _saveTrackPrefsMap(all);
  }

  // --- Recent poster paths ---

  static Map<String, String> _readStringMap(String key) {
    final raw = _player?.get(key);
    if (raw == null) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  static Future<void> _writeStringMap(String key, Map<String, String> map) async {
    await _player?.put(key, jsonEncode(map));
  }

  static String _seriesCacheKey(VideoItem video) {
    final parsed = VideoNameParser.parse(video.uri);
    final key = parsed.cleanName.trim().toLowerCase();
    return key.isEmpty ? video.displayName.trim().toLowerCase() : key;
  }

  static Future<void> saveRecentPosterPath(VideoItem video, String localPath) async {
    if (localPath.isEmpty) return;

    final byVideo = _readStringMap(_recentPosterByVideoKey);
    byVideo[video.id] = localPath;
    await _writeStringMap(_recentPosterByVideoKey, byVideo);

    final bySeries = _readStringMap(_recentPosterBySeriesKey);
    final seriesKey = _seriesCacheKey(video);
    bySeries[seriesKey] = localPath;
    await _writeStringMap(_recentPosterBySeriesKey, bySeries);
  }

  static String? getRecentPosterPath(VideoItem video) {
    final byVideo = _readStringMap(_recentPosterByVideoKey);
    final direct = byVideo[video.id];
    if (direct != null && direct.isNotEmpty && File(direct).existsSync()) {
      return direct;
    }

    final bySeries = _readStringMap(_recentPosterBySeriesKey);
    final seriesPath = bySeries[_seriesCacheKey(video)];
    if (seriesPath != null && seriesPath.isNotEmpty && File(seriesPath).existsSync()) {
      return seriesPath;
    }

    return null;
  }

  // --- Last opened file directory ---
  static String? getLastOpenedDirectory() {
    final value = _player?.get(_lastOpenedDirectoryKey);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Future<void> setLastOpenedDirectory(String? directory) async {
    if (directory == null || directory.isEmpty) return;
    await _player?.put(_lastOpenedDirectoryKey, directory);
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
