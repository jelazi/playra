import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/subtitle_entry.dart';

/// One embedded subtitle track extracted from a Matroska (MKV/WebM) container.
class EmbeddedSubtitleTrack {
  EmbeddedSubtitleTrack({required this.trackNumber, required this.codecId, this.language, this.name, required this.cues});

  final int trackNumber;
  final String codecId;
  final String? language;
  final String? name;
  final List<SubtitleEntry> cues;
}

/// Minimal, dependency-free Matroska/EBML reader that extracts *text* subtitle
/// tracks (`S_TEXT/UTF8` = SRT, `S_TEXT/ASS` / `S_TEXT/SSA`) and converts them
/// to [SubtitleEntry] cues.
///
/// This is how Playra turns embedded subtitles into "external" cues so they can
/// be rendered with full Flutter styling. Bitmap subtitles (PGS/VOBSUB) are not
/// supported. Works on local files and over HTTP (range requests) — the latter
/// powers SMB playback served through Playra's local proxy.
///
/// The scan skips audio/video block payloads (no bytes read for them), so only
/// subtitle data and small element headers are fetched.
class MatroskaSubtitleExtractor {
  // EBML / Matroska element IDs (full IDs, including length-descriptor bits).
  static const int _idSegment = 0x18538067;
  static const int _idInfo = 0x1549A966;
  static const int _idTimecodeScale = 0x2AD7B1;
  static const int _idTracks = 0x1654AE6B;
  static const int _idTrackEntry = 0xAE;
  static const int _idTrackNumber = 0xD7;
  static const int _idTrackType = 0x83;
  static const int _idCodecId = 0x86;
  static const int _idLanguage = 0x22B59C;
  static const int _idName = 0x536E;
  static const int _idCluster = 0x1F43B675;
  static const int _idTimecode = 0xE7;
  static const int _idSimpleBlock = 0xA3;
  static const int _idBlockGroup = 0xA0;
  static const int _idBlock = 0xA1;
  static const int _idBlockDuration = 0x9B;

  static const int _trackTypeSubtitle = 0x11;

  /// Extracts text subtitle tracks from a local MKV/WebM [path].
  static Future<List<EmbeddedSubtitleTrack>> extractFromFile(String path) async {
    _ByteSource? source;
    try {
      final file = File(path);
      if (!await file.exists()) return const [];
      final raf = await file.open();
      source = _FileByteSource(raf, await raf.length());
      return await _extract(source);
    } catch (_) {
      return const [];
    } finally {
      await source?.close();
    }
  }

  /// Extracts text subtitle tracks from an MKV/WebM served over HTTP [url]
  /// (requires the server to support range requests).
  static Future<List<EmbeddedSubtitleTrack>> extractFromHttp(String url) async {
    _ByteSource? source;
    try {
      final http = _HttpByteSource(Uri.parse(url));
      final length = await http.length();
      if (length <= 0) {
        await http.close();
        return const [];
      }
      source = http;
      return await _extract(source);
    } catch (_) {
      return const [];
    } finally {
      await source?.close();
    }
  }

  static Future<List<EmbeddedSubtitleTrack>> _extract(_ByteSource source) async {
    final length = await source.length();
    final reader = _Reader(source, length);

    // Validate EBML header magic.
    final firstId = await reader.readId();
    if (firstId != 0x1A45DFA3) return const [];
    final headerSize = await reader.readSize();
    await reader.skip(headerSize);

    final segId = await reader.readId();
    if (segId != _idSegment) return const [];
    final segSize = await reader.readSize();
    final segEnd = segSize == _unknownSize ? length : reader.position + segSize;

    final tracks = <int, _TrackMeta>{};
    final cuesByTrack = <int, List<SubtitleEntry>>{};
    var timecodeScaleNs = 1000000; // default 1ms

    while (reader.position < segEnd) {
      final id = await reader.readId();
      if (id == _idEof) break;
      final size = await reader.readSize();
      final elementEnd = size == _unknownSize ? segEnd : reader.position + size;

      switch (id) {
        case _idInfo:
          timecodeScaleNs = await _readTimecodeScale(reader, elementEnd, timecodeScaleNs);
          break;
        case _idTracks:
          await _readTracks(reader, elementEnd, tracks);
          break;
        case _idCluster:
          await _readCluster(reader, elementEnd, tracks, cuesByTrack, timecodeScaleNs);
          break;
        default:
          await reader.seekTo(elementEnd);
      }
    }

    final result = <EmbeddedSubtitleTrack>[];
    tracks.forEach((number, meta) {
      if (!_isTextCodec(meta.codecId)) return;
      final cues = cuesByTrack[number];
      if (cues == null || cues.isEmpty) return;
      cues.sort((a, b) => a.startTime.compareTo(b.startTime));
      final renumbered = <SubtitleEntry>[];
      for (var i = 0; i < cues.length; i++) {
        renumbered.add(cues[i].copyWith(index: i + 1));
      }
      result.add(EmbeddedSubtitleTrack(trackNumber: number, codecId: meta.codecId, language: meta.language, name: meta.name, cues: renumbered));
    });
    return result;
  }

