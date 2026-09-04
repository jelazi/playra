import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:playra/models/server_connection.dart';
import 'package:playra/services/playra_storage.dart';
import 'package:playra/services/secret_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('playra_secret_store_test');
    Hive.init(tempDir.path);
    await PlayraStorage.init();
    await SecretStore.init(keyDirectory: tempDir);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('SecretStore', () {
    test('stores and returns the TMDB key', () async {
      expect(SecretStore.tmdbApiKey, isEmpty);
      await SecretStore.setTmdbApiKey('a1b2c3d4e5f60718293a4b5c6d7e8f90');
      expect(SecretStore.tmdbApiKey, 'a1b2c3d4e5f60718293a4b5c6d7e8f90');
    });

    test('trims the key and treats an empty value as a removal', () async {
      await SecretStore.setTmdbApiKey('  a1b2c3d4e5f60718293a4b5c6d7e8f90  ');
      expect(SecretStore.tmdbApiKey, 'a1b2c3d4e5f60718293a4b5c6d7e8f90');
      await SecretStore.setTmdbApiKey('');
      expect(SecretStore.tmdbApiKey, isEmpty);
    });

    test('keeps server passwords apart per server id', () async {
      await SecretStore.setServerPassword('nas-1', 'hunter2');
      await SecretStore.setServerPassword('nas-2', 'other-secret');

      expect(SecretStore.serverPassword('nas-1'), 'hunter2');
      expect(SecretStore.serverPassword('nas-2'), 'other-secret');
      expect(SecretStore.serverPassword('nas-3'), isNull);

      await SecretStore.setServerPassword('nas-1', null);
      expect(SecretStore.serverPassword('nas-1'), isNull);
      expect(SecretStore.serverPassword('nas-2'), 'other-secret');
    });

    test('writes the key file owner-only', () async {
      final keyFile = File('${tempDir.path}/.playra_secret_key');
      expect(await keyFile.exists(), isTrue);

      if (Platform.isMacOS || Platform.isLinux) {
        // FileStat.mode rather than `stat`, whose flags differ between BSD and GNU.
        final permissions = (await keyFile.stat()).mode & 0x1FF;
        expect(permissions.toRadixString(8).padLeft(3, '0'), '600');
      }
    });

    test('does not leave secrets readable in the box file on disk', () async {
      await SecretStore.setTmdbApiKey('a1b2c3d4e5f60718293a4b5c6d7e8f90');
      await SecretStore.setServerPassword('nas-1', 'plaintext-canary');
      await Hive.box<String>('playra_secrets').flush();

      final boxFile = File('${tempDir.path}/playra_secrets.hive');
      expect(await boxFile.exists(), isTrue);
      final bytes = await boxFile.readAsBytes();
      final asText = String.fromCharCodes(bytes);
      expect(asText, isNot(contains('plaintext-canary')));
      expect(asText, isNot(contains('a1b2c3d4e5f60718293a4b5c6d7e8f90')));
    });
  });

  group('PlayraStorage server credentials', () {
    const server = ServerConnection(
      id: 'nas-1',
      name: 'NAS',
      type: ServerType.smb,
      host: '192.168.1.10',
      share: 'media',
      username: 'jelazi',
      password: 'plaintext-canary',
    );

    test('saveServer keeps the password out of the plaintext box', () async {
      await PlayraStorage.saveServer(server);

      final raw = Hive.box<String>('playra_servers').get('nas-1')!;
      expect(raw, isNot(contains('plaintext-canary')));
      expect(raw, contains('192.168.1.10'));
      expect(SecretStore.serverPassword('nas-1'), 'plaintext-canary');
    });

    test('getServers merges the password back in', () async {
      await PlayraStorage.saveServer(server);

      final loaded = PlayraStorage.getServers().single;
      expect(loaded.id, 'nas-1');
      expect(loaded.host, '192.168.1.10');
      expect(loaded.username, 'jelazi');
      expect(loaded.password, 'plaintext-canary');
    });

    test('deleteServer removes the stored password too', () async {
      await PlayraStorage.saveServer(server);
      await PlayraStorage.deleteServer('nas-1');

      expect(PlayraStorage.getServers(), isEmpty);
      expect(SecretStore.serverPassword('nas-1'), isNull);
    });

    test('migrates a password embedded by an older build', () async {
      // Exactly what the previous version wrote: the full JSON, password included.
      await Hive.box<String>('playra_servers').put('nas-1', server.encode());
      expect(Hive.box<String>('playra_servers').get('nas-1'), contains('plaintext-canary'));

      await PlayraStorage.migrateSecretsToSecretStore();

      expect(Hive.box<String>('playra_servers').get('nas-1'), isNot(contains('plaintext-canary')));
      expect(SecretStore.serverPassword('nas-1'), 'plaintext-canary');
      expect(PlayraStorage.getServers().single.password, 'plaintext-canary');
    });

    test('migration leaves an already-migrated entry alone', () async {
      await PlayraStorage.saveServer(server);
      await PlayraStorage.migrateSecretsToSecretStore();

      expect(SecretStore.serverPassword('nas-1'), 'plaintext-canary');
      expect(PlayraStorage.getServers().single.password, 'plaintext-canary');
    });

    test('a server saved without a password stays without one', () async {
      await PlayraStorage.saveServer(server.withoutPassword());

      expect(SecretStore.serverPassword('nas-1'), isNull);
      expect(PlayraStorage.getServers().single.password, isNull);
    });
  });
}
