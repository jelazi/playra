import 'dart:convert';

import 'package:dio/dio.dart';

/// Lightweight translation helper backed by the public Google Translate HTTP
/// endpoint. Used only as a fallback when TMDB does not provide localized
/// episode metadata.
class TranslationService {
  TranslationService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://translate.googleapis.com'));

  final Dio _dio;
  final Map<String, String> _cache = <String, String>{};

  Future<String?> translateText(String text, {required String targetLanguage, String sourceLanguage = 'auto'}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (targetLanguage.toLowerCase().startsWith('en')) return trimmed;

    final cacheKey = '$sourceLanguage|$targetLanguage|$trimmed';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final response = await _dio.get<dynamic>(
        '/translate_a/single',
        queryParameters: <String, dynamic>{'client': 'gtx', 'sl': sourceLanguage, 'tl': targetLanguage, 'dt': 't', 'q': trimmed},
        options: Options(responseType: ResponseType.plain),
      );

      final raw = response.data;
      if (raw == null) return null;

      final decoded = jsonDecode(raw is String ? raw : raw.toString());
      if (decoded is! List || decoded.isEmpty || decoded.first is! List) {
        return null;
      }

      final chunks = decoded.first as List;
      final translated = chunks.whereType<List>().map((chunk) => chunk.isNotEmpty ? chunk.first?.toString() ?? '' : '').join().trim();

      if (translated.isEmpty) return null;

      _cache[cacheKey] = translated;
      return translated;
    } catch (_) {
      return null;
    }
  }
}
