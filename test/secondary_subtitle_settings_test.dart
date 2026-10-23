import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:playra/models/player_settings.dart';
import 'package:playra/models/subtitle_style_settings.dart';
import 'package:playra/services/playra_storage.dart';

void main() {
  test('the secondary subtitle size survives a round trip and defaults for older settings', () {
    final style = const SubtitleStyleSettings().copyWith(secondaryFontScale: 0.45);
    expect(SubtitleStyleSettings.decode(style.encode()).secondaryFontScale, 0.45);
    expect(SubtitleStyleSettings.fromJson(const {'fontSize': 28}).secondaryFontScale, 0.6);
  });

  test('position, colour, alignment and sideways shift survive a round trip and fall back when unknown', () {
    final style = const SubtitleStyleSettings().copyWith(
      secondaryPosition: 'top',
      secondaryTextColor: 0xFF00FFFF,
      horizontalAlign: 'left',
      horizontalOffset: -0.2,
    );
    final decoded = SubtitleStyleSettings.decode(style.encode());
    expect(decoded.secondaryPosition, 'top');
    expect(decoded.secondaryTextColor, 0xFF00FFFF);
    expect(decoded.horizontalAlign, 'left');
    expect(decoded.horizontalOffset, -0.2);

    final fallback = SubtitleStyleSettings.fromJson(const {'secondaryPosition': 'middle', 'horizontalAlign': 'justify', 'horizontalOffset': 3});
    expect(fallback.secondaryPosition, 'below');
    expect(fallback.horizontalAlign, 'center');
    expect(fallback.horizontalOffset, 0.4);
  });

  test('the default secondary subtitle language survives a round trip and defaults to none', () {
    final settings = const PlayerSettings().copyWith(defaultSecondarySubtitleLanguage: 'en');
    expect(PlayerSettings.decode(settings.encode()).defaultSecondarySubtitleLanguage, 'en');
    expect(PlayerSettings.fromJson(const {}).defaultSecondarySubtitleLanguage, '');
  });

  group('secondary subtitle choice per video', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('playra_secondary_subtitle_test');
      Hive.init(tempDir.path);
      await PlayraStorage.init();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('is stored per video and removed with null', () async {
      await PlayraStorage.saveSecondarySubtitleKey('a.mkv', 'english|eng');
      await PlayraStorage.saveSecondarySubtitleKey('b.mkv', PlayraStorage.secondarySubtitleOff);

      expect(PlayraStorage.getSecondarySubtitleKey('a.mkv'), 'english|eng');
      expect(PlayraStorage.getSecondarySubtitleKey('b.mkv'), PlayraStorage.secondarySubtitleOff);
      expect(PlayraStorage.getSecondarySubtitleKey('c.mkv'), isNull);

      await PlayraStorage.saveSecondarySubtitleKey('a.mkv', null);
      expect(PlayraStorage.getSecondarySubtitleKey('a.mkv'), isNull);
    });
  });
}
