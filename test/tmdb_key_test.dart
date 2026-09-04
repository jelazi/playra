import 'package:flutter_test/flutter_test.dart';
import 'package:playra/services/tmdb_service.dart';

void main() {
  group('TmdbService.isWellFormedKey', () {
    test('accepts a 32-character hex key', () {
      expect(TmdbService.isWellFormedKey('a1b2c3d4e5f60718293a4b5c6d7e8f90'), isTrue);
    });

    test('accepts uppercase hex', () {
      expect(TmdbService.isWellFormedKey('A1B2C3D4E5F60718293A4B5C6D7E8F90'), isTrue);
    });

    test('ignores surrounding whitespace from a paste', () {
      expect(TmdbService.isWellFormedKey('  a1b2c3d4e5f60718293a4b5c6d7e8f90\n'), isTrue);
    });

    test('rejects an empty key', () {
      expect(TmdbService.isWellFormedKey(''), isFalse);
    });

    test('rejects a key that is too short or too long', () {
      expect(TmdbService.isWellFormedKey('a1b2c3d4'), isFalse);
      expect(TmdbService.isWellFormedKey('a1b2c3d4e5f60718293a4b5c6d7e8f901'), isFalse);
    });

    test('rejects non-hex characters', () {
      expect(TmdbService.isWellFormedKey('z1b2c3d4e5f60718293a4b5c6d7e8f90'), isFalse);
      expect(TmdbService.isWellFormedKey('a1b2c3d4-e5f6-0718-293a-4b5c6d7e8f'), isFalse);
    });
  });

  test('isKeyFixedAtBuildTime reflects the TMDB_API_KEY define', () {
    const define = String.fromEnvironment('TMDB_API_KEY');
    expect(TmdbService.isKeyFixedAtBuildTime, define.trim().isNotEmpty);
  });
}