  static bool _isTextCodec(String codecId) {
    final c = codecId.toUpperCase();
    return c == 'S_TEXT/UTF8' || c == 'S_TEXT/ASS' || c == 'S_TEXT/SSA';
  }

  static Future<int> _readTimecodeScale(_Reader reader, int end, int fallback) async {
    var scale = fallback;
    while (reader.position < end) {
      final id = await reader.readId();
      if (id == _idEof) break;
      final size = await reader.readSize();
      if (id == _idTimecodeScale) {
        scale = await reader.readUInt(size);
      } else {
        await reader.skip(size);
      }
    }
    return scale;
  }

  static Future<void> _readTracks(_Reader reader, int end, Map<int, _TrackMeta> out) async {
    while (reader.position < end) {
      final id = await reader.readId();
      if (id == _idEof) break;
      final size = await reader.readSize();
      if (id == _idTrackEntry) {
        await _readTrackEntry(reader, reader.position + size, out);
      } else {
        await reader.skip(size);
      }
    }
  }

  static Future<void> _readTrackEntry(_Reader reader, int end, Map<int, _TrackMeta> out) async {
    int? number;
    int? type;
    var codecId = '';
    String? language;
    String? name;

    while (reader.position < end) {
      final id = await reader.readId();
      if (id == _idEof) break;
      final size = await reader.readSize();
      switch (id) {
        case _idTrackNumber:
          number = await reader.readUInt(size);
          break;
        case _idTrackType:
          type = await reader.readUInt(size);
          break;
        case _idCodecId:
          codecId = await reader.readString(size);
          break;
        case _idLanguage:
          language = await reader.readString(size);
          break;
        case _idName:
          name = await reader.readString(size);
          break;
        default:
          await reader.skip(size);
      }
    }

    if (number != null && type == _trackTypeSubtitle) {
      out[number] = _TrackMeta(codecId: codecId, language: language, name: name);
    }
  }

  static Future<void> _readCluster(_Reader reader, int end, Map<int, _TrackMeta> tracks, Map<int, List<SubtitleEntry>> cuesByTrack, int timecodeScaleNs) async {
    var clusterTimecode = 0;
    while (reader.position < end) {
      final id = await reader.readId();
      if (id == _idEof) break;
      final size = await reader.readSize();
      final elementEnd = reader.position + size;

      switch (id) {
        case _idTimecode:
          clusterTimecode = await reader.readUInt(size);
          break;
        case _idSimpleBlock:
          await _readBlock(reader, size, tracks, cuesByTrack, clusterTimecode, timecodeScaleNs);
          break;
        case _idBlockGroup:
          await _readBlockGroup(reader, elementEnd, tracks, cuesByTrack, clusterTimecode, timecodeScaleNs);
          break;
        default:
          await reader.seekTo(elementEnd);
      }
    }
  }

  static Future<void> _readBlockGroup(_Reader reader, int end, Map<int, _TrackMeta> tracks, Map<int, List<SubtitleEntry>> cuesByTrack, int clusterTimecode, int timecodeScaleNs) async {
    int? durationTicks;
    _PendingBlock? pending;

    while (reader.position < end) {
      final id = await reader.readId();
      if (id == _idEof) break;
      final size = await reader.readSize();
      if (id == _idBlock) {
        pending = await _parseBlock(reader, size, tracks);
      } else if (id == _idBlockDuration) {
        durationTicks = await reader.readUInt(size);
      } else {
        await reader.skip(size);
      }
    }

    if (pending == null) return;
    final startMs = ((clusterTimecode + pending.relativeTime) * timecodeScaleNs) ~/ 1000000;
    final durationMs = durationTicks != null ? (durationTicks * timecodeScaleNs) ~/ 1000000 : 4000;
    _appendCue(cuesByTrack, pending.trackNumber, startMs, startMs + durationMs, pending.text);
  }

