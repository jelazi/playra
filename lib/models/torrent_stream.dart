/// A single playable source returned by the Torrentio addon for a movie/episode.
///
/// Torrentio returns either torrent streams (`infoHash` + `fileIdx` + `sources`)
/// or, when a debrid provider is configured, direct HTTPS `url`s.
class TorrentStream {
  /// Short label, e.g. "Torrentio 1080p" (Torrentio puts the provider + quality here).
  final String name;

  /// Full descriptive title containing the release name, seeders, size and source.
  final String title;

  /// BitTorrent info hash (40-char hex). Empty when only a direct [url] is provided.
  final String infoHash;

  /// Index of the target file within the torrent (for multi-file torrents).
  final int fileIdx;

  /// Tracker / DHT hints (`tracker:udp://...`, `dht:<hash>`), used to build a magnet.
  final List<String> sources;

  /// Direct HTTPS URL (only present when Torrentio is configured with a debrid key).
  final String? url;

  /// Suggested file name, when Torrentio provides it via behaviorHints.
  final String? fileName;

  // Parsed from [title] for display/filtering.
  final String quality; // e.g. '1080p', '2160p', or '' when unknown
  final int? seeders;
  final int? sizeBytes;

  const TorrentStream({
    required this.name,
    required this.title,
    required this.infoHash,
    required this.fileIdx,
    required this.sources,
    this.url,
    this.fileName,
    this.quality = '',
    this.seeders,
    this.sizeBytes,
  });

  bool get hasDirectUrl => url != null && url!.isNotEmpty;
  bool get hasInfoHash => infoHash.isNotEmpty;

  /// The release name (first line of [title]); falls back to [name].
  String get releaseName {
    final firstLine = title.split('\n').first.trim();
    return firstLine.isNotEmpty ? firstLine : name.replaceAll('\n', ' ').trim();
  }

  factory TorrentStream.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as String?) ?? (json['name'] as String?) ?? '';
    final behaviorHints = json['behaviorHints'] as Map<String, dynamic>?;
    return TorrentStream(
      name: (json['name'] as String?) ?? '',
      title: title,
      infoHash: (json['infoHash'] as String?) ?? '',
      fileIdx: (json['fileIdx'] as num?)?.toInt() ?? 0,
      sources: (json['sources'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      url: json['url'] as String?,
      fileName: behaviorHints?['filename'] as String?,
      quality: _parseQuality(title) ?? _parseQuality(json['name'] as String? ?? '') ?? '',
      seeders: _parseSeeders(title),
      sizeBytes: _parseSize(title),
    );
  }

  static final RegExp _qualityRe = RegExp(r'\b(2160p|1440p|1080p|720p|480p|360p)\b', caseSensitive: false);
  static final RegExp _seedersRe = RegExp(r'\u{1F464}\s*(\d+)', unicode: true); // 👤 123
  static final RegExp _sizeRe = RegExp(r'\u{1F4BE}\s*([\d.,]+)\s*(GB|MB)', unicode: true, caseSensitive: false); // 💾 2.5 GB

  static String? _parseQuality(String text) {
    final m = _qualityRe.firstMatch(text);
    return m?.group(1)?.toLowerCase();
  }

  static int? _parseSeeders(String text) {
    final m = _seedersRe.firstMatch(text);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static int? _parseSize(String text) {
    final m = _sizeRe.firstMatch(text);
    if (m == null) return null;
    final value = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (value == null) return null;
    final unit = m.group(2)!.toUpperCase();
    final multiplier = unit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
    return (value * multiplier).round();
  }

  String get formattedSize {
    final bytes = sizeBytes;
    if (bytes == null) return '';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
