import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

void main() async {
  print('=== Testing Detailed Login Flow ===\n');

  final dio = Dio();
  dio.options.connectTimeout = const Duration(seconds: 30);
  dio.options.receiveTimeout = const Duration(seconds: 30);
  dio.options.followRedirects = false; // Nechceme automatický redirect
  dio.options.validateStatus = (status) => status! < 500;

  final cookieJar = <String>[];

  try {
    // 1. Get homepage
    print('1. Getting homepage...');
    final homeResponse = await dio.get('https://www.titulky.com/');

    print('Homepage status: ${homeResponse.statusCode}');

    // Extract cookies
    final homeCookies = homeResponse.headers['set-cookie'];
    if (homeCookies != null) {
      print('Homepage cookies:');
      for (var cookie in homeCookies) {
        print('  $cookie');
        cookieJar.add(cookie.split(';')[0]);
      }
    }

    final cookieHeader = cookieJar.join('; ');
    print('Cookie header: $cookieHeader\n');

    // 2. Login
    print('2. Logging in...');
    final loginResponse = await dio.post(
      'https://www.titulky.com/',
      data: {'Login': 'jelazi', 'Password': 'Honzicek1', 'Detail2': '', 'prihlasit': 'Přihlásit', 'foreverlog': '1'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Cookie': cookieHeader, 'Referer': 'https://www.titulky.com/', 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'},
      ),
    );

    print('Login status: ${loginResponse.statusCode}');

    // Check for redirect
    if (loginResponse.statusCode == 302 || loginResponse.statusCode == 301) {
      final location = loginResponse.headers['location'];
      print('Redirecting to: $location');
    }

    // Extract new cookies
    final loginCookies = loginResponse.headers['set-cookie'];
    if (loginCookies != null) {
      print('Login cookies:');
      for (var cookie in loginCookies) {
        print('  $cookie');
        final cookieName = cookie.split('=')[0];
        // Update or add cookie
        cookieJar.removeWhere((c) => c.startsWith(cookieName));
        cookieJar.add(cookie.split(';')[0]);
      }
    }

    final updatedCookieHeader = cookieJar.join('; ');
    print('Updated cookie header: $updatedCookieHeader\n');

    // Print part of response
    final loginHtml = loginResponse.data.toString();
    print('Login response preview (first 1000 chars):');
    print(loginHtml.substring(0, loginHtml.length > 1000 ? 1000 : loginHtml.length));
    print('\n---\n');

    // 3. Verify login
    print('3. Verifying login...');
    final verifyResponse = await dio.get(
      'https://www.titulky.com/',
      options: Options(headers: {'Cookie': updatedCookieHeader, 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}),
    );

    print('Verify status: ${verifyResponse.statusCode}');

    final verifyHtml = verifyResponse.data.toString();

    // Look for login indicators
    final hasOdhlas = verifyHtml.contains('Odhlásit');
    final hasUsername = verifyHtml.contains('jelazi');

    print('Contains "Odhlásit": $hasOdhlas');
    print('Contains username: $hasUsername');

    // Search for user-related elements
    final document = html_parser.parse(verifyHtml);
    final userLinks = document.querySelectorAll('a[href*="user"], a[href*="User"], a[href*="profil"]');
    print('\nUser-related links found: ${userLinks.length}');
    for (var link in userLinks) {
      final href = link.attributes['href'] ?? '';
      final text = link.text.trim();
      print('  - $text -> $href');
    }

    if (hasOdhlas || hasUsername) {
      print('\n✅ LOGIN SUCCESSFUL!');
    } else {
      print('\n❌ LOGIN FAILED!');
      print('\nLooking for error messages...');

      // Look for error messages in login response
      final loginDoc = html_parser.parse(loginHtml);
      final errors = loginDoc.querySelectorAll('.error, .alert, .warning, [class*="error"], [class*="alert"]');
      if (errors.isNotEmpty) {
        print('Found ${errors.length} potential error elements:');
        for (var error in errors) {
          print('  - ${error.text.trim()}');
        }
      }
    }
  } catch (e, stackTrace) {
    print('Error: $e');
    print('Stack trace: $stackTrace');
  }
}
