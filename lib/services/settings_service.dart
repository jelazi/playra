import 'package:hive_flutter/hive_flutter.dart';

import '../models/app_settings.dart';

class SettingsService {
  static const String _boxName = 'settings';
  static Box<AppSettings>? _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(AppSettingsAdapter());
    _box = await Hive.openBox<AppSettings>(_boxName);
  }

  static AppSettings getSettings() {
    return _box?.get('app_settings', defaultValue: AppSettings()) ?? AppSettings();
  }

  static Future<void> saveSettings(AppSettings settings) async {
    await _box?.put('app_settings', settings);
  }

  static Future<void> updateUsername(String? username) async {
    final settings = getSettings();
    await saveSettings(settings.copyWith(username: username));
  }

  static Future<void> updateSessionCookie(String? sessionCookie) async {
    final settings = getSettings();
    await saveSettings(settings.copyWith(sessionCookie: sessionCookie));
  }

  static Future<void> updateLanguage(String language) async {
    final settings = getSettings();
    await saveSettings(settings.copyWith(language: language));
  }

  static Future<void> updateLastVideoPath(String? path) async {
    final settings = getSettings();
    await saveSettings(settings.copyWith(lastVideoPath: path));
  }

  static Future<void> updatePreferredSubtitleLanguage(String language) async {
    final settings = getSettings();
    await saveSettings(settings.copyWith(preferredSubtitleLanguage: language));
  }

  static Future<void> updatePassword(String? password) async {
    final settings = getSettings();
    await saveSettings(settings.copyWith(password: password));
  }

  /// Save login credentials for auto-login
  static Future<void> saveCredentials(String username, String password) async {
    final settings = getSettings();
    await saveSettings(settings.copyWith(username: username, password: password));
  }

  /// Clear login credentials (on logout)
  static Future<void> clearCredentials() async {
    final settings = getSettings();
    // Clear username, password and sessionCookie, keep other settings
    final newSettings = AppSettings(
      language: settings.language,
      lastVideoPath: settings.lastVideoPath,
      preferredSubtitleLanguage: settings.preferredSubtitleLanguage,
      downloadedVideoPaths: settings.downloadedVideoPaths,
    );
    await saveSettings(newSettings);
  }

  /// Mark video as having downloaded subtitles
  static Future<void> markVideoWithSubtitles(String videoPath) async {
    final settings = getSettings();
    final paths = List<String>.from(settings.downloadedVideoPaths);
    if (!paths.contains(videoPath)) {
      paths.add(videoPath);
      await saveSettings(settings.copyWith(downloadedVideoPaths: paths));
    }
  }

  /// Check if video has downloaded subtitles recorded in settings
  static bool hasDownloadedSubtitles(String videoPath) {
    final settings = getSettings();
    return settings.downloadedVideoPaths.contains(videoPath);
  }

  /// Remove video from downloaded subtitles list
  static Future<void> removeVideoFromDownloaded(String videoPath) async {
    final settings = getSettings();
    final paths = List<String>.from(settings.downloadedVideoPaths);
    paths.remove(videoPath);
    await saveSettings(settings.copyWith(downloadedVideoPaths: paths));
  }

  /// Get all video paths with downloaded subtitles
  static List<String> getVideosWithDownloadedSubtitles() {
    final settings = getSettings();
    return settings.downloadedVideoPaths;
  }

  static Future<void> clear() async {
    await _box?.clear();
  }

  static Future<void> close() async {
    await _box?.close();
  }
}