  static Future<void> _readBlock(_Reader reader, int size, Map<int, _TrackMeta> tracks, Map<int, List<SubtitleEntry>> cuesByTrack, int clusterTimecode, int timecodeScaleNs) async {
    final pending = await _parseBlock(reader, size, tracks);
    if (pending == null) return;
    final startMs = ((clusterTimecode + pending.relativeTime) * timecodeScaleNs) ~/ 1000000;
    _appendCue(cuesByTrack, pending.trackNumber, startMs, startMs + 4000, pending.text);
  }

  /// Parses a (Simple)Block header + payload. Returns null for non-subtitle
  /// tracks (their payload is skipped without being read).
  static Future<_PendingBlock?> _parseBlock(_Reader reader, int size, Map<int, _TrackMeta> tracks) async {
    final blockEnd = reader.position + size;
    final trackNumber = await reader.readVIntValue();
    if (!tracks.containsKey(trackNumber)) {
      await reader.seekTo(blockEnd);
      return null;
    }
    final relTime = await reader.readSInt16();
    await reader.skip(1); // flags byte (assume no lacing for text subtitles)
    final remaining = blockEnd - reader.position;
    if (remaining <= 0) return null;
    final data = await reader.readBytes(remaining);
    final text = _decodeText(data, tracks[trackNumber]!.codecId);
    return _PendingBlock(trackNumber: trackNumber, relativeTime: relTime, text: text);
  }

  static void _appendCue(Map<int, List<SubtitleEntry>> cuesByTrack, int trackNumber, int startMs, int endMs, String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final list = cuesByTrack.putIfAbsent(trackNumber, () => <SubtitleEntry>[]);
    list.add(SubtitleEntry(index: list.length + 1, startTime: Duration(milliseconds: startMs), endTime: Duration(milliseconds: endMs < startMs ? startMs + 2000 : endMs), text: clean));
  }

  static String _decodeText(Uint8List data, String codecId) {
    String raw;
    try {
      raw = utf8.decode(data, allowMalformed: true);
    } catch (_) {
      raw = String.fromCharCodes(data);
    }
    if (codecId.toUpperCase().contains('ASS') || codecId.toUpperCase().contains('SSA')) {
      // ASS block payload fields: ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text
      final parts = raw.split(',');
      if (parts.length >= 9) {
        raw = parts.sublist(8).join(',');
      }
      raw = raw.replaceAll('\\N', '\n').replaceAll('\\n', '\n');
    }
    // Strip ASS inline override blocks and HTML-ish tags.
    return raw.replaceAll(RegExp(r'\{\\[^}]*\}'), '').replaceAll(RegExp(r'<[^>]+>'), '');
  }
}

const int _unknownSize = -1;
const int _idEof = -2;

class _TrackMeta {
  _TrackMeta({required this.codecId, this.language, this.name});
  final String codecId;
  final String? language;
  final String? name;
}

class _PendingBlock {
  _PendingBlock({required this.trackNumber, required this.relativeTime, required this.text});
  final int trackNumber;
  final int relativeTime;
  final String text;
}

/// A random-access byte source (local file or HTTP range).
abstract class _ByteSource {
  Future<int> length();
  Future<Uint8List> readAt(int offset, int count);
  Future<void> close();
}

class _FileByteSource implements _ByteSource {
  _FileByteSource(this._raf, this._length);
  final RandomAccessFile _raf;
  final int _length;

  @override
  Future<int> length() async => _length;

  @override
  Future<Uint8List> readAt(int offset, int count) async {
    await _raf.setPosition(offset);
    return _raf.read(count);
  }

  @override
  Future<void> close() async => _raf.close();
}

class _HttpByteSource implements _ByteSource {
  _HttpByteSource(this._url);
  final Uri _url;
  final HttpClient _client = HttpClient();
  int? _len;

  @override
  Future<int> length() async {
    if (_len != null) return _len!;
    final req = await _client.getUrl(_url);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final res = await req.close();
    final contentRange = res.headers.value(HttpHeaders.contentRangeHeader);
    await res.drain<void>();
    if (contentRange != null && contentRange.contains('/')) {
      _len = int.tryParse(contentRange.split('/').last.trim());
    }
    _len ??= res.contentLength > 0 ? res.contentLength : 0;
    return _len!;
  }

