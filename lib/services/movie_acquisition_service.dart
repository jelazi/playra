import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/player_settings.dart';
import '../models/torrent_stream.dart';
import 'http_download_service.dart';
import 'real_debrid_service.dart';
import 'smb_download_service.dart';

void _log(String msg) => debugPrint('[playra.acquire] $msg');

/// Error codes the UI can map to localized messages.
enum AcquisitionError { missingRealDebridKey, torrentUnavailable, torrentStreamingDisabled, realDebridFailed, unknown }

class AcquisitionException implements Exception {
  final AcquisitionError code;
  final String message;
  const AcquisitionException(this.code, this.message);

  @override
  String toString() => 'AcquisitionException($code): $message';
}

/// Resolves a [TorrentStream] into a play-ready URL, or downloads it locally.
/// Implementations are platform-specific (Real-Debrid vs native torrent).
abstract class MovieAcquisitionService {
  /// Returns a URL ready to hand to the player (direct HTTPS or local proxy).
  Future<String> resolveStreamUrl(TorrentStream stream, {void Function(String status)? onStatus});

  /// Downloads [stream] into the app's downloads folder; returns the local path.
  Future<String> download(
    TorrentStream stream, {
    void Function(int received, int total, String fileName)? onProgress,
    DownloadCancellationToken? cancellationToken,
  });
}

/// Picks the right [MovieAcquisitionService] based on settings + platform.
///
/// `auto`: Real-Debrid on mobile, native torrent on desktop (when available).
/// Falls back to Real-Debrid when the native torrent client is not wired in yet.
class AcquisitionResolver {
  AcquisitionResolver({this.torrentBuilder});

  /// Optional factory for the native torrent implementation (Phase 2). When
  /// null, torrent acquisition is considered unavailable.
  final MovieAcquisitionService Function()? torrentBuilder;

  MovieAcquisitionService resolve(PlayerSettings settings) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final hasRdKey = settings.realDebridApiKey.trim().isNotEmpty;
    _log('resolve: mode=${settings.acquisitionMode} mobile=$isMobile hasRdKey=$hasRdKey torrentAvailable=${torrentBuilder != null}');

    MovieAcquisitionService realDebrid() {
      if (!hasRdKey) {
        throw const AcquisitionException(AcquisitionError.missingRealDebridKey, 'Real-Debrid API key is not set');
      }
      return RealDebridAcquisitionService(RealDebridService(apiKey: settings.realDebridApiKey.trim()));
    }

    MovieAcquisitionService torrent() {
      final builder = torrentBuilder;
      if (builder == null) {
        // Phase 2 not active: gracefully fall back to Real-Debrid if possible.
        if (hasRdKey) return realDebrid();
        throw const AcquisitionException(AcquisitionError.torrentUnavailable, 'Native torrent client is not available');
      }
      return builder();
    }

    switch (settings.acquisitionMode) {
      case 'torrent':
        return torrent();
      case 'realdebrid':
        return realDebrid();
      case 'auto':
      default:
        return isMobile ? realDebrid() : torrent();
    }
  }
}

/// Real-Debrid implementation: resolves an unrestricted direct URL, then either
/// streams it directly or downloads it via [HttpDownloadService].
class RealDebridAcquisitionService implements MovieAcquisitionService {
  RealDebridAcquisitionService(this._rd);

  final RealDebridService _rd;

  @override
  Future<String> resolveStreamUrl(TorrentStream stream, {void Function(String status)? onStatus}) {
    return _rd.resolveDirectUrl(stream, onStatus: onStatus);
  }

  @override
  Future<String> download(
    TorrentStream stream, {
    void Function(int received, int total, String fileName)? onProgress,
    DownloadCancellationToken? cancellationToken,
  }) async {
    final directUrl = await _rd.resolveDirectUrl(stream);
    final fileName = _deriveFileName(stream, directUrl);
    return HttpDownloadService.downloadUrl(
      url: directUrl,
      fileName: fileName,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
  }

  String _deriveFileName(TorrentStream stream, String url) {
    final fromHint = stream.fileName;
    if (fromHint != null && fromHint.trim().isNotEmpty) return fromHint.trim();

    // Try the URL's last path segment (Real-Debrid keeps the original name).
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    if (segments.isNotEmpty && p.extension(segments.last).isNotEmpty) {
      return Uri.decodeComponent(segments.last);
    }

    final base = stream.releaseName.isNotEmpty ? stream.releaseName : 'movie';
    return '$base.mp4';
  }
}
