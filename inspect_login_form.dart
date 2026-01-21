import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

void main() async {
  print('=== Inspecting Titulky.com Login Form ===\n');

  final dio = Dio();
  dio.options.connectTimeout = const Duration(seconds: 30);
  dio.options.receiveTimeout = const Duration(seconds: 30);

  try {
    // Stáhnout hlavní stránku
    print('Downloading homepage...');
    final response = await dio.get('https://www.titulky.com/');

    if (response.statusCode != 200) {
      print('Error: Status code ${response.statusCode}');
      return;
    }

    // Parsovat HTML
    final document = html_parser.parse(response.data);

    // Najít všechny formuláře
    final forms = document.querySelectorAll('form');
    print('\nFound ${forms.length} forms on the page\n');

    for (var i = 0; i < forms.length; i++) {
      final form = forms[i];
      final action = form.attributes['action'] ?? 'no action';
      final method = form.attributes['method'] ?? 'no method';
      final id = form.attributes['id'] ?? 'no id';
      final className = form.attributes['class'] ?? 'no class';

      print('--- Form ${i + 1} ---');
      print('Action: $action');
      print('Method: $method');
      print('ID: $id');
      print('Class: $className');

      // Najít všechny input pole
      final inputs = form.querySelectorAll('input');
      print('Inputs:');
      for (var input in inputs) {
        final type = input.attributes['type'] ?? 'text';
        final name = input.attributes['name'] ?? 'no name';
        final id = input.attributes['id'] ?? 'no id';
        final value = input.attributes['value'] ?? '';
        print('  - Type: $type, Name: $name, ID: $id, Value: $value');
      }

      // Najít buttony
      final buttons = form.querySelectorAll('button');
      print('Buttons:');
      for (var button in buttons) {
        final type = button.attributes['type'] ?? 'button';
        final name = button.attributes['name'] ?? 'no name';
        print('  - Type: $type, Name: $name, Text: ${button.text.trim()}');
      }

      print('');
    }

    // Hledat přihlašovací formulář specificky
    print('\n=== Looking for login-related elements ===\n');

    // Hledat input s názvem obsahujícím login, user, password
    final loginInputs = document.querySelectorAll('input[name*="ogin"], input[name*="ser"], input[name*="assword"]');
    print('Found ${loginInputs.length} potential login inputs:');
    for (var input in loginInputs) {
      final type = input.attributes['type'] ?? 'text';
      final name = input.attributes['name'] ?? 'no name';
      final id = input.attributes['id'] ?? 'no id';
      print('  - Type: $type, Name: $name, ID: $id');
    }

    // Hledat odkazy na Login.php
    final loginLinks = document.querySelectorAll('a[href*="Login"], a[href*="login"]');
    print('\nFound ${loginLinks.length} login links:');
    for (var link in loginLinks) {
      final href = link.attributes['href'] ?? '';
      print('  - Href: $href, Text: ${link.text.trim()}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
