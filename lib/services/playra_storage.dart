import 'dart:async';
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
  static const String _libraryFoldersBox = 'playra_library_folders';
  static const String _resumeBox = 'playra_resume';
  static const String _styleBox = 'playra_style';
  static const String _serversBox = 'playra_servers';

  static const String _playerKey = 'settings';
  static const String _libraryFoldersKey = 'folders';
  static const String _styleKey = 'style';
  static const String _recentsKey = 'recents';
  static const String _recentMetaKey = 'recent_meta';
  static const String _trackPrefsKey = 'track_prefs';
  static const String _trackPrefsMetaKey = 'track_prefs_meta';
  static const String _resumeMetaKey = 'resume_meta';
  static const String _resumeByHashMetaKey = 'resume_by_hash_meta';
  static const String _trackPrefsByHashMetaKey = 'track_prefs_by_hash_meta';
  static const String _trackPrefsBySeriesMetaKey = 'track_prefs_by_series_meta';
  static const String _subtitleDelayMetaKey = 'subtitle_delay_meta';
  static const String _durationMetaKey = 'duration_meta';
  static const String _videoIdentityMetaKey = 'video_identity_meta';
  static const String _recentByHashMetaKey = 'recent_by_hash_meta';
  static const String _mediaByHashMetaKey = 'media_by_hash_meta';
  static const String _nowPlayingSessionKey = 'now_playing_session';
  static const String _recentPosterByVideoKey = 'recent_posters_by_video';
  static const String _recentPosterBySeriesKey = 'recent_posters_by_series';
  static const String _lastOpenedDirectoryKey = 'last_opened_directory';
  static const String _librarySectionExpandedKey = 'library_section_expanded';

  static const int _maxRecents = 20;
  static const int _maxNowPlayingAgeMs = 6 * 60 * 60 * 1000;

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  static Box<String>? _player;
  static Box<String>? _libraryFolders;
  static Box<int>? _resume;
  static Box<String>? _style;
  static Box<String>? _servers;

  /// Initialise Hive (callable after Hive.initFlutter has been called).
  static Future<void> init() async {
    _player = await Hive.openBox<String>(_playerBox);
    _libraryFolders = await Hive.openBox<String>(_libraryFoldersBox);
    _resume = await Hive.openBox<int>(_resumeBox);
    _style = await Hive.openBox<String>(_styleBox);
    _servers = await Hive.openBox<String>(_serversBox);
  }

  // --- Player settings ---
  static PlayerSettings getPlayerSettings() {
    final raw = _player?.get(_playerKey);
    if (raw == null) return const PlayerSettings();
    try {
      final settings = PlayerSettings.decode(raw);
      return settings.copyWith(libraryFolders: getLibraryFolders());
    } catch (_) {
      return const PlayerSettings();
    }
  }

  static Future<void> savePlayerSettings(PlayerSettings s) async {
    final merged = s.copyWith(libraryFolders: getLibraryFolders());
    await _player?.put(_playerKey, merged.encode());
  }

  static List<String> getLibraryFolders() {
    final raw = _libraryFolders?.get(_libraryFoldersKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
        }
      } catch (_) {}
    }

    final legacyRaw = _player?.get(_playerKey);
    final legacy = legacyRaw == null
        ? const <String>[]
        : (() {
            try {
              return PlayerSettings.decode(legacyRaw).libraryFolders;
            } catch (_) {
              return const <String>[];
            }
          })();
    if (legacy.isNotEmpty) {
      unawaited(_libraryFolders?.put(_libraryFoldersKey, jsonEncode(_normalizeFolders(legacy))));
    }
    return _normalizeFolders(legacy);
  }

  static Future<void> setLibraryFolders(List<String> folders) async {
    final normalized = _normalizeFolders(folders);
    await _libraryFolders?.put(_libraryFoldersKey, jsonEncode(normalized));
    final settings = getPlayerSettings();
    await _player?.put(_playerKey, settings.copyWith(libraryFolders: normalized).encode());
  }

  static Future<void> addLibraryFolder(String folder) async {
    final normalizedFolder = _normalizeFolder(folder);
    final folders = getLibraryFolders();
    if (folders.any((f) => _normalizeFolder(f) == normalizedFolder)) return;
    await setLibraryFolders([...folders, normalizedFolder]);
  }

  static Future<void> removeLibraryFolder(String folder) async {
    final normalizedFolder = _normalizeFolder(folder);
    final folders = getLibraryFolders().where((f) => _normalizeFolder(f) != normalizedFolder).toList();
    await setLibraryFolders(folders);
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

  static List<String> _normalizeFolders(List<String> folders) {
    final out = <String>[];
    for (final folder in folders) {
      final normalized = _normalizeFolder(folder);
      if (normalized.isEmpty) continue;
      if (out.contains(normalized)) continue;
      out.add(normalized);
    }
    return out;
  }

  static String _normalizeFolder(String folder) {
    var value = folder.trim();
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  // --- Video identity map (videoId -> stable content hash) ---

  static String? getVideoHash(String videoId) {
    final map = _readMap(_videoIdentityMetaKey);
    final entry = map[videoId];
    if (entry is! Map) return null;
    final hash = entry['hash'];
    if (hash is! String || hash.isEmpty) return null;
    return hash;
  }

  static List<String> getVideoIdsForHash(String hash) {
    if (hash.isEmpty) return const [];
    final map = _readMap(_videoIdentityMetaKey);
    final out = <String>[];
    map.forEach((videoId, entry) {
      if (entry is! Map) return;
      if (entry['hash'] == hash) out.add(videoId);
    });
    return out;
  }

  static Future<void> bindVideoToHash({required String videoId, required String hash, String? title, int? sizeBytes}) async {
    if (videoId.isEmpty || hash.isEmpty) return;
    final now = _nowMs();
    final map = _readMap(_videoIdentityMetaKey);
    map[videoId] = <String, dynamic>{'hash': hash, 'title': title, 'sizeBytes': sizeBytes, 'updatedAt': now};
    await _writeMap(_videoIdentityMetaKey, map);

    final existingResume = _resume?.get(videoId);
    if (existingResume != null && existingResume > 0) {
      final byHash = _readMap(_resumeByHashMetaKey);
      byHash[hash] = <String, dynamic>{'positionMs': existingResume, 'updatedAt': now};
      await _writeMap(_resumeByHashMetaKey, byHash);
    }

    final allTrackPrefs = _getTrackPrefsMap();
    final byVideoTrack = allTrackPrefs[videoId];
    if (byVideoTrack is Map) {
      final byHashTracks = _readMap(_trackPrefsByHashMetaKey);
      final next = <String, dynamic>{};
      final audio = byVideoTrack['audio'];
      if (audio is String && audio.isNotEmpty) {
        next['audio'] = audio;
        next['audioUpdatedAt'] = now;
      }
      final subtitle = byVideoTrack['subtitle'];
      if (subtitle is String && subtitle.isNotEmpty) {
        next['subtitle'] = subtitle;
        next['subtitleUpdatedAt'] = now;
      }
      if (next.isNotEmpty) {
        byHashTracks[hash] = next;
        await _writeMap(_trackPrefsByHashMetaKey, byHashTracks);
      }
    }

    final recentMeta = _readMap(_recentMetaKey);
    final recentEntry = recentMeta[videoId];
    if (recentEntry is Map && recentEntry['video'] is Map) {
      final byHashRecents = _readMap(_recentByHashMetaKey);
      byHashRecents[hash] = <String, dynamic>{
        'video': Map<String, dynamic>.from(recentEntry['video'] as Map),
        'hash': hash,
        'updatedAt': _updatedAtFromEntry(recentEntry) > 0 ? _updatedAtFromEntry(recentEntry) : now,
      };
      await _writeMap(_recentByHashMetaKey, byHashRecents);
    }
  }

  static Future<void> saveNowPlayingSession(Map<String, dynamic> session) async {
    final data = Map<String, dynamic>.from(session);
    data['updatedAt'] ??= _nowMs();
    await _writeMap(_nowPlayingSessionKey, data);
  }

  static Map<String, dynamic>? getNowPlayingSession() {
    final data = _readMap(_nowPlayingSessionKey);
    if (data.isEmpty) return null;
    final age = _nowMs() - _updatedAtFromEntry(data);
    if (age > _maxNowPlayingAgeMs) return null;
    return data;
  }

  static Future<void> saveMediaInfoForHash(String hash, Map<String, dynamic> mediaJson) async {
    if (hash.isEmpty || mediaJson.isEmpty) return;
    final map = _readMap(_mediaByHashMetaKey);
    map[hash] = <String, dynamic>{'media': mediaJson, 'updatedAt': _nowMs()};
    await _writeMap(_mediaByHashMetaKey, map);
  }

  static Map<String, dynamic>? getMediaInfoForHash(String hash) {
    if (hash.isEmpty) return null;
    final map = _readMap(_mediaByHashMetaKey);
    final entry = map[hash];
    if (entry is! Map) return null;
    final media = entry['media'];
    if (media is! Map) return null;
    return Map<String, dynamic>.from(media);
  }

  // --- Resume positions (videoId -> milliseconds) ---
  static int? getResume(String videoId) {
    final direct = _resume?.get(videoId);
    if (direct != null && direct > 0) return direct;

    final hash = getVideoHash(videoId);
    if (hash == null || hash.isEmpty) return null;
    final byHash = _readMap(_resumeByHashMetaKey);
    final entry = byHash[hash];
    if (entry is! Map) return null;
    final value = entry['positionMs'];
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();
    return null;
  }

  static Map<String, int> getResumeMap() {
    final box = _resume;
    if (box == null) return <String, int>{};
    return Map<String, int>.from(box.toMap());
  }

  static Future<void> setResume(String videoId, int positionMs) async {
    final now = _nowMs();
    final meta = _readMap(_resumeMetaKey);
    final hashMeta = _readMap(_resumeByHashMetaKey);
    final hash = getVideoHash(videoId);
    if (positionMs <= 0) {
      await _resume?.delete(videoId);
      meta.remove(videoId);
      if (hash != null && hash.isNotEmpty) {
        hashMeta.remove(hash);
      }
    } else {
      await _resume?.put(videoId, positionMs);
      meta[videoId] = <String, dynamic>{'positionMs': positionMs, 'updatedAt': now};
      if (hash != null && hash.isNotEmpty) {
        hashMeta[hash] = <String, dynamic>{'positionMs': positionMs, 'updatedAt': now};
      }
    }
    await _writeMap(_resumeMetaKey, meta);
    await _writeMap(_resumeByHashMetaKey, hashMeta);
  }

  static Future<void> clearResume(String videoId) async {
    await _resume?.delete(videoId);
    final meta = _readMap(_resumeMetaKey);
    meta.remove(videoId);
    await _writeMap(_resumeMetaKey, meta);

    final hash = getVideoHash(videoId);
    if (hash != null && hash.isNotEmpty) {
      final hashMeta = _readMap(_resumeByHashMetaKey);
      hashMeta.remove(hash);
      await _writeMap(_resumeByHashMetaKey, hashMeta);
    }
  }

  static Future<void> clearAllResume() async {
    await _resume?.clear();
    await _player?.delete(_resumeMetaKey);
    await _player?.delete(_resumeByHashMetaKey);
  }

  // --- Known media durations (videoId -> milliseconds) ---

  static int? getVideoDuration(String videoId) {
    final meta = _readMap(_durationMetaKey);
    final entry = meta[videoId];
    if (entry is Map) {
      final value = entry['durationMs'];
      if (value is int && value > 0) return value;
      if (value is num && value > 0) return value.toInt();
      return null;
    }
    if (entry is int && entry > 0) return entry;
    if (entry is num && entry > 0) return entry.toInt();
    return null;
  }

  static Map<String, int> getVideoDurationMap() {
    final meta = _readMap(_durationMetaKey);
    final out = <String, int>{};
    meta.forEach((key, value) {
      if (value is Map) {
        final duration = value['durationMs'];
        if (duration is int && duration > 0) {
          out[key] = duration;
        } else if (duration is num && duration > 0) {
          out[key] = duration.toInt();
        }
        return;
      }
      if (value is int && value > 0) {
        out[key] = value;
      } else if (value is num && value > 0) {
        out[key] = value.toInt();
      }
    });
    return out;
  }

  static Future<void> setVideoDuration(String videoId, int durationMs) async {
    if (durationMs <= 0) return;
    final meta = _readMap(_durationMetaKey);
    final previous = getVideoDuration(videoId);
    if (previous == durationMs) return;
    meta[videoId] = <String, dynamic>{'durationMs': durationMs, 'updatedAt': _nowMs()};
    await _writeMap(_durationMetaKey, meta);
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
    final now = _nowMs();
    final list = getRecent().toList();
    // Remove duplicate
    list.removeWhere((v) => v.id == video.id);
    list.insert(0, video);
    if (list.length > _maxRecents) list.removeRange(_maxRecents, list.length);
    await _player?.put(_recentsKey, jsonEncode(list.map((v) => v.toJson()).toList()));

    final meta = _readMap(_recentMetaKey);
    meta[video.id] = <String, dynamic>{'video': video.toJson(), 'updatedAt': now};
    await _writeMap(_recentMetaKey, meta);

    final hash = getVideoHash(video.id);
    if (hash != null && hash.isNotEmpty) {
      final byHash = _readMap(_recentByHashMetaKey);
      byHash[hash] = <String, dynamic>{'video': video.toJson(), 'hash': hash, 'updatedAt': now};
      await _writeMap(_recentByHashMetaKey, byHash);
    }
  }

  static Future<void> clearRecent() async {
    await _player?.delete(_recentsKey);
    await _player?.delete(_recentMetaKey);
    await _player?.delete(_recentByHashMetaKey);
  }

  static Future<void> removeRecent(String videoId) async {
    final list = getRecent().toList();
    list.removeWhere((v) => v.id == videoId);
    await _player?.put(_recentsKey, jsonEncode(list.map((v) => v.toJson()).toList()));

    final meta = _readMap(_recentMetaKey);
    meta.remove(videoId);
    await _writeMap(_recentMetaKey, meta);

    final hash = getVideoHash(videoId);
    if (hash != null && hash.isNotEmpty) {
      final byHash = _readMap(_recentByHashMetaKey);
      byHash.remove(hash);
      await _writeMap(_recentByHashMetaKey, byHash);
    }
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
    if (pref is Map) {
      final value = pref['audio'];
      if (value is String && value.isNotEmpty) return value;
    }

    final hash = getVideoHash(videoId);
    if (hash != null && hash.isNotEmpty) {
      final byHash = _readMap(_trackPrefsByHashMetaKey);
      final byHashPref = byHash[hash];
      if (byHashPref is Map) {
        final value = byHashPref['audio'];
        if (value is String && value.isNotEmpty) return value;
      }
    }

    final bySeries = _readMap(_trackPrefsBySeriesMetaKey);
    final seriesPref = bySeries[_seriesTrackKey(videoId)];
    if (seriesPref is! Map) return null;
    final value = seriesPref['audio'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static String? getPreferredSubtitleTrackKey(String videoId) {
    final all = _getTrackPrefsMap();
    final pref = all[videoId];
    if (pref is Map) {
      final value = pref['subtitle'];
      if (value is String && value.isNotEmpty) return value;
    }

    final hash = getVideoHash(videoId);
    if (hash != null && hash.isNotEmpty) {
      final byHash = _readMap(_trackPrefsByHashMetaKey);
      final byHashPref = byHash[hash];
      if (byHashPref is Map) {
        final value = byHashPref['subtitle'];
        if (value is String && value.isNotEmpty) return value;
      }
    }

    final bySeries = _readMap(_trackPrefsBySeriesMetaKey);
    final seriesPref = bySeries[_seriesTrackKey(videoId)];
    if (seriesPref is! Map) return null;
    final value = seriesPref['subtitle'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static Future<void> savePreferredAudioTrackKey(String videoId, String? trackKey) async {
    final now = _nowMs();
    final all = _getTrackPrefsMap();
    final pref = (all[videoId] is Map) ? Map<String, dynamic>.from(all[videoId] as Map) : <String, dynamic>{};
    final meta = _readMap(_trackPrefsMetaKey);
    final metaPref = (meta[videoId] is Map) ? Map<String, dynamic>.from(meta[videoId] as Map) : <String, dynamic>{};
    final hashMap = _readMap(_trackPrefsByHashMetaKey);
    final hash = getVideoHash(videoId);
    final hashPref = hash != null && hashMap[hash] is Map ? Map<String, dynamic>.from(hashMap[hash] as Map) : <String, dynamic>{};
    final seriesMap = _readMap(_trackPrefsBySeriesMetaKey);
    final seriesKey = _seriesTrackKey(videoId);
    final seriesPref = seriesMap[seriesKey] is Map ? Map<String, dynamic>.from(seriesMap[seriesKey] as Map) : <String, dynamic>{};
    if (trackKey == null || trackKey.isEmpty) {
      pref.remove('audio');
      metaPref.remove('audio');
      metaPref.remove('audioUpdatedAt');
      hashPref.remove('audio');
      hashPref.remove('audioUpdatedAt');
      seriesPref.remove('audio');
      seriesPref.remove('audioUpdatedAt');
    } else {
      pref['audio'] = trackKey;
      metaPref['audio'] = trackKey;
      metaPref['audioUpdatedAt'] = now;
      hashPref['audio'] = trackKey;
      hashPref['audioUpdatedAt'] = now;
      seriesPref['audio'] = trackKey;
      seriesPref['audioUpdatedAt'] = now;
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

    if (hash != null && hash.isNotEmpty) {
      if (hashPref.isEmpty) {
        hashMap.remove(hash);
      } else {
        hashMap[hash] = hashPref;
      }
    }
    if (seriesPref.isEmpty) {
      seriesMap.remove(seriesKey);
    } else {
      seriesMap[seriesKey] = seriesPref;
    }
    await _saveTrackPrefsMap(all);
    await _writeMap(_trackPrefsMetaKey, meta);
    await _writeMap(_trackPrefsByHashMetaKey, hashMap);
    await _writeMap(_trackPrefsBySeriesMetaKey, seriesMap);
  }

  static Future<void> savePreferredSubtitleTrackKey(String videoId, String? trackKey) async {
    final now = _nowMs();
    final all = _getTrackPrefsMap();
    final pref = (all[videoId] is Map) ? Map<String, dynamic>.from(all[videoId] as Map) : <String, dynamic>{};
    final meta = _readMap(_trackPrefsMetaKey);
    final metaPref = (meta[videoId] is Map) ? Map<String, dynamic>.from(meta[videoId] as Map) : <String, dynamic>{};
    final hashMap = _readMap(_trackPrefsByHashMetaKey);
    final hash = getVideoHash(videoId);
    final hashPref = hash != null && hashMap[hash] is Map ? Map<String, dynamic>.from(hashMap[hash] as Map) : <String, dynamic>{};
    final seriesMap = _readMap(_trackPrefsBySeriesMetaKey);
    final seriesKey = _seriesTrackKey(videoId);
    final seriesPref = seriesMap[seriesKey] is Map ? Map<String, dynamic>.from(seriesMap[seriesKey] as Map) : <String, dynamic>{};
    if (trackKey == null || trackKey.isEmpty) {
      pref.remove('subtitle');
      metaPref.remove('subtitle');
      metaPref.remove('subtitleUpdatedAt');
      hashPref.remove('subtitle');
      hashPref.remove('subtitleUpdatedAt');
      seriesPref.remove('subtitle');
      seriesPref.remove('subtitleUpdatedAt');
    } else {
      pref['subtitle'] = trackKey;
      metaPref['subtitle'] = trackKey;
      metaPref['subtitleUpdatedAt'] = now;
      hashPref['subtitle'] = trackKey;
      hashPref['subtitleUpdatedAt'] = now;
      seriesPref['subtitle'] = trackKey;
      seriesPref['subtitleUpdatedAt'] = now;
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

    if (hash != null && hash.isNotEmpty) {
      if (hashPref.isEmpty) {
        hashMap.remove(hash);
      } else {
        hashMap[hash] = hashPref;
      }
    }
    if (seriesPref.isEmpty) {
      seriesMap.remove(seriesKey);
    } else {
      seriesMap[seriesKey] = seriesPref;
    }
    await _saveTrackPrefsMap(all);
    await _writeMap(_trackPrefsMetaKey, meta);
    await _writeMap(_trackPrefsByHashMetaKey, hashMap);
    await _writeMap(_trackPrefsBySeriesMetaKey, seriesMap);
  }

  static int getSubtitleDelayMs(String videoId) {
    final map = _readMap(_subtitleDelayMetaKey);
    final entry = map[videoId];
    if (entry is int) return entry;
    if (entry is num) return entry.toInt();
    return 0;
  }

  static Future<void> saveSubtitleDelayMs(String videoId, int delayMs) async {
    final map = _readMap(_subtitleDelayMetaKey);
    if (delayMs == 0) {
      map.remove(videoId);
    } else {
      map[videoId] = delayMs;
    }
    await _writeMap(_subtitleDelayMetaKey, map);
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
    return <String, dynamic>{
      'schema': 2,
      'generatedAt': _nowMs(),
      'recents': _readMap(_recentMetaKey),
      'recentByHash': _readMap(_recentByHashMetaKey),
      'resume': _readMap(_resumeMetaKey),
      'resumeByHash': _readMap(_resumeByHashMetaKey),
      'tracks': _readMap(_trackPrefsMetaKey),
      'tracksByHash': _readMap(_trackPrefsByHashMetaKey),
      'tracksBySeries': _readMap(_trackPrefsBySeriesMetaKey),
      'videoIdentity': _readMap(_videoIdentityMetaKey),
      'mediaByHash': _readMap(_mediaByHashMetaKey),
    };
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
    final incomingRecentByHash = snapshot['recentByHash'] is Map ? Map<String, dynamic>.from(snapshot['recentByHash'] as Map) : <String, dynamic>{};
    final incomingResume = snapshot['resume'] is Map ? Map<String, dynamic>.from(snapshot['resume'] as Map) : <String, dynamic>{};
    final incomingResumeByHash = snapshot['resumeByHash'] is Map ? Map<String, dynamic>.from(snapshot['resumeByHash'] as Map) : <String, dynamic>{};
    final incomingTracks = snapshot['tracks'] is Map ? Map<String, dynamic>.from(snapshot['tracks'] as Map) : <String, dynamic>{};
    final incomingTracksByHash = snapshot['tracksByHash'] is Map ? Map<String, dynamic>.from(snapshot['tracksByHash'] as Map) : <String, dynamic>{};
    final incomingTracksBySeries = snapshot['tracksBySeries'] is Map ? Map<String, dynamic>.from(snapshot['tracksBySeries'] as Map) : <String, dynamic>{};
    final incomingVideoIdentity = snapshot['videoIdentity'] is Map ? Map<String, dynamic>.from(snapshot['videoIdentity'] as Map) : <String, dynamic>{};
    final incomingMediaByHash = snapshot['mediaByHash'] is Map ? Map<String, dynamic>.from(snapshot['mediaByHash'] as Map) : <String, dynamic>{};

    List<String> videoIdsForHash(Map<String, dynamic> identityMap, String hash) {
      final out = <String>[];
      identityMap.forEach((videoId, value) {
        if (value is! Map) return;
        if (value['hash'] == hash) out.add(videoId);
      });
      return out;
    }

    // Merge video identity map first.
    final localIdentity = _readMap(_videoIdentityMetaKey);
    incomingVideoIdentity.forEach((videoId, incomingValue) {
      if (incomingValue is! Map) return;
      final incomingUpdatedAt = _updatedAtFromEntry(incomingValue);
      final localUpdatedAt = _updatedAtFromEntry(localIdentity[videoId]);
      if (incomingUpdatedAt < localUpdatedAt) return;
      localIdentity[videoId] = Map<String, dynamic>.from(incomingValue);
    });
    await _writeMap(_videoIdentityMetaKey, localIdentity);

    // Merge media info by hash.
    final localMediaByHash = _readMap(_mediaByHashMetaKey);
    incomingMediaByHash.forEach((hash, incomingValue) {
      if (incomingValue is! Map) return;
      final incomingUpdatedAt = _updatedAtFromEntry(incomingValue);
      final localUpdatedAt = _updatedAtFromEntry(localMediaByHash[hash]);
      if (incomingUpdatedAt < localUpdatedAt) return;
      localMediaByHash[hash] = Map<String, dynamic>.from(incomingValue);
    });
    await _writeMap(_mediaByHashMetaKey, localMediaByHash);

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

    // Merge recents by hash.
    final localRecentByHash = _readMap(_recentByHashMetaKey);
    incomingRecentByHash.forEach((hash, incomingValue) {
      if (incomingValue is! Map) return;
      final incomingUpdatedAt = _updatedAtFromEntry(incomingValue);
      final localUpdatedAt = _updatedAtFromEntry(localRecentByHash[hash]);
      if (incomingUpdatedAt < localUpdatedAt) return;
      localRecentByHash[hash] = Map<String, dynamic>.from(incomingValue);
    });

    final recentEntries = localRecentsMeta.entries.where((e) => e.value is Map && (e.value as Map)['video'] is Map).toList()
      ..sort((a, b) => _updatedAtFromEntry(b.value).compareTo(_updatedAtFromEntry(a.value)));
    final recentHashEntries = localRecentByHash.entries.where((e) => e.value is Map && (e.value as Map)['video'] is Map).toList()
      ..sort((a, b) => _updatedAtFromEntry(b.value).compareTo(_updatedAtFromEntry(a.value)));

    final mergedRecentVideos = <VideoItem>[];
    final trimmedRecentMeta = <String, dynamic>{};
    for (final entry in recentHashEntries) {
      final value = entry.value as Map;
      try {
        final video = VideoItem.fromJson(Map<String, dynamic>.from(value['video'] as Map));
        if (!mergedRecentVideos.any((v) => v.id == video.id)) {
          mergedRecentVideos.add(video);
          trimmedRecentMeta[video.id] = <String, dynamic>{'video': video.toJson(), 'updatedAt': _updatedAtFromEntry(value)};
        }
      } catch (_) {}
      if (mergedRecentVideos.length >= _maxRecents) break;
    }

    for (final entry in recentEntries) {
      final value = entry.value as Map;
      try {
        final video = VideoItem.fromJson(Map<String, dynamic>.from(value['video'] as Map));
        if (mergedRecentVideos.any((v) => v.id == video.id)) continue;
        mergedRecentVideos.add(video);
        trimmedRecentMeta[entry.key] = value;
      } catch (_) {}
      if (mergedRecentVideos.length >= _maxRecents) break;
    }

    await _player?.put(_recentsKey, jsonEncode(mergedRecentVideos.map((v) => v.toJson()).toList()));
    await _writeMap(_recentMetaKey, trimmedRecentMeta);
    await _writeMap(_recentByHashMetaKey, localRecentByHash);

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

    // Merge resume by hash.
    final localResumeByHash = _readMap(_resumeByHashMetaKey);
    incomingResumeByHash.forEach((hash, incomingValue) {
      if (incomingValue is! Map) return;
      final incomingUpdatedAt = _updatedAtFromEntry(incomingValue);
      final localUpdatedAt = _updatedAtFromEntry(localResumeByHash[hash]);
      if (incomingUpdatedAt < localUpdatedAt) return;
      localResumeByHash[hash] = Map<String, dynamic>.from(incomingValue);
    });

    // Propagate hash-based resume to known local video IDs.
    localResumeByHash.forEach((hash, value) {
      if (value is! Map) return;
      final position = value['positionMs'];
      final positionMs = position is num ? position.toInt() : 0;
      if (positionMs <= 0) return;
      final updatedAt = _updatedAtFromEntry(value);
      final ids = videoIdsForHash(localIdentity, hash);
      for (final videoId in ids) {
        _resume?.put(videoId, positionMs);
        localResumeMeta[videoId] = <String, dynamic>{'positionMs': positionMs, 'updatedAt': updatedAt};
      }
    });

    await _writeMap(_resumeMetaKey, localResumeMeta);
    await _writeMap(_resumeByHashMetaKey, localResumeByHash);

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

    final localTracksByHash = _readMap(_trackPrefsByHashMetaKey);
    incomingTracksByHash.forEach((hash, incomingValue) {
      if (incomingValue is! Map) return;
      final local = localTracksByHash[hash] is Map ? Map<String, dynamic>.from(localTracksByHash[hash] as Map) : <String, dynamic>{};

      final incomingAudioAt = _fieldUpdatedAtFromEntry(incomingValue, 'audioUpdatedAt');
      final localAudioAt = _fieldUpdatedAtFromEntry(local, 'audioUpdatedAt');
      if (incomingAudioAt >= localAudioAt && incomingAudioAt > 0) {
        final incomingAudio = incomingValue['audio'];
        if (incomingAudio is String && incomingAudio.isNotEmpty) {
          local['audio'] = incomingAudio;
          local['audioUpdatedAt'] = incomingAudioAt;
        } else {
          local.remove('audio');
          local.remove('audioUpdatedAt');
        }
      }

      final incomingSubtitleAt = _fieldUpdatedAtFromEntry(incomingValue, 'subtitleUpdatedAt');
      final localSubtitleAt = _fieldUpdatedAtFromEntry(local, 'subtitleUpdatedAt');
      if (incomingSubtitleAt >= localSubtitleAt && incomingSubtitleAt > 0) {
        final incomingSubtitle = incomingValue['subtitle'];
        if (incomingSubtitle is String && incomingSubtitle.isNotEmpty) {
          local['subtitle'] = incomingSubtitle;
          local['subtitleUpdatedAt'] = incomingSubtitleAt;
        } else {
          local.remove('subtitle');
          local.remove('subtitleUpdatedAt');
        }
      }

      if (local.isEmpty) {
        localTracksByHash.remove(hash);
      } else {
        localTracksByHash[hash] = local;
      }
    });

    final localTracksBySeries = _readMap(_trackPrefsBySeriesMetaKey);
    incomingTracksBySeries.forEach((seriesKey, incomingValue) {
      if (incomingValue is! Map) return;
      final local = localTracksBySeries[seriesKey] is Map ? Map<String, dynamic>.from(localTracksBySeries[seriesKey] as Map) : <String, dynamic>{};

      final incomingAudioAt = _fieldUpdatedAtFromEntry(incomingValue, 'audioUpdatedAt');
      final localAudioAt = _fieldUpdatedAtFromEntry(local, 'audioUpdatedAt');
      if (incomingAudioAt >= localAudioAt && incomingAudioAt > 0) {
        final incomingAudio = incomingValue['audio'];
        if (incomingAudio is String && incomingAudio.isNotEmpty) {
          local['audio'] = incomingAudio;
          local['audioUpdatedAt'] = incomingAudioAt;
        } else {
          local.remove('audio');
          local.remove('audioUpdatedAt');
        }
      }

      final incomingSubtitleAt = _fieldUpdatedAtFromEntry(incomingValue, 'subtitleUpdatedAt');
      final localSubtitleAt = _fieldUpdatedAtFromEntry(local, 'subtitleUpdatedAt');
      if (incomingSubtitleAt >= localSubtitleAt && incomingSubtitleAt > 0) {
        final incomingSubtitle = incomingValue['subtitle'];
        if (incomingSubtitle is String && incomingSubtitle.isNotEmpty) {
          local['subtitle'] = incomingSubtitle;
          local['subtitleUpdatedAt'] = incomingSubtitleAt;
        } else {
          local.remove('subtitle');
          local.remove('subtitleUpdatedAt');
        }
      }

      if (local.isEmpty) {
        localTracksBySeries.remove(seriesKey);
      } else {
        localTracksBySeries[seriesKey] = local;
      }
    });

    // Propagate hash-based track preferences to known local video IDs.
    localTracksByHash.forEach((hash, value) {
      if (value is! Map) return;
      final ids = videoIdsForHash(localIdentity, hash);
      for (final videoId in ids) {
        final pref = (localTrackPrefs[videoId] is Map) ? Map<String, dynamic>.from(localTrackPrefs[videoId] as Map) : <String, dynamic>{};
        final meta = (localTrackMeta[videoId] is Map) ? Map<String, dynamic>.from(localTrackMeta[videoId] as Map) : <String, dynamic>{};

        final audio = value['audio'];
        if (audio is String && audio.isNotEmpty) {
          pref['audio'] = audio;
          meta['audio'] = audio;
          meta['audioUpdatedAt'] = _fieldUpdatedAtFromEntry(value, 'audioUpdatedAt');
        }

        final subtitle = value['subtitle'];
        if (subtitle is String && subtitle.isNotEmpty) {
          pref['subtitle'] = subtitle;
          meta['subtitle'] = subtitle;
          meta['subtitleUpdatedAt'] = _fieldUpdatedAtFromEntry(value, 'subtitleUpdatedAt');
        }

        if (pref.isEmpty) {
          localTrackPrefs.remove(videoId);
        } else {
          localTrackPrefs[videoId] = pref;
        }

        if (meta.isEmpty) {
          localTrackMeta.remove(videoId);
        } else {
          localTrackMeta[videoId] = meta;
        }
      }
    });

    // Propagate series-based track preferences to known local video IDs.
    localTracksBySeries.forEach((seriesKey, value) {
      if (value is! Map) return;
      localIdentity.forEach((videoId, _) {
        if (_seriesTrackKey(videoId) != seriesKey) return;

        final pref = (localTrackPrefs[videoId] is Map) ? Map<String, dynamic>.from(localTrackPrefs[videoId] as Map) : <String, dynamic>{};
        final meta = (localTrackMeta[videoId] is Map) ? Map<String, dynamic>.from(localTrackMeta[videoId] as Map) : <String, dynamic>{};

        final audio = value['audio'];
        if (audio is String && audio.isNotEmpty) {
          pref['audio'] = audio;
          meta['audio'] = audio;
          meta['audioUpdatedAt'] = _fieldUpdatedAtFromEntry(value, 'audioUpdatedAt');
        }

        final subtitle = value['subtitle'];
        if (subtitle is String && subtitle.isNotEmpty) {
          pref['subtitle'] = subtitle;
          meta['subtitle'] = subtitle;
          meta['subtitleUpdatedAt'] = _fieldUpdatedAtFromEntry(value, 'subtitleUpdatedAt');
        }

        if (pref.isEmpty) {
          localTrackPrefs.remove(videoId);
        } else {
          localTrackPrefs[videoId] = pref;
        }

        if (meta.isEmpty) {
          localTrackMeta.remove(videoId);
        } else {
          localTrackMeta[videoId] = meta;
        }
      });
    });

    await _saveTrackPrefsMap(localTrackPrefs);
    await _writeMap(_trackPrefsMetaKey, localTrackMeta);
    await _writeMap(_trackPrefsByHashMetaKey, localTracksByHash);
    await _writeMap(_trackPrefsBySeriesMetaKey, localTracksBySeries);
  }

  static String _seriesTrackKey(String videoId) {
    final normalized = videoId.trim();
    if (normalized.isEmpty) return '';

    String candidate = normalized;
    if (normalized.startsWith('smb://') || normalized.startsWith('http://') || normalized.startsWith('https://') || normalized.startsWith('file://')) {
      try {
        candidate = Uri.decodeComponent(Uri.parse(normalized).path);
      } catch (_) {
        candidate = normalized;
      }
    }

    final parsed = VideoNameParser.parse(candidate);
    final key = parsed.cleanName.trim().toLowerCase();
    return key.isEmpty ? candidate.trim().toLowerCase() : key;
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

  static Map<String, String?> getRecentPosterPathMap(Iterable<VideoItem> videos) {
    final byVideo = _readStringMap(_recentPosterByVideoKey);
    final bySeries = _readStringMap(_recentPosterBySeriesKey);
    final out = <String, String?>{};

    for (final video in videos) {
      String? resolved;

      final direct = byVideo[video.id];
      if (direct != null && direct.isNotEmpty && File(direct).existsSync()) {
        resolved = direct;
      } else {
        final seriesPath = bySeries[_seriesCacheKey(video)];
        if (seriesPath != null && seriesPath.isNotEmpty && File(seriesPath).existsSync()) {
          resolved = seriesPath;
        }
      }

      out[video.id] = resolved;
    }

    return out;
  }

  // --- Last opened file directory ---
  static String? getLastOpenedDirectory() {
    final value = _player?.get(_lastOpenedDirectoryKey);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Future<void> setLastOpenedDirectory(String? directory) async {
    if (directory == null || directory.isEmpty) {
      await _player?.delete(_lastOpenedDirectoryKey);
      return;
    }
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
