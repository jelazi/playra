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
    // Clear username, password and sessionCookie
    final newSettings = AppSettings(language: settings.language, lastVideoPath: settings.lastVideoPath, preferredSubtitleLanguage: settings.preferredSubtitleLanguage);
    await saveSettings(newSettings);
  }

  static Future<void> clear() async {
    await _box?.clear();
  }

  static Future<void> close() async {
    await _box?.close();
  }
}
