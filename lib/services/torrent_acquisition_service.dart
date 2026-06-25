import '../models/torrent_stream.dart';
import 'movie_acquisition_service.dart';
import 'smb_download_service.dart';
import 'torrent_client_service.dart';
import 'torrent_proxy_server.dart';

/// Native (desktop) torrent implementation of [MovieAcquisitionService], backed
/// by aria2. Supports both downloading and progressive streaming (served from
/// the growing on-disk file through a local proxy).
class TorrentAcquisitionService implements MovieAcquisitionService {
  TorrentAcquisitionService({TorrentClientService? client, TorrentProxyServer? proxy})
      : _client = client ?? TorrentClientService(),
        _proxy = proxy ?? TorrentProxyServer();

  final TorrentClientService _client;
  final TorrentProxyServer _proxy;

  @override
  Future<String> resolveStreamUrl(TorrentStream stream, {void Function(String status)? onStatus}) async {
    onStatus?.call('adding');
    final handle = await _client.openStream(stream);
    onStatus?.call('caching');
    await _proxy.start();
    return _proxy.register(handle);
  }

  @override
  Future<String> download(
    TorrentStream stream, {
    void Function(int received, int total, String fileName)? onProgress,
    DownloadCancellationToken? cancellationToken,
  }) {
    return _client.download(stream, onProgress: onProgress, cancellationToken: cancellationToken);
  }

  Future<void> dispose() async {
    await _proxy.stop();
    await _client.dispose();
  }
}
