import 'dart:io';

import 'package:path/path.dart' as path;

// Quick test script to verify subtitle indicator functionality
void main() async {
  print('🧪 Testing Subtitle Indicators Feature');
  print('=========================================\n');

  // Test 1: Create a test video file and subtitle file
  final testDir = Directory('/tmp/test_video_lib');
  if (await testDir.exists()) {
    await testDir.delete(recursive: true);
  }
  await testDir.create();

  print('✅ Test directory created: ${testDir.path}');

  // Create test video file
  final videoFile = File(path.join(testDir.path, 'test_movie.mp4'));
  await videoFile.writeAsString('dummy video content');
  print('✅ Test video file created: ${videoFile.path}');

  // Create corresponding subtitle file
  final subtitleFile = File(path.join(testDir.path, 'test_movie.srt'));
  await subtitleFile.writeAsString('''1
00:00:01,000 --> 00:00:04,000
Test subtitle line 1

2
00:00:05,000 --> 00:00:08,000
Test subtitle line 2
''');
  print('✅ Test subtitle file created: ${subtitleFile.path}');

  // Test subtitle detection
  print('\n🔍 Testing subtitle file detection...');

  final videoName = path.basenameWithoutExtension(videoFile.path);
  final videoDir = path.dirname(videoFile.path);
  final subtitleExtensions = ['.srt', '.sub', '.vtt', '.ass', '.ssa'];

  List<File> foundSubtitles = [];

  for (final ext in subtitleExtensions) {
    final subtitlePath = path.join(videoDir, '$videoName$ext');
    final subtitleFile = File(subtitlePath);

    if (await subtitleFile.exists()) {
      foundSubtitles.add(subtitleFile);
      print('  ✅ Found subtitle: ${path.basename(subtitlePath)}');
    }
  }

  print('\n📊 Results:');
  print('  Video file: ${path.basename(videoFile.path)}');
  print('  Found ${foundSubtitles.length} subtitle files');
  print('  Has subtitles: ${foundSubtitles.isNotEmpty}');

  if (foundSubtitles.isNotEmpty) {
    print('  Subtitle indicators should show:');
    print('    🟢 Green circle (has physical subtitles)');
    print('    📁 Folder icon');
  }

  // Test 2: Test without subtitle file
  print('\n🔍 Testing video without subtitles...');

  final videoFile2 = File(path.join(testDir.path, 'movie_without_subs.mkv'));
  await videoFile2.writeAsString('dummy video content 2');

  final videoName2 = path.basenameWithoutExtension(videoFile2.path);
  final videoDir2 = path.dirname(videoFile2.path);

  List<File> foundSubtitles2 = [];

  for (final ext in subtitleExtensions) {
    final subtitlePath = path.join(videoDir2, '$videoName2$ext');
    final subtitleFile = File(subtitlePath);

    if (await subtitleFile.exists()) {
      foundSubtitles2.add(subtitleFile);
    }
  }

  print('  Video file: ${path.basename(videoFile2.path)}');
  print('  Found ${foundSubtitles2.length} subtitle files');
  print('  Has subtitles: ${foundSubtitles2.isNotEmpty}');

  if (foundSubtitles2.isEmpty) {
    print('  No subtitle indicators should show (default state)');
  }

  // Cleanup
  print('\n🧹 Cleaning up test files...');
  await testDir.delete(recursive: true);
  print('✅ Cleanup complete');

  print('\n🎉 Subtitle indicator test completed!');
  print('\nTo test in the app:');
  print('1. Go to Video Library tab');
  print('2. Add some video files using the + button');
  print('3. Download subtitles for some videos');
  print('4. Check that videos with subtitles show green indicators');
  print('5. Check that videos without subtitles show no indicators');
}
