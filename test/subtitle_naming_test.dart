import 'package:flutter_test/flutter_test.dart';
import 'package:titulky_com/models/subtitle.dart';

// Test to verify that original and alternative subtitles have consistent naming
void main() {
  group('Subtitle Naming Consistency Tests', () {
    test('Original subtitle title format', () {
      final originalSubtitle = Subtitle(
        id: '12345',
        title: 'Forrest Gump (1994) 1080p BluRay x264-SPARKS',
        language: 'cs',
        format: 'srt',
        downloadUrl: 'https://premium.titulky.com/index.php?action=detail&id=12345',
      );

      expect(originalSubtitle.title, 'Forrest Gump (1994) 1080p BluRay x264-SPARKS');
      expect(originalSubtitle.title.isNotEmpty, true);
    });

    test('Alternative subtitle title format', () {
      final alternativeSubtitle = Subtitle(
        id: '12346',
        title: 'Forrest.Gump.1994.720p.HDTV.XviD-GROUP',
        language: 'cs',
        format: 'srt',
        downloadUrl: 'https://premium.titulky.com/index.php?action=detail&id=12346',
        uploader: 'user123',
        details: '720p.HDTV.XviD-GROUP',
      );

      expect(alternativeSubtitle.title, 'Forrest.Gump.1994.720p.HDTV.XviD-GROUP');
      expect(alternativeSubtitle.title.isNotEmpty, true);
    });

    test('Both subtitles use same title field structure', () {
      final original = Subtitle(id: '1', title: 'Movie Title Original', language: 'cs', format: 'srt', downloadUrl: 'test1');

      final alternative = Subtitle(id: '2', title: 'Movie Title Alternative', language: 'cs', format: 'srt', downloadUrl: 'test2', uploader: 'user', details: 'details');

      // Both should have the same type and structure for title
      expect(original.title.runtimeType, alternative.title.runtimeType);
      expect(original.title.isNotEmpty, true);
      expect(alternative.title.isNotEmpty, true);
    });
  });
}
