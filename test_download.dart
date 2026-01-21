import 'dart:io';

import 'package:titulky_com/repositories/titulky_repository.dart';

void main() async {
  print('🧪 Testing subtitle download functionality...\n');

  final repository = TitulkyRepository();

  // Přihlášení
  print('1️⃣  Logging in...');
  final username = 'jelazi';
  final password = 'Honzicek1';

  final loginSuccess = await repository.login(username, password);
  if (!loginSuccess) {
    print('❌ Login failed! Check credentials.');
    return;
  }
  print('✅ Login successful!\n');

  // Vyhledání titulků pro "Matrix"
  print('2️⃣  Searching for "Matrix" subtitles...');
  final subtitles = await repository.searchSubtitles('matrix');

  if (subtitles.isEmpty) {
    print('❌ No subtitles found for "matrix"!');
    return;
  }

  print('✅ Found ${subtitles.length} subtitles\n');

  // Zobrazit prvních 5
  print('📋 First 5 results:');
  for (var i = 0; i < (subtitles.length > 5 ? 5 : subtitles.length); i++) {
    final sub = subtitles[i];
    print('  ${i + 1}. ${sub.title}');
    print('     Format: ${sub.format} | Language: ${sub.language}');
    print('     Movie: ${sub.movieName ?? "N/A"}');
    print('     Downloads: ${sub.downloadCount ?? "N/A"}');
    print('     Uploader: ${sub.uploader ?? "N/A"}');
    print('     URL: ${sub.downloadUrl}');
    print('');
  }

  // Zkusit stáhnout první titulek
  print('3️⃣  Testing download of first subtitle...');
  final firstSubtitle = subtitles[0];

  // Vytvořit testovací adresář
  final testDir = Directory('test_downloads');
  if (!await testDir.exists()) {
    await testDir.create();
  }

  final testVideoPath = '${testDir.path}/test_video.mkv';
  // Vytvořit dummy video soubor
  await File(testVideoPath).writeAsString('dummy video file');

  print('📥 Downloading: ${firstSubtitle.title}');
  print('   This will save to: ${testDir.path}/test_video.${firstSubtitle.format}');
  print('');

  final result = await repository.saveSubtitleWithVideo(subtitle: firstSubtitle, videoPath: testVideoPath);

  print('');
  print('═══════════════════════════════════════════════════════');

  if (result != null) {
    print('✅ DOWNLOAD SUCCESSFUL!');
    print('   Saved to: $result');
    print('');

    // Zkontrolovat, zda soubor existuje a má nějaký obsah
    final file = File(result);
    if (await file.exists()) {
      final size = await file.length();
      print('📁 File info:');
      print('   Size: $size bytes');

      if (size > 0) {
        print('   ✅ File has content!');
        print('');

        // Přečíst prvních 500 znaků pro ověření, že je to SRT soubor
        final content = await file.readAsString();
        final preview = content.substring(0, content.length > 500 ? 500 : content.length);

        print('📄 File preview (first 500 chars):');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print(preview);
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

        // Kontrola, zda vypadá jako subtitle soubor
        if (content.contains('-->') || content.contains('WEBVTT') || content.contains('[SubRip]')) {
          print('');
          print('✅ Content looks like a valid subtitle file!');
        } else {
          print('');
          print('⚠️  Content does not look like a subtitle file - might be HTML error page');
        }
      } else {
        print('   ❌ File is empty!');
      }
    } else {
      print('❌ File does not exist after download!');
    }
  } else {
    print('❌ DOWNLOAD FAILED!');
    print('   Check the error messages above for details.');
  }

  print('═══════════════════════════════════════════════════════');
  print('');

  // Cleanup
  print('🧹 Cleaning up test files...');
  if (await testDir.exists()) {
    await testDir.delete(recursive: true);
    print('✅ Cleanup complete!');
  }

  print('');
  print('🏁 Test complete!');
}
