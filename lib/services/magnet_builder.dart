import '../models/torrent_stream.dart';

/// Builds magnet URIs from Torrentio streams, adding fallback public trackers
/// since DHT-only bootstrapping is slow and unreliable.
class MagnetBuilder {
  /// A small set of well-known public UDP trackers used as a fallback.
  static const List<String> fallbackTrackers = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.tracker.cl:1337/announce',
    'udp://tracker.openbittorrent.com:6969/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.torrent.eu.org:451/announce',
  ];

  /// Builds a `magnet:?xt=urn:btih:...` URI for [stream].
  static String fromStream(TorrentStream stream) {
    final trackers = <String>{...fallbackTrackers};
    for (final source in stream.sources) {
      if (source.startsWith('tracker:')) {
        trackers.add(source.substring('tracker:'.length));
      }
    }

    final buffer = StringBuffer('magnet:?xt=urn:btih:${stream.infoHash}');
    final name = stream.releaseName;
    if (name.isNotEmpty) {
      buffer.write('&dn=${Uri.encodeComponent(name)}');
    }
    for (final tracker in trackers) {
      buffer.write('&tr=${Uri.encodeComponent(tracker)}');
    }
    return buffer.toString();
  }
}
