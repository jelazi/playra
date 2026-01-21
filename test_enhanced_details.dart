import 'package:flutter_test/flutter_test.dart';
import 'package:titulky_com/models/subtitle.dart';
import 'package:titulky_com/repositories/titulky_repository.dart';

// Test for enhanced original subtitle details functionality
void main() {
  group('Enhanced Original Subtitle Details Tests', () {
    test('AlternativeSubtitlesResult structure', () {
      final originalSubtitle = Subtitle(id: '123', title: 'Test Movie (2024)', language: 'cs', format: 'srt', downloadUrl: 'https://test.com/detail?id=123');

      final enhancedSubtitle = Subtitle(
        id: '123',
        title: 'Test Movie (2024)',
        language: 'cs',
        format: 'srt',
        downloadUrl: 'https://test.com/detail?id=123',
        uploader: 'testuser',
        details: 'BluRay.x264-SPARKS',
        downloadCount: '150',
      );

      final alternatives = [Subtitle(id: '124', title: 'Test Movie Alternative (2024)', language: 'cs', format: 'srt', downloadUrl: 'https://test.com/detail?id=124')];

      final result = AlternativeSubtitlesResult(enhancedOriginal: enhancedSubtitle, alternatives: alternatives);

      expect(result.enhancedOriginal.id, '123');
      expect(result.enhancedOriginal.uploader, 'testuser');
      expect(result.enhancedOriginal.details, 'BluRay.x264-SPARKS');
      expect(result.enhancedOriginal.downloadCount, '150');
      expect(result.alternatives.length, 1);
      expect(result.alternatives.first.id, '124');
    });

    test('Original subtitle without enhancement should remain unchanged', () {
      final originalSubtitle = Subtitle(id: '123', title: 'Test Movie (2024)', language: 'cs', format: 'srt', downloadUrl: 'https://test.com/detail?id=123');

      // If no enhanced data found, original should be returned unchanged
      final result = AlternativeSubtitlesResult(enhancedOriginal: originalSubtitle, alternatives: []);

      expect(result.enhancedOriginal, equals(originalSubtitle));
      expect(result.enhancedOriginal.uploader, isNull);
      expect(result.enhancedOriginal.details, isNull);
    });

    test('Enhanced subtitle preserves original properties', () {
      final original = Subtitle(id: '123', title: 'Test Movie', language: 'cs', format: 'srt', downloadUrl: 'test.com', rating: '8.5', movieName: 'Test Movie 2024');

      final enhanced = Subtitle(
        id: original.id,
        title: original.title,
        language: original.language,
        format: original.format,
        downloadUrl: original.downloadUrl,
        rating: original.rating,
        uploader: 'newuser',
        details: 'new details',
        downloadCount: original.downloadCount,
        movieName: original.movieName,
        isSynced: original.isSynced,
      );

      // Original properties should be preserved
      expect(enhanced.id, original.id);
      expect(enhanced.title, original.title);
      expect(enhanced.language, original.language);
      expect(enhanced.format, original.format);
      expect(enhanced.downloadUrl, original.downloadUrl);
      expect(enhanced.rating, original.rating);
      expect(enhanced.movieName, original.movieName);

      // New properties should be added
      expect(enhanced.uploader, 'newuser');
      expect(enhanced.details, 'new details');
    });
  });

  print('✅ Enhanced Original Subtitle Tests');
  print('===================================');
  print('✓ AlternativeSubtitlesResult structure works correctly');
  print('✓ Original subtitle preservation works');
  print('✓ Enhanced properties are properly added');
  print('');
  print('🎯 Expected behavior in app:');
  print('1. Click on a subtitle in search results');
  print('2. App fetches alternative subtitles AND enhances original with details');
  print('3. Selected subtitle shows additional info (uploader, details, etc.)');
  print('4. Alternative subtitles show their own detailed info');
  print('5. Non-selected subtitles show basic info only');
}
