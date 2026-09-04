import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Encrypted Hive box holding user-supplied credentials: the TMDB API key and
/// the password of every saved server connection.
///
/// The AES key is kept in a separate owner-only file rather than inside the
/// box, so a Hive file that leaks through a backup, a synced folder or a
/// shared support bundle cannot be read on its own.
class SecretStore {
  static const String _boxName = 'playra_secrets';
  static const String _keyFileName = '.playra_secret_key';
  static const String _tmdbEntry = 'tmdb_api_key';
  static const String _serverPasswordPrefix = 'server_password:';

  static Box<String>? _box;

  /// [keyDirectory] overrides where the encryption key file lives; tests pass a
  /// temporary directory because path_provider is unavailable to them.
  static Future<void> init({Directory? keyDirectory}) async {
    final cipher = HiveAesCipher(await _loadOrCreateEncryptionKey(keyDirectory));
    try {
      _box = await Hive.openBox<String>(_boxName, encryptionCipher: cipher);
    } catch (e) {
      debugPrint('SecretStore: box unreadable ($e), starting a fresh one');
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox<String>(_boxName, encryptionCipher: cipher);
    }
  }

  static String get tmdbApiKey => _box?.get(_tmdbEntry)?.trim() ?? '';

  static Future<void> setTmdbApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _box?.delete(_tmdbEntry);
    } else {
      await _box?.put(_tmdbEntry, trimmed);
    }
  }

  /// Password of the saved server [serverId], or null when none is stored.
  static String? serverPassword(String serverId) {
    final stored = _box?.get('$_serverPasswordPrefix$serverId');
    return (stored == null || stored.isEmpty) ? null : stored;
  }

  static Future<void> setServerPassword(String serverId, String? password) async {
    if (password == null || password.isEmpty) {
      await _box?.delete('$_serverPasswordPrefix$serverId');
    } else {
      await _box?.put('$_serverPasswordPrefix$serverId', password);
    }
  }

  static Future<List<int>> _loadOrCreateEncryptionKey(Directory? override) async {
    final dir = override ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, _keyFileName));

    if (await file.exists()) {
      try {
        final stored = base64Decode((await file.readAsString()).trim());
        if (stored.length == 32) return stored;
        debugPrint('SecretStore: key file has unexpected length, regenerating');
      } catch (e) {
        debugPrint('SecretStore: key file unreadable ($e), regenerating');
      }
    }

    final key = Hive.generateSecureKey();
    // Restrict the empty file before it holds anything, so the key is never
    // world-readable even briefly.
    await file.create(recursive: true);
    await _restrictToOwner(file);
    await file.writeAsString(base64Encode(key), flush: true);
    return key;
  }

  /// Dart has no chmod, and on desktop the application-support directory is
  /// world-readable, so shell out to keep the key file owner-only.
  static Future<void> _restrictToOwner(File file) async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    try {
      await Process.run('chmod', ['600', file.path]);
    } catch (e) {
      debugPrint('SecretStore: could not restrict key file permissions ($e)');
    }
  }
}
