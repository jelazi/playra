import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/video_item.dart';

class VideoHashService {
  static const int _chunkSize = 256 * 1024;

  static Future<String?> hashForVideo(VideoItem video) async {
    if (video.uri.isEmpty) return null;

    if (video.uri.startsWith('http://') || video.uri.startsWith('https://')) {
      return _hashHttpResource(Uri.parse(video.uri));
    }

    if (video.source == VideoSource.local) {
      return _hashLocalFile(File(video.uri));
    }

    return null;
  }

  static Future<String?> _hashLocalFile(File file) async {
    if (!await file.exists()) return null;

    final stat = await file.stat();
    final length = stat.size;
    if (length <= 0) return null;

    final raf = await file.open();
    try {
      final firstLen = length < _chunkSize ? length : _chunkSize;
      final first = await raf.read(firstLen);

      List<int> tail = const [];
      if (length > _chunkSize) {
        await raf.setPosition(length - _chunkSize);
        tail = await raf.read(_chunkSize);
      }

      return _digest(length, first, tail);
    } finally {
      await raf.close();
    }
  }

  static Future<String?> _hashHttpResource(Uri uri) async {
    final client = HttpClient();
    try {
      final total = await _contentLength(client, uri);
      if (total == null || total <= 0) return null;

      final first = await _readRange(client, uri, 0, _chunkSize - 1);
      if (first == null || first.isEmpty) return null;

      List<int> tail = const [];
      if (total > _chunkSize) {
        final start = total - _chunkSize;
        tail = await _readRange(client, uri, start, total - 1) ?? const [];
      }

      return _digest(total, first, tail);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<int?> _contentLength(HttpClient client, Uri uri) async {
    try {
      final head = await client.headUrl(uri);
      final headRes = await head.close();
      final h = headRes.contentLength;
      if (h > 0) return h;
    } catch (_) {}

    try {
      final get = await client.getUrl(uri);
      get.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final res = await get.close();
      final range = res.headers.value(HttpHeaders.contentRangeHeader);
      if (range != null) {
        final slash = range.lastIndexOf('/');
        if (slash > 0) {
          final parsed = int.tryParse(range.substring(slash + 1));
          if (parsed != null && parsed > 0) return parsed;
        }
      }
      if (res.contentLength > 0) return res.contentLength;
    } catch (_) {}

    return null;
  }

  static Future<List<int>?> _readRange(HttpClient client, Uri uri, int start, int end) async {
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      final res = await req.close();
      if (res.statusCode != HttpStatus.partialContent && res.statusCode != HttpStatus.ok) {
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    }
  }

  static String _digest(int length, List<int> head, List<int> tail) {
    final input = <int>[];
    input.addAll(utf8.encode('len:$length|'));
    input.addAll(head);
    input.addAll(utf8.encode('|tail|'));
    input.addAll(tail);
    return sha256.convert(input).toString();
  }
}
