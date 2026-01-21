import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;

import '../models/subtitle.dart';

class TitulkyRepository {
  final Dio _dio;
  final String _baseUrl = 'https://premium.titulky.com';
  final List<String> _cookies = [];

  TitulkyRepository({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.followRedirects = true;
    _dio.options.validateStatus = (status) => status! < 500;
  }

  String get _cookieHeader => _cookies.join('; ');

  void _updateCookies(List<String>? setCookies) {
    if (setCookies == null) return;

    for (var cookie in setCookies) {
      final cookieName = cookie.split('=')[0];
      // Remove old cookie with same name
      _cookies.removeWhere((c) => c.startsWith('$cookieName='));
      // Add new cookie (only the name=value part, not expires etc.)
      _cookies.add(cookie.split(';')[0]);
    }
  }

  // Premium server uses SESSTITULKY cookie
  bool get isLoggedIn => _cookies.any((c) => c.startsWith('SESSTITULKY=') || c.startsWith('LogonLogin='));

  /// Login to titulky.com
  Future<bool> login(String username, String password) async {
    try {
      // Step 1: Get main page for initial cookies
      print('Getting main page for initial cookies...');
      final homeResponse = await _dio.get('/');
      _updateCookies(homeResponse.headers['set-cookie']);

      // Step 2: Login using correct form fields
      // Premium server uses different fields than regular server
      print('Logging in with username: $username');

      final loginResponse = await _dio.post(
        '/', // Action je přímo na homepage
        data: {
          'LoginName': username, // Premium server field
          'LoginPassword': password, // Premium server field
          'PermanentLog': '148', // Trvalé přihlášení
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Cookie': _cookieHeader, 'Referer': '$_baseUrl/', 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'},
        ),
      );

      // Update cookies after login (contains LogonLogin, LogonId, CRC)
      _updateCookies(loginResponse.headers['set-cookie']);

      // Step 3: Verify login
      print('Verifying login...');
      final verifyResponse = await _dio.get(
        '/',
        options: Options(headers: {'Cookie': _cookieHeader, 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}),
      );

      // Check if we are logged in (look for "Odhlásit" or username)
      final htmlContent = verifyResponse.data.toString();

      final success = htmlContent.contains('Odhlásit') || htmlContent.contains(username);

      if (success) {
        print('✅ Login successful!');
      } else {
        print('❌ Login failed!');
      }

      return success;
    } catch (e, stackTrace) {
      print('Login error: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Search subtitles by video name
  Future<List<Subtitle>> searchSubtitles(String query, {String? languageFilter, int page = 1}) async {
    if (!isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      print('Searching for: $query (language filter: ${languageFilter ?? 'all'}, page: $page)');

      // Build query parameters
      final queryParams = <String, dynamic>{'action': 'search', 'Fulltext': query};

      // Add pagination - premium.titulky.com uses Strana parameter
      if (page > 1) {
        queryParams['Strana'] = page.toString();
      }

      final response = await _dio.get(
        '/',
        queryParameters: queryParams,
        options: Options(headers: {'Cookie': _cookieHeader, 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}),
      );

      final document = html_parser.parse(response.data);
      final List<Subtitle> subtitles = [];

      // Debug: Print part of HTML
      if (response.data.toString().contains('přihlásit') && !response.data.toString().contains('Odhlásit')) {
        print('WARNING: Not logged in on premium server!');
      }

      // Premium server uses different structure - look for links with action=detail
      final detailLinks = document.querySelectorAll('a[href*="action=detail"]');

      // Filter unique links (some are repeated)
      final seenIds = <String>{};

      for (final link in detailLinks) {
        try {
          final href = link.attributes['href'] ?? '';

          // Get ID from URL (e.g. ./?action=detail&id=12345)
          final idMatch = RegExp(r'id=(\d+)').firstMatch(href);
          final id = idMatch?.group(1) ?? '';

          // Debug
          // print('Processing: href=$href, id=$id');

          if (id.isEmpty) continue;

          // Skip duplicates
          if (seenIds.contains(id)) continue;

          // Get title from link text
          var title = link.text.trim();

          // If link is empty, skip (there will be another link with same ID)
          if (title.isEmpty) continue;

          seenIds.add(id);

          // Normalize URL
          var downloadUrl = href;
          if (href.startsWith('./')) {
            downloadUrl = '$_baseUrl/${href.substring(2)}';
          } else if (href.startsWith('/')) {
            downloadUrl = '$_baseUrl$href';
          } else if (!href.startsWith('http')) {
            downloadUrl = '$_baseUrl/$href';
          }

          final subtitle = Subtitle(
            id: id,
            title: title,
            language: 'cs', // Všechny titulky na premium.titulky.com jsou české
            format: 'srt',
            downloadUrl: downloadUrl,
          );

          subtitles.add(subtitle);
        } catch (e) {
          print('Error parsing detail link: $e');
          continue;
        }
      }

      print('Found ${subtitles.length} unique subtitles');

      // Filter by language if specified
      if (languageFilter != null && languageFilter != 'all') {
        subtitles.removeWhere((s) => s.language != languageFilter);
        print('After language filter: ${subtitles.length} subtitles');
      }

      return subtitles;
    } catch (e, stackTrace) {
      print('Search error: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Download subtitle
  Future<String?> downloadSubtitle(Subtitle subtitle, String savePath) async {
    if (!isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      print('Downloading subtitle: ${subtitle.title}');

      // Download subtitle file
      final response = await _dio.get(
        subtitle.downloadUrl,
        options: Options(headers: {'Cookie': _cookieHeader, 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}, responseType: ResponseType.bytes),
      );

      // Určit finální cestu k souboru
      final fileName = '${subtitle.title}_${subtitle.language}.${subtitle.format}';
      final filePath = path.join(savePath, fileName);

      // Uložit soubor
      final file = File(filePath);
      await file.writeAsBytes(response.data);

      print('Subtitle saved to: $filePath');
      return filePath;
    } catch (e, stackTrace) {
      print('Download error: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Uložení titulku vedle video souboru
  Future<String?> saveSubtitleWithVideo({required Subtitle subtitle, required String videoPath}) async {
    try {
      // Získat adresář videa
      final videoDir = path.dirname(videoPath);
      final videoName = path.basenameWithoutExtension(videoPath);

      // Stáhnout titulek na detail stránku pro získání skutečného download linku
      print('Getting subtitle download link from: ${subtitle.downloadUrl}');
      final detailResponse = await _dio.get(
        subtitle.downloadUrl,
        options: Options(headers: {'Cookie': _cookieHeader, 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}),
      );

      final document = html_parser.parse(detailResponse.data);

      // Najít download link (hledat download.php pro premium nebo idown.php pro běžný server)
      var downloadLink = document.querySelector('a[href*="download.php"]');
      downloadLink ??= document.querySelector('a[href*="idown.php"]');

      if (downloadLink == null) {
        print('❌ Download link not found on detail page');
        print('Available links:');
        final allLinks = document.querySelectorAll('a[href]');
        for (var link in allLinks.take(10)) {
          print('  - ${link.attributes["href"]}');
        }
        return null;
      }

      var downloadUrl = downloadLink.attributes['href'] ?? '';
      if (downloadUrl.startsWith('./')) {
        downloadUrl = '$_baseUrl/${downloadUrl.substring(2)}';
      } else if (!downloadUrl.startsWith('http')) {
        downloadUrl = downloadUrl.startsWith('/') ? '$_baseUrl$downloadUrl' : '$_baseUrl/$downloadUrl';
      }

      print('✅ Found download link: $downloadUrl');

      // Zjistit formát z URL nebo názvu souboru
      var format = subtitle.format;

      // Vytvořit cestu pro titulek se stejným názvem jako video
      final subtitleFileName = '$videoName.$format';
      final subtitlePath = path.join(videoDir, subtitleFileName);

      // Premium server stahuje přímo, bez countdown stránky
      final finalDownloadUrl = downloadUrl;

      print('Downloading subtitle from: $finalDownloadUrl');
      print('Saving to: $subtitlePath');

      // Stáhnout soubor
      final response = await _dio.get(
        finalDownloadUrl,
        options: Options(
          headers: {'Cookie': _cookieHeader, 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36', 'Referer': downloadUrl},
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
      );

      if (response.data == null || (response.data as List).isEmpty) {
        print('❌ Downloaded file is empty');
        return null;
      }

      // Zkontrolovat, zda nejde o HTML stránku (error page nebo captcha)
      var bytes = response.data as List<int>;
      var sampleString = String.fromCharCodes(bytes.take(1000));

      // Kontrola na denní limit a captcha (obsahuje "denní limit" nebo captcha formulář)
      if (sampleString.contains('denní limit') || sampleString.contains('captcha.php') || sampleString.contains('downkod')) {
        print('❌ Denní limit stahování překročen nebo captcha požadována');
        print('   Pro obejití limitu použijte prémiový účet nebo zkuste později.');
        print('');
        print('💡 TIP: Prémiové účty mají 25 stažení/den bez ohledu na IP adresu.');
        print('   Registrujte se na: https://www.netusers.cz/');
        throw Exception('daily_limit_exceeded');
      }

      // Kontrola na countdown stránku (bez limitu - má imgLoader ale ne captcha)
      if (sampleString.contains('imgLoader') && !sampleString.contains('captcha')) {
        print('⏳ Detekována countdown stránka (bez limitu) - čekání 7 sekund...');
        await Future.delayed(const Duration(seconds: 7));

        // Po countdown zkusit znovu
        final retryResponse = await _dio.get(
          finalDownloadUrl,
          options: Options(
            headers: {'Cookie': _cookieHeader, 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36', 'Referer': downloadUrl},
            responseType: ResponseType.bytes,
            followRedirects: true,
          ),
        );

        if (retryResponse.data != null && (retryResponse.data as List).isNotEmpty) {
          bytes = retryResponse.data as List<int>;
          sampleString = String.fromCharCodes(bytes.take(1000));

          if (sampleString.contains('denní limit') || sampleString.contains('captcha')) {
            print('❌ Po countdown stále vyžadována captcha - denní limit překročen');
            throw Exception('daily_limit_exceeded');
          }
        }
      }

      // Zkontrolovat, jestli je to ZIP soubor (začíná na PK)
      if (bytes.length > 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
        print('📦 Downloaded file is ZIP archive, extracting...');

        try {
          // Rozbalit ZIP
          final archive = ZipDecoder().decodeBytes(bytes);

          // Najít první soubor s podporovanou příponou
          ArchiveFile? subtitleFile;
          for (var file in archive) {
            if (file.isFile) {
              final fileName = file.name.toLowerCase();
              if (fileName.endsWith('.srt') || fileName.endsWith('.sub') || fileName.endsWith('.txt') || fileName.endsWith('.ass') || fileName.endsWith('.ssa')) {
                subtitleFile = file;
                print('   Found subtitle file in archive: ${file.name}');
                break;
              }
            }
          }

          if (subtitleFile == null) {
            print('❌ No subtitle file found in ZIP archive');
            return null;
          }

          // Zapsat rozbalený obsah
          final subtitleBytes = subtitleFile.content as List<int>;
          final file = File(subtitlePath);
          await file.writeAsBytes(subtitleBytes);

          final fileSize = await file.length();
          print('✅ Subtitle extracted and saved successfully!');
          print('   Path: $subtitlePath');
          print('   Size: $fileSize bytes');

          return subtitlePath;
        } catch (e) {
          print('❌ Error extracting ZIP: $e');
          return null;
        }
      }

      // Pokud to není ZIP, zkontrolovat, zda nejde o HTML stránku (error page)
      final sample = String.fromCharCodes(bytes.take(100));
      if (sample.toLowerCase().contains('<!doctype') || sample.toLowerCase().contains('<html')) {
        print('❌ Downloaded file is HTML, not subtitle file');
        print('First 100 bytes: $sample');
        return null;
      }

      // Uložit soubor přímo (není to ZIP)
      final file = File(subtitlePath);
      await file.writeAsBytes(bytes);

      final fileSize = await file.length();
      print('✅ Subtitle saved successfully!');
      print('   Path: $subtitlePath');
      print('   Size: $fileSize bytes');

      return subtitlePath;
    } catch (e, stackTrace) {
      print('❌ Error saving subtitle with video: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Odhlášení
  Future<void> logout() async {
    try {
      // Vymazat cookies
      _cookies.clear();
      print('Logged out successfully');
    } catch (e) {
      print('Logout error: $e');
    }
  }
}
