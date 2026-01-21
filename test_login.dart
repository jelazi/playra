import 'package:titulky_com/repositories/titulky_repository.dart';

void main() async {
  print('=== Testing Titulky.com Login ===\n');

  final repository = TitulkyRepository();

  print('Attempting to login with username: jelazi');
  final success = await repository.login('jelazi', 'Honzicek1');

  if (success) {
    print('\n✅ Login SUCCESSFUL!');
    print('Session established: ${repository.isLoggedIn}');

    // Test vyhledávání
    print('\n=== Testing Search ===');
    print('Searching for "Matrix"...');
    final subtitles = await repository.searchSubtitles('Matrix');
    print('Found ${subtitles.length} subtitles');

    if (subtitles.isNotEmpty) {
      print('\nFirst 3 results:');
      for (var i = 0; i < subtitles.length && i < 3; i++) {
        final sub = subtitles[i];
        print('  ${i + 1}. ${sub.title}');
        print('     Language: ${sub.language}');
        print('     ID: ${sub.id}');
        print('     Download URL: ${sub.downloadUrl}');
        print('');
      }
    }
  } else {
    print('\n❌ Login FAILED!');
    print('Please check:');
    print('1. Username and password are correct');
    print('2. Internet connection is working');
    print('3. Titulky.com website is accessible');
  }
}
