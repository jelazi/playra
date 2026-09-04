import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;

import '../models/subtitle.dart';

/// Result of fetching alternative subtitles with enhanced original subtitle details
class AlternativeSubtitlesResult {
  final Subtitle enhancedOriginal;
  final List<Subtitle> alternatives;

  AlternativeSubtitlesResult({required this.enhancedOriginal, required this.alternatives});
}

/// Result of saving a subtitle next to a video file.
///
/// [partCount] is the number of subtitle files the downloaded archive
/// contained. A value > 1 means it was a multi-disc subtitle (CD1/CD2/...) that
/// got merged into a single track, which the UI surfaces to the user.
class SubtitleSaveResult {
  final String path;
  final int partCount;

  /// True when a multi-part archive was successfully merged into one track.
  /// False with [partCount] > 1 means only the first part could be saved.
  final bool merged;

  SubtitleSaveResult({required this.path, this.partCount = 1, this.merged = false});

  bool get wasMultiPart => partCount > 1;
}

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
  /// [alternativeSearch] sends the "Vyhledat jinak" request (fsf=1) which the
  /// site offers when the primary search returns few/no results.
  Future<List<Subtitle>> searchSubtitles(String query, {String? languageFilter, int page = 1, bool alternativeSearch = false}) async {
    if (!isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      print('Searching for: $query (language filter: ${languageFilter ?? 'all'}, page: $page, fsf: $alternativeSearch)');

      // Build query parameters
      final queryParams = <String, dynamic>{'action': 'search', 'Fulltext': query};

      // "Vyhledat jinak" (fuzzy/alternative search) - site appends fsf=1
      if (alternativeSearch) {
        queryParams['fsf'] = '1';
      }

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
  Future<SubtitleSaveResult?> saveSubtitleWithVideo({required Subtitle subtitle, required String videoPath}) async {
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

          // Posbírat VŠECHNY titulkové soubory (kvůli vícedílným CD1/CD2/... titulkům).
          // Server občas přílohám ořízne příponu (např. ".---"), proto se u neznámé
          // přípony rozhodne podle obsahu (přítomnost "-->").
          final subtitleFiles = <ArchiveFile>[];
          for (final file in archive) {
            if (!file.isFile) continue;
            final base = file.name.toLowerCase().split('/').last;

            // Přeskočit doprovodný info soubor z titulky.com
            if (base == '_info.txt') continue;

            final hasKnownExt = base.endsWith('.srt') || base.endsWith('.sub') || base.endsWith('.ass') || base.endsWith('.ssa') || base.endsWith('.txt');
            var isSubtitle = hasKnownExt;
            if (!isSubtitle) {
              final head = latin1.decode((file.content as List<int>).take(2000).toList(), allowInvalid: true);
              isSubtitle = head.contains('-->');
            }
            if (isSubtitle) subtitleFiles.add(file);
          }

          if (subtitleFiles.isEmpty) {
            print('❌ No subtitle file found in ZIP archive');
            return null;
          }

          // Seřadit podle čísla CD, aby CD1 předcházelo CD2; jinak abecedně.
          subtitleFiles.sort((a, b) {
            final ca = _cdNumber(a.name);
            final cb = _cdNumber(b.name);
            if (ca != cb) return ca.compareTo(cb);
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

          List<int> subtitleBytes;
          var mergedOk = false;
          if (subtitleFiles.length == 1) {
            subtitleBytes = subtitleFiles.first.content as List<int>;
            print('   Found subtitle file in archive: ${subtitleFiles.first.name}');
          } else {
            print('   Found ${subtitleFiles.length} subtitle parts: ${subtitleFiles.map((f) => f.name).join(', ')}');
            final merged = _mergeSrtParts(subtitleFiles.map((f) => f.content as List<int>).toList());
            if (merged != null) {
              subtitleBytes = merged;
              mergedOk = true;
              print('🔗 Merged ${subtitleFiles.length} subtitle parts into a single track');
            } else {
              // Nelze sloučit (např. nejde o SRT) – uložit aspoň první díl jako dřív.
              subtitleBytes = subtitleFiles.first.content as List<int>;
              print('⚠️ Could not merge parts (not SRT?), saved first part only: ${subtitleFiles.first.name}');
            }
          }

          final file = File(subtitlePath);
          await file.writeAsBytes(subtitleBytes);

          final fileSize = await file.length();
          print('✅ Subtitle extracted and saved successfully!');
          print('   Path: $subtitlePath');
          print('   Size: $fileSize bytes');

          return SubtitleSaveResult(path: subtitlePath, partCount: subtitleFiles.length, merged: mergedOk);
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

      return SubtitleSaveResult(path: subtitlePath, partCount: 1, merged: false);
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

  /// Get alternative subtitles from a subtitle detail page
  /// Returns enhanced original subtitle with details and list of alternative subtitles
  Future<AlternativeSubtitlesResult> getAlternativeSubtitles(Subtitle subtitle) async {
    if (!isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      print('Fetching alternative subtitles for: ${subtitle.title}');

      // Fetch the detail page
      final response = await _dio.get(
        subtitle.downloadUrl,
        options: Options(headers: {'Cookie': _cookieHeader, 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}),
      );

      final document = html_parser.parse(response.data);
      final List<Subtitle> alternatives = [];

      // Extract enhanced details for the original subtitle from the detail page
      Subtitle enhancedOriginal = subtitle;

      // Try to get enhanced info about the original subtitle from detail page content
      try {
        // Look for uploader info and other details in the page content
        final detailElements = document.querySelectorAll('td, .info, .detail-info, .table-cell, div');
        String? uploader;
        String? details;
        String? downloadCount;

        // Look for uploader patterns in various formats
        for (final element in detailElements) {
          final text = element.text.trim();

          // Uploader patterns
          if (text.contains('Přidal:') || text.contains('Autor:') || text.contains('Uživatel:') || text.contains('Nahrál:')) {
            final match = RegExp(r'(?:Přidal:|Autor:|Uživatel:|Nahrál:)\s*([^\s,\n\r]+)').firstMatch(text);
            if (match != null) {
              uploader = match.group(1);
              print('🔍 Found uploader in element: $uploader');
            }
          }

          // Release info patterns
          if (text.contains('Release:') || text.contains('Verze:') || text.contains('BDRip') || text.contains('BluRay') || text.contains('x264')) {
            // Look for release patterns
            final releasePattern = RegExp(r'([A-Za-z0-9\.\-_]+(?:BDRip|BluRay|x264|DEMAND|ROVERS)[A-Za-z0-9\.\-_]*)');
            final match = releasePattern.firstMatch(text);
            if (match != null) {
              details = match.group(1);
              print('🔍 Found release details: $details');
            }
          }

          // Download count patterns
          if (text.contains('staženo') || text.contains('krát') || RegExp(r'\d+×').hasMatch(text)) {
            final countMatch = RegExp(r'(\d+)(?:×|krát|staženo)').firstMatch(text);
            if (countMatch != null) {
              downloadCount = countMatch.group(1);
              print('🔍 Found download count: $downloadCount');
            }
          }
        }

        // Additional search in table cells specifically for True Detective pattern
        final tableCells = document.querySelectorAll('table td');
        for (final cell in tableCells) {
          final cellText = cell.text.trim();

          // Look for username patterns in table cells (like "mark82", "badboy.majkl")
          if (uploader == null &&
              RegExp(r'^[a-zA-Z0-9\._-]+$').hasMatch(cellText) &&
              cellText.length > 2 &&
              cellText.length < 20 &&
              !cellText.contains(' ') &&
              !cellText.contains('BDRip') &&
              !cellText.contains('BluRay')) {
            // This might be a username
            uploader = cellText;
            print('🔍 Found potential uploader in table cell: $uploader');
          }

          // Look for detailed release strings in cells
          if (details == null && (cellText.contains('BDRip') || cellText.contains('BluRay') || cellText.contains('x264'))) {
            details = cellText;
            print('🔍 Found release details in table cell: $details');
          }
        }

        // Create enhanced version of original subtitle if we found additional info
        if (uploader != null || details != null || downloadCount != null) {
          enhancedOriginal = Subtitle(
            id: subtitle.id,
            title: subtitle.title,
            language: subtitle.language,
            format: subtitle.format,
            downloadUrl: subtitle.downloadUrl,
            rating: subtitle.rating,
            uploader: uploader ?? subtitle.uploader,
            details: details ?? subtitle.details,
            downloadCount: downloadCount ?? subtitle.downloadCount,
            movieName: subtitle.movieName,
            isSynced: subtitle.isSynced,
          );
          print('🔵 Enhanced original subtitle: uploader=$uploader, details=$details, downloadCount=$downloadCount');
        }
      } catch (e) {
        print('Could not extract enhanced original subtitle details: $e');
      }

      // Look for the "Alternativní titulky" table
      // The structure is: table.table.table-hover with rows containing links to action=detail
      final tables = document.querySelectorAll('table.table');

      for (final table in tables) {
        final rows = table.querySelectorAll('tbody tr');

        for (final row in rows) {
          try {
            // Find the link to the subtitle detail
            final link = row.querySelector('a[href*="action=detail"]');
            if (link == null) continue;

            final href = link.attributes['href'] ?? '';
            final idMatch = RegExp(r'id=(\d+)').firstMatch(href);
            final id = idMatch?.group(1) ?? '';

            if (id.isEmpty) continue;

            // Skip if this is the same subtitle we're viewing
            if (id == subtitle.id) continue;

            // Get title from link text
            var title = link.text.trim();
            if (title.isEmpty) continue;

            // Get additional info from row cells
            final cells = row.querySelectorAll('td');
            String? uploader;
            String? releaseInfo;

            if (cells.length >= 4) {
              // Uploader in 4th cell
              uploader = cells.length > 3 ? cells[3].text.trim() : null;
              // Release info in 5th cell (hidden on mobile)
              if (cells.length > 4) {
                releaseInfo = cells[4].text.trim();
              }
            }

            // Normalize URL
            var downloadUrl = href;
            if (href.startsWith('./')) {
              downloadUrl = '$_baseUrl/${href.substring(2)}';
            } else if (href.startsWith('/')) {
              downloadUrl = '$_baseUrl$href';
            } else if (!href.startsWith('http')) {
              downloadUrl = '$_baseUrl/$href';
            }

            final alternativeSubtitle = Subtitle(id: id, title: title, language: 'cs', format: 'srt', downloadUrl: downloadUrl, uploader: uploader, details: releaseInfo);

            alternatives.add(alternativeSubtitle);
          } catch (e) {
            print('Error parsing alternative subtitle row: $e');
            continue;
          }
        }
      }

      print('Found ${alternatives.length} alternative subtitles');
      return AlternativeSubtitlesResult(enhancedOriginal: enhancedOriginal, alternatives: alternatives);
    } catch (e, stackTrace) {
      print('Error fetching alternative subtitles: $e');
      print('Stack trace: $stackTrace');
      return AlternativeSubtitlesResult(enhancedOriginal: subtitle, alternatives: []);
    }
  }

  /// Extract the CD number from a part file name (e.g. "Movie [CD2].srt" -> 2).
  /// Returns 0 when no marker is present so single-disc files keep their order.
  int _cdNumber(String name) {
    final match = RegExp(r'(?:\[?\s*cd\s*0*([0-9]+)\s*\]?|(?:^|[._\- ])0*([0-9]+)\s*(?:of|z)\s*[0-9]+)', caseSensitive: false).firstMatch(name);
    if (match == null) return 0;
    final value = match.group(1) ?? match.group(2);
    return int.tryParse(value ?? '') ?? 0;
  }

  /// Merge multiple SRT parts (CD1/CD2/...) into a single SRT track.
  ///
  /// Each subsequent part is time-shifted by the end timestamp of the previous
  /// part, since multi-disc subtitles restart their timeline at zero. The shift
  /// is an estimate (it assumes the next disc begins right where the previous
  /// one ends), which is accurate enough for a single merged video file.
  ///
  /// Dialogue bytes are preserved via a latin1 round-trip so the original
  /// (usually Windows-1250) encoding survives untouched — only the ASCII
  /// timestamp/index lines are rewritten. Returns null if any part is not SRT.
  List<int>? _mergeSrtParts(List<List<int>> parts) {
    final buffer = StringBuffer();
    var index = 1;
    var offset = Duration.zero;

    for (final partBytes in parts) {
      final entries = _parseSrt(latin1.decode(partBytes, allowInvalid: true));
      if (entries.isEmpty) return null; // not parseable as SRT -> let caller fall back

      var lastEnd = offset;
      for (final entry in entries) {
        final start = entry.start + offset;
        final end = entry.end + offset;
        if (end > lastEnd) lastEnd = end;

        buffer.write('$index\r\n');
        buffer.write('${_formatSrtTime(start)} --> ${_formatSrtTime(end)}\r\n');
        buffer.write(entry.text);
        buffer.write('\r\n\r\n');
        index++;
      }
      offset = lastEnd; // next part picks up where this one ended
    }

    return latin1.encode(buffer.toString());
  }

  /// Parse SRT content into time-stamped entries. Index lines and surrounding
  /// blank lines are ignored; entry text keeps its original (raw) line content.
  List<_SrtEntry> _parseSrt(String content) {
    final entries = <_SrtEntry>[];
    final lines = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final timeRe = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})');

    var i = 0;
    while (i < lines.length) {
      final match = timeRe.firstMatch(lines[i]);
      if (match == null) {
        i++;
        continue;
      }
      final start = _durationFromMatch(match, 1);
      final end = _durationFromMatch(match, 5);
      i++;

      final textLines = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        textLines.add(lines[i]);
        i++;
      }
      entries.add(_SrtEntry(start, end, textLines.join('\r\n')));
    }
    return entries;
  }

  Duration _durationFromMatch(RegExpMatch match, int firstGroup) {
    final hours = int.parse(match.group(firstGroup)!);
    final minutes = int.parse(match.group(firstGroup + 1)!);
    final seconds = int.parse(match.group(firstGroup + 2)!);
    final msRaw = match.group(firstGroup + 3)!;
    final milliseconds = int.parse(msRaw.padRight(3, '0').substring(0, 3));
    return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: milliseconds);
  }

  String _formatSrtTime(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds,$millis';
  }
}

/// A single SRT cue: its time span and raw (un-decoded) text content.
class _SrtEntry {
  final Duration start;
  final Duration end;
  final String text;

  _SrtEntry(this.start, this.end, this.text);
}
