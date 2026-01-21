import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class AppConfig {
  static const String _configFileName = 'titulky_config.json';

  String? username;
  String? sessionCookie;

  AppConfig({this.username, this.sessionCookie});

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(username: json['username'], sessionCookie: json['sessionCookie']);
  }

  Map<String, dynamic> toJson() {
    return {'username': username, 'sessionCookie': sessionCookie};
  }

  /// Načtení konfigurace ze souboru
  static Future<AppConfig> load() async {
    try {
      final configFile = await _getConfigFile();
      if (await configFile.exists()) {
        final contents = await configFile.readAsString();
        final json = jsonDecode(contents) as Map<String, dynamic>;
        return AppConfig.fromJson(json);
      }
    } catch (e) {
      print('Error loading config: $e');
    }
    return AppConfig();
  }

  /// Uložení konfigurace do souboru
  Future<void> save() async {
    try {
      final configFile = await _getConfigFile();
      final json = jsonEncode(toJson());
      await configFile.writeAsString(json);
    } catch (e) {
      print('Error saving config: $e');
    }
  }

  /// Smazání konfigurace
  static Future<void> clear() async {
    try {
      final configFile = await _getConfigFile();
      if (await configFile.exists()) {
        await configFile.delete();
      }
    } catch (e) {
      print('Error clearing config: $e');
    }
  }

  static Future<File> _getConfigFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, _configFileName));
  }
}
