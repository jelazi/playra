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
  static const String _recentMetaKey = 'recent_meta';
  static const String _trackPrefsKey = 'track_prefs';
  static const String _trackPrefsMetaKey = 'track_prefs_meta';
  static const String _resumeMetaKey = 'resume_meta';
  static const String _recentPosterByVideoKey = 'recent_posters_by_video';
  static const String _recentPosterBySeriesKey = 'recent_posters_by_series';
  static const String _lastOpenedDirectoryKey = 'last_opened_directory';
  static const String _librarySectionExpandedKey = 'library_section_expanded';

  static const int _maxRecents = 20;

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

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
    final meta = _readMap(_resumeMetaKey);
    if (positionMs <= 0) {
      await _resume?.delete(videoId);
      meta.remove(videoId);
    } else {
      await _resume?.put(videoId, positionMs);
      meta[videoId] = <String, dynamic>{'positionMs': positionMs, 'updatedAt': _nowMs()};
    }
    await _writeMap(_resumeMetaKey, meta);
  }

  static Future<void> clearResume(String videoId) async {
    await _resume?.delete(videoId);
    final meta = _readMap(_resumeMetaKey);
    meta.remove(videoId);
    await _writeMap(_resumeMetaKey, meta);
  }

  static Future<void> clearAllResume() async {
    await _resume?.clear();
    await _player?.delete(_resumeMetaKey);
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

    final meta = _readMap(_recentMetaKey);
    meta[video.id] = <String, dynamic>{'video': video.toJson(), 'updatedAt': _nowMs()};
    await _writeMap(_recentMetaKey, meta);
  }

  static Future<void> clearRecent() async {
    await _player?.delete(_recentsKey);
    await _player?.delete(_recentMetaKey);
  }

  static Future<void> removeRecent(String videoId) async {
    final list = getRecent().toList();
    list.removeWhere((v) => v.id == videoId);
    await _player?.put(_recentsKey, jsonEncode(list.map((v) => v.toJson()).toList()));

    final meta = _readMap(_recentMetaKey);
    meta.remove(videoId);
    await _writeMap(_recentMetaKey, meta);
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
    final meta = _readMap(_trackPrefsMetaKey);
    final metaPref = (meta[videoId] is Map) ? Map<String, dynamic>.from(meta[videoId] as Map) : <String, dynamic>{};
    if (trackKey == null || trackKey.isEmpty) {
      pref.remove('audio');
      metaPref.remove('audio');
      metaPref.remove('audioUpdatedAt');
    } else {
      pref['audio'] = trackKey;
      metaPref['audio'] = trackKey;
      metaPref['audioUpdatedAt'] = _nowMs();
    }
    if (pref.isEmpty) {
      all.remove(videoId);
    } else {
      all[videoId] = pref;
    }
    if (metaPref.isEmpty) {
      meta.remove(videoId);
    } else {
      meta[videoId] = metaPref;
    }
    await _saveTrackPrefsMap(all);
    await _writeMap(_trackPrefsMetaKey, meta);
  }

  static Future<void> savePreferredSubtitleTrackKey(String videoId, String? trackKey) async {
    final all = _getTrackPrefsMap();
    final pref = (all[videoId] is Map) ? Map<String, dynamic>.from(all[videoId] as Map) : <String, dynamic>{};
    final meta = _readMap(_trackPrefsMetaKey);
    final metaPref = (meta[videoId] is Map) ? Map<String, dynamic>.from(meta[videoId] as Map) : <String, dynamic>{};
    if (trackKey == null || trackKey.isEmpty) {
      pref.remove('subtitle');
      metaPref.remove('subtitle');
      metaPref.remove('subtitleUpdatedAt');
    } else {
      pref['subtitle'] = trackKey;
      metaPref['subtitle'] = trackKey;
      metaPref['subtitleUpdatedAt'] = _nowMs();
    }
    if (pref.isEmpty) {
      all.remove(videoId);
    } else {
      all[videoId] = pref;
    }
    if (metaPref.isEmpty) {
      meta.remove(videoId);
    } else {
      meta[videoId] = metaPref;
    }
    await _saveTrackPrefsMap(all);
    await _writeMap(_trackPrefsMetaKey, meta);
  }

  static Map<String, dynamic> _readMap(String key) {
    final raw = _player?.get(key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<void> _writeMap(String key, Map<String, dynamic> value) async {
    await _player?.put(key, jsonEncode(value));
  }

  static Map<String, dynamic> exportSyncSnapshot() {
    return <String, dynamic>{'schema': 1, 'generatedAt': _nowMs(), 'recents': _readMap(_recentMetaKey), 'resume': _readMap(_resumeMetaKey), 'tracks': _readMap(_trackPrefsMetaKey)};
  }

  static int _updatedAtFromEntry(dynamic entry) {
    if (entry is! Map) return 0;
    final ms = entry['updatedAt'];
    if (ms is int) return ms;
    if (ms is num) return ms.toInt();
    return 0;
  }

  static int _fieldUpdatedAtFromEntry(dynamic entry, String field) {
    if (entry is! Map) return 0;
    final ms = entry[field];
    if (ms is int) return ms;
    if (ms is num) return ms.toInt();
    return 0;
  }

  static Future<void> mergeSyncSnapshot(Map<String, dynamic> snapshot) async {
    final incomingRecents = snapshot['recents'] is Map ? Map<String, dynamic>.from(snapshot['recents'] as Map) : <String, dynamic>{};
    final incomingResume = snapshot['resume'] is Map ? Map<String, dynamic>.from(snapshot['resume'] as Map) : <String, dynamic>{};
    final incomingTracks = snapshot['tracks'] is Map ? Map<String, dynamic>.from(snapshot['tracks'] as Map) : <String, dynamic>{};

    // Merge recents by per-video updatedAt.
    final localRecentsMeta = _readMap(_recentMetaKey);
    incomingRecents.forEach((videoId, incomingValue) {
      if (incomingValue is! Map) return;
      final incomingUpdatedAt = _updatedAtFromEntry(incomingValue);
      final localUpdatedAt = _updatedAtFromEntry(localRecentsMeta[videoId]);
      if (incomingUpdatedAt < localUpdatedAt) return;
      final videoJson = incomingValue['video'];
      if (videoJson is! Map) return;
      localRecentsMeta[videoId] = <String, dynamic>{'video': Map<String, dynamic>.from(videoJson), 'updatedAt': incomingUpdatedAt};
    });

    final recentEntries = localRecentsMeta.entries.where((e) => e.value is Map && (e.value as Map)['video'] is Map).toList()
      ..sort((a, b) => _updatedAtFromEntry(b.value).compareTo(_updatedAtFromEntry(a.value)));
    final topRecentEntries = recentEntries.take(_maxRecents).toList();
    final mergedRecentVideos = <VideoItem>[];
    final trimmedRecentMeta = <String, dynamic>{};
    for (final entry in topRecentEntries) {
      final value = entry.value as Map;
      try {
        final video = VideoItem.fromJson(Map<String, dynamic>.from(value['video'] as Map));
        mergedRecentVideos.add(video);
        trimmedRecentMeta[entry.key] = value;
      } catch (_) {}
    }
    await _player?.put(_recentsKey, jsonEncode(mergedRecentVideos.map((v) => v.toJson()).toList()));
    await _writeMap(_recentMetaKey, trimmedRecentMeta);

    // Merge resume positions by per-video updatedAt.
    final localResumeMeta = _readMap(_resumeMetaKey);
    incomingResume.forEach((videoId, incomingValue) {
      if (incomingValue is! Map) return;
      final incomingUpdatedAt = _updatedAtFromEntry(incomingValue);
      final localUpdatedAt = _updatedAtFromEntry(localResumeMeta[videoId]);
      if (incomingUpdatedAt < localUpdatedAt) return;
      final position = incomingValue['positionMs'];
      final positionMs = position is num ? position.toInt() : 0;
      if (positionMs <= 0) {
        _resume?.delete(videoId);
        localResumeMeta.remove(videoId);
      } else {
        _resume?.put(videoId, positionMs);
        localResumeMeta[videoId] = <String, dynamic>{'positionMs': positionMs, 'updatedAt': incomingUpdatedAt};
      }
    });
    await _writeMap(_resumeMetaKey, localResumeMeta);

    // Merge preferred tracks by per-field updatedAt.
    final localTrackPrefs = _getTrackPrefsMap();
    final localTrackMeta = _readMap(_trackPrefsMetaKey);
    incomingTracks.forEach((videoId, incomingValue) {
      if (incomingValue is! Map) return;

      final localPref = (localTrackPrefs[videoId] is Map) ? Map<String, dynamic>.from(localTrackPrefs[videoId] as Map) : <String, dynamic>{};
      final localMeta = (localTrackMeta[videoId] is Map) ? Map<String, dynamic>.from(localTrackMeta[videoId] as Map) : <String, dynamic>{};

      final incomingAudioAt = _fieldUpdatedAtFromEntry(incomingValue, 'audioUpdatedAt');
      final localAudioAt = _fieldUpdatedAtFromEntry(localMeta, 'audioUpdatedAt');
      if (incomingAudioAt >= localAudioAt && incomingAudioAt > 0) {
        final incomingAudio = incomingValue['audio'];
        if (incomingAudio is String && incomingAudio.isNotEmpty) {
          localPref['audio'] = incomingAudio;
          localMeta['audio'] = incomingAudio;
          localMeta['audioUpdatedAt'] = incomingAudioAt;
        } else {
          localPref.remove('audio');
          localMeta.remove('audio');
          localMeta.remove('audioUpdatedAt');
        }
      }

      final incomingSubtitleAt = _fieldUpdatedAtFromEntry(incomingValue, 'subtitleUpdatedAt');
      final localSubtitleAt = _fieldUpdatedAtFromEntry(localMeta, 'subtitleUpdatedAt');
      if (incomingSubtitleAt >= localSubtitleAt && incomingSubtitleAt > 0) {
        final incomingSubtitle = incomingValue['subtitle'];
        if (incomingSubtitle is String && incomingSubtitle.isNotEmpty) {
          localPref['subtitle'] = incomingSubtitle;
          localMeta['subtitle'] = incomingSubtitle;
          localMeta['subtitleUpdatedAt'] = incomingSubtitleAt;
        } else {
          localPref.remove('subtitle');
          localMeta.remove('subtitle');
          localMeta.remove('subtitleUpdatedAt');
        }
      }

      if (localPref.isEmpty) {
        localTrackPrefs.remove(videoId);
      } else {
        localTrackPrefs[videoId] = localPref;
      }

      if (localMeta.isEmpty) {
        localTrackMeta.remove(videoId);
      } else {
        localTrackMeta[videoId] = localMeta;
      }
    });

    await _saveTrackPrefsMap(localTrackPrefs);
    await _writeMap(_trackPrefsMetaKey, localTrackMeta);
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

  // --- Library section expand/collapse state ---
  static Map<String, bool> getLibrarySectionExpandedMap() {
    final raw = _player?.get(_librarySectionExpandedKey);
    if (raw == null) return <String, bool>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, bool>{};
      return decoded.map((k, v) => MapEntry(k.toString(), v == true));
    } catch (_) {
      return <String, bool>{};
    }
  }

  static Future<void> setLibrarySectionExpandedMap(Map<String, bool> map) async {
    await _player?.put(_librarySectionExpandedKey, jsonEncode(map));
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
