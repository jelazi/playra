import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

void main() async {
  print('=== Testing Alternative Subtitles on premium.titulky.com ===\n');

  final dio = Dio();
  dio.options.baseUrl = 'https://premium.titulky.com';
  dio.options.followRedirects = true;
  dio.options.validateStatus = (status) => status! < 500;
  final cookies = <String>[];

  String cookieHeader() => cookies.join('; ');

  void updateCookies(List<String>? setCookies) {
    if (setCookies == null) return;
    for (var cookie in setCookies) {
      final cookieName = cookie.split('=')[0];
      cookies.removeWhere((c) => c.startsWith('$cookieName='));
      cookies.add(cookie.split(';')[0]);
    }
  }

  try {
    // 1. Get homepage & cookies
    print('1. Getting homepage...');
    var response = await dio.get('/');
    updateCookies(response.headers['set-cookie']);

    // 2. Login
    print('2. Logging in...');
    response = await dio.post(
      '/',
      data: {'LoginName': 'jelazi', 'LoginPassword': 'Honzicek1', 'PermanentLog': '148'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Cookie': cookieHeader(), 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'},
      ),
    );
    updateCookies(response.headers['set-cookie']);

    // 3. Search for subtitles - try a popular movie with many alternatives
    print('3. Searching for "Interstellar"...');
    response = await dio.get(
      '/',
      queryParameters: {'action': 'search', 'Fulltext': 'Interstellar'},
      options: Options(headers: {'Cookie': cookieHeader(), 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}),
    );

    final searchDoc = html_parser.parse(response.data);
    final detailLinks = searchDoc.querySelectorAll('a[href*="action=detail"]');
    print('   Found ${detailLinks.length} subtitle links');

    // Print all links to see the titles
    print('\n   First 10 results:');
    final seenIds = <String>{};
    var count = 0;
    for (var link in detailLinks) {
      if (count >= 10) break;
      final href = link.attributes['href'] ?? '';
      final text = link.text.trim();
      final idMatch = RegExp(r'id=(\d+)').firstMatch(href);
      final id = idMatch?.group(1) ?? '';
      if (id.isNotEmpty && !seenIds.contains(id) && text.isNotEmpty) {
        seenIds.add(id);
        print('   $count. $text (id=$id)');
        count++;
      }
    }

    if (detailLinks.isEmpty) {
      print('   No subtitles found!');
      return;
    }

    // Get first subtitle detail URL
    var firstLink = detailLinks.first.attributes['href'] ?? '';
    if (firstLink.startsWith('./')) {
      firstLink = '${dio.options.baseUrl}/${firstLink.substring(2)}';
    }
    print('   First subtitle: ${detailLinks.first.text.trim()}');
    print('   URL: $firstLink');

    // 4. Get detail page
    print('\n4. Getting detail page...');
    response = await dio.get(firstLink, options: Options(headers: {'Cookie': cookieHeader(), 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}));

    final detailDoc = html_parser.parse(response.data);

    // Print full HTML for analysis
    print('\n=== ANALYZING DETAIL PAGE ===\n');

    // Save full HTML to file for analysis
    await File('detail_page.html').writeAsString(response.data.toString());
    print('Full HTML saved to detail_page.html');

    // Look for alternative subtitles section
    print('5. Looking for alternative subtitles...');

    // Try various selectors that might contain alternatives
    final possibleSelectors = ['a[href*="action=detail"]', '.alternativy', '.alternatives', '#alternativy', '[class*="alt"]', '[id*="alt"]', 'table a', '.box a', '.content a'];

    for (var selector in possibleSelectors) {
      try {
        final elements = detailDoc.querySelectorAll(selector);
        if (elements.isNotEmpty) {
          print('\n   Selector: $selector');
          print('   Found ${elements.length} elements');
          for (var i = 0; i < elements.length && i < 10; i++) {
            final el = elements[i];
            final href = el.attributes['href'] ?? '';
            final text = el.text.trim();
            final className = el.attributes['class'] ?? '';
            if (text.isNotEmpty || href.contains('detail')) {
              print('      $i. text="$text" href="$href" class="$className"');
            }
          }
        }
      } catch (e) {
        // Ignore selector errors
      }
    }

    // Look for all links on the page
    print('\n6. All links on detail page:');
    final allLinks = detailDoc.querySelectorAll('a[href]');
    print('   Total links: ${allLinks.length}');

    var detailLinkCount = 0;
    for (var link in allLinks) {
      final href = link.attributes['href'] ?? '';
      final text = link.text.trim();

      // Only show links that might be alternative subtitles
      if (href.contains('action=detail') && href != firstLink) {
        detailLinkCount++;
        if (detailLinkCount <= 20) {
          print('   - "$text" -> $href');
        }
      }
    }
    print('   Found $detailLinkCount alternative subtitle links');

    // Look for table rows
    print('\n7. Looking for tables with alternatives...');
    final tables = detailDoc.querySelectorAll('table');
    print('   Found ${tables.length} tables');

    for (var i = 0; i < tables.length; i++) {
      final table = tables[i];
      final tableLinks = table.querySelectorAll('a[href*="detail"]');
      if (tableLinks.length > 1) {
        print('   Table $i has ${tableLinks.length} detail links:');
        for (var j = 0; j < tableLinks.length && j < 10; j++) {
          final link = tableLinks[j];
          print('      - ${link.text.trim()} -> ${link.attributes['href']}');
        }
      }
    }

    // Look for divs that might contain alternatives
    print('\n8. Looking for divs that might contain alternatives...');
    final divs = detailDoc.querySelectorAll('div');
    for (var div in divs) {
      final className = div.attributes['class'] ?? '';
      final id = div.attributes['id'] ?? '';
      if (className.toLowerCase().contains('alt') ||
          id.toLowerCase().contains('alt') ||
          className.toLowerCase().contains('related') ||
          className.toLowerCase().contains('similar')) {
        print('   Found div: class="$className" id="$id"');
        final innerLinks = div.querySelectorAll('a[href*="detail"]');
        print('   Contains ${innerLinks.length} detail links');
      }
    }

    // Print raw HTML sections that might contain alternatives
    print('\n9. Searching for "alternativ" in HTML...');
    final htmlContent = response.data.toString().toLowerCase();
    if (htmlContent.contains('alternativ')) {
      final idx = htmlContent.indexOf('alternativ');
      print('   Found "alternativ" at position $idx');
      print('   Context: ...${response.data.toString().substring(idx > 100 ? idx - 100 : 0, idx + 500 > htmlContent.length ? htmlContent.length : idx + 500)}...');
    } else {
      print('   "alternativ" not found in HTML');
    }

    // Search for "dalsi" (další = more/other in Czech)
    print('\n10. Searching for "dalsi" or "další" in HTML...');
    if (htmlContent.contains('dalsi') || htmlContent.contains('další')) {
      final patterns = ['dalsi', 'další', 'dalsí'];
      for (var pattern in patterns) {
        if (htmlContent.contains(pattern)) {
          final idx = htmlContent.indexOf(pattern);
          print('   Found "$pattern" at position $idx');
        }
      }
    }
  } catch (e, st) {
    print('Error: $e');
    print('Stack trace: $st');
  }
}
