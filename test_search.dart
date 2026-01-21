import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

void main() async {
  print('=== Testing Search on Titulky.com ===\n');

  final dio = Dio();
  dio.options.followRedirects = true;
  final cookieJar = <String>[];

  try {
    // 1. Get homepage & cookies
    print('1. Getting homepage...');
    var response = await dio.get('https://www.titulky.com/');

    var cookies = response.headers['set-cookie'];
    if (cookies != null) {
      for (var cookie in cookies) {
        cookieJar.add(cookie.split(';')[0]);
      }
    }

    // 2. Login
    print('2. Logging in...');
    response = await dio.post(
      'https://www.titulky.com/',
      data: {'Login': 'jelazi', 'Password': 'Honzicek1', 'Detail2': '', 'prihlasit': 'Přihlásit', 'foreverlog': '1'},
      options: Options(contentType: Headers.formUrlEncodedContentType, headers: {'Cookie': cookieJar.join('; '), 'User-Agent': 'Mozilla/5.0'}),
    );

    cookies = response.headers['set-cookie'];
    if (cookies != null) {
      for (var cookie in cookies) {
        final name = cookie.split('=')[0];
        cookieJar.removeWhere((c) => c.startsWith('$name='));
        cookieJar.add(cookie.split(';')[0]);
      }
    }

    print('Cookies: ${cookieJar.join('; ')}\n');

    // 3. Test vyhledávání s různými parametry
    print('3. Testing search with Fulltext parameter...');
    response = await dio.get(
      'https://www.titulky.com/',
      queryParameters: {'Fulltext': 'Matrix'},
      options: Options(headers: {'Cookie': cookieJar.join('; '), 'User-Agent': 'Mozilla/5.0'}),
    );

    print('Status: ${response.statusCode}');
    print('URL: ${response.realUri}');

    var document = html_parser.parse(response.data);
    var results = document.querySelectorAll('.content-box, .result, .titulky-box, [class*="tilutek"]');
    print('Found ${results.length} result containers\n');

    // Hledat všechny odkazy na titulky
    var links = document.querySelectorAll('a[href*="titulky"], a[href*="idown"]');
    print('Found ${links.length} subtitle-related links');
    if (links.isNotEmpty) {
      print('First 5 links:');
      for (var i = 0; i < links.length && i < 5; i++) {
        final href = links[i].attributes['href'] ?? '';
        final text = links[i].text.trim();
        print('  $i. $text -> $href');
      }
    }

    // Hledat tabulky
    print('\n4. Looking for tables...');
    var tables = document.querySelectorAll('table');
    print('Found ${tables.length} tables');

    for (var i = 0; i < tables.length; i++) {
      final table = tables[i];
      final className = table.attributes['class'] ?? 'no class';
      final id = table.attributes['id'] ?? 'no id';
      final rows = table.querySelectorAll('tr');
      print('  Table ${i + 1}: class="$className", id="$id", ${rows.length} rows');

      // Zobrazit první řádek
      if (rows.isNotEmpty) {
        final firstRow = rows[0];
        final cells = firstRow.querySelectorAll('td, th');
        if (cells.isNotEmpty) {
          print('    First row cells:');
          for (var cell in cells) {
            print('      - ${cell.text.trim()}');
          }
        }
      }
    }

    // Hledat výsledky přes různé selektory
    print('\n5. Trying different selectors...');
    final selectors = ['.titulky-box', '.tilutek', '[class*="tilutek"]', 'div[id*="tilutek"]', '.result-item', 'article', 'section'];

    for (var selector in selectors) {
      final elements = document.querySelectorAll(selector);
      if (elements.isNotEmpty) {
        print('  $selector: ${elements.length} elements');
      }
    }
  } catch (e, stackTrace) {
    print('Error: $e');
    print('$stackTrace');
  }
}