  @override
  Future<Uint8List> readAt(int offset, int count) async {
    final req = await _client.getUrl(_url);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-${offset + count - 1}');
    final res = await req.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  @override
  Future<void> close() async => _client.close(force: true);
}

/// Buffered sequential EBML reader over a [_ByteSource]. Large element payloads
/// are skipped by advancing [position] without fetching bytes.
class _Reader {
  _Reader(this._source, this._length);

  final _ByteSource _source;
  final int _length;
  int position = 0;

  Uint8List _buf = Uint8List(0);
  int _bufStart = 0;
  static const int _chunkSize = 65536;

  bool _inBuffer(int pos) => pos >= _bufStart && pos < _bufStart + _buf.length;

  Future<void> _fill(int minCount) async {
    final remaining = _length - position;
    if (remaining <= 0) {
      _buf = Uint8List(0);
      _bufStart = position;
      return;
    }
    var toRead = minCount > _chunkSize ? minCount : _chunkSize;
    if (toRead > remaining) toRead = remaining;
    _buf = await _source.readAt(position, toRead);
    _bufStart = position;
  }

  Future<void> seekTo(int pos) async {
    position = pos;
  }

  Future<void> skip(int count) async {
    position += count;
  }

  Future<int> _readByte() async {
    if (position >= _length) return -1;
    if (!_inBuffer(position)) {
      await _fill(1);
      if (_buf.isEmpty) return -1;
    }
    final b = _buf[position - _bufStart];
    position += 1;
    return b;
  }

  Future<Uint8List> readBytes(int count) async {
    final out = Uint8List(count);
    var got = 0;
    while (got < count) {
      if (!_inBuffer(position)) {
        await _fill(count - got);
        if (_buf.isEmpty) break;
      }
      final avail = (_bufStart + _buf.length) - position;
      final take = (count - got) < avail ? (count - got) : avail;
      out.setRange(got, got + take, _buf, position - _bufStart);
      got += take;
      position += take;
    }
    return got == count ? out : Uint8List.sublistView(out, 0, got);
  }

  Future<int> readId() async {
    if (position >= _length) return _idEof;
    final first = await _readByte();
    if (first < 0) return _idEof;
    final length = _vintLength(first);
    if (length == 0 || length > 4) return _idEof;
    var value = first;
    for (var i = 1; i < length; i++) {
      final b = await _readByte();
      if (b < 0) return _idEof;
      value = (value << 8) | b;
    }
    return value;
  }

  Future<int> readSize() async {
    final first = await _readByte();
    if (first < 0) return _unknownSize;
    final length = _vintLength(first);
    if (length == 0) return _unknownSize;
    var value = first & (0xFF >> length);
    var allOnes = value == (0xFF >> length);
    for (var i = 1; i < length; i++) {
      final b = await _readByte();
      if (b < 0) return _unknownSize;
      if (b != 0xFF) allOnes = false;
      value = (value << 8) | b;
    }
    if (allOnes) return _unknownSize;
    return value;
  }

  Future<int> readVIntValue() async {
    final first = await _readByte();
    final length = _vintLength(first);
    var value = first & (0xFF >> length);
    for (var i = 1; i < length; i++) {
      final b = await _readByte();
      value = (value << 8) | b;
    }
    return value;
  }

  Future<int> readUInt(int size) async {
    var value = 0;
    for (var i = 0; i < size; i++) {
      final b = await _readByte();
      if (b < 0) break;
      value = (value << 8) | b;
    }
    return value;
  }

  Future<int> readSInt16() async {
    final hi = await _readByte();
    final lo = await _readByte();
    var value = (hi << 8) | lo;
    if (value >= 0x8000) value -= 0x10000;
    return value;
  }

  Future<String> readString(int size) async {
    final bytes = await readBytes(size);
    return utf8.decode(bytes, allowMalformed: true).replaceAll('\x00', '').trim();
  }

  static int _vintLength(int firstByte) {
    if (firstByte == 0) return 0;
    var mask = 0x80;
    var length = 1;
    while ((firstByte & mask) == 0 && length <= 8) {
      mask >>= 1;
      length++;
    }
    return length;
  }
}
