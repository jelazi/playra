import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../models/media_info.dart';
import '../models/server_connection.dart';
import 'playra_storage.dart';
import 'smb_browser_service.dart';
import 'video_name_parser.dart';

/// File access for the folder a video lives in: the local file system or an
/// SMB share.
abstract class SidecarStore {
  p.Context get paths;

  /// Null when the file does not exist.
  Future<String?> readText(String path);

  Future<bool> exists(String path);

  Future<void> write(String path, List<int> bytes);
}

class LocalSidecarStore implements SidecarStore {
  const LocalSidecarStore();

  @override
  p.Context get paths => p.context;

  @override
  Future<String?> readText(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<void> write(String path, List<int> bytes) => File(path).writeAsBytes(bytes, flush: true);
}

class SmbSidecarStore implements SidecarStore {
  SmbSidecarStore(this._smb, this._server);

  final SmbBrowserService _smb;
  final ServerConnection _server;

  @override
  p.Context get paths => p.posix;

  @override
  Future<String?> readText(String path) async {
    final bytes = await _smb.readSmallFile(_server, path);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<bool> exists(String path) => _smb.exists(_server, path);

  @override
  Future<void> write(String path, List<int> bytes) => _smb.writeFile(_server, path, bytes);
}

/// What the sidecar files next to a video say it is.
class MediaSidecar {
  final MediaInfo media;
  final EpisodeInfo? episode;

  const MediaSidecar({required this.media, this.episode});
}

typedef SidecarLocation = ({SidecarStore store, String path});

/// Kodi-style `.nfo` files and posters next to the videos, so every Playra
/// install (and Kodi, Jellyfin, Emby, Infuse) reuses one identification
/// instead of looking the file up again.
///
/// - Movie: `<video>.nfo` (`<movie>`) and `<video>-poster.jpg`.
/// - Series: `tvshow.nfo` and `poster.jpg` in the series folder, plus
///   `<video>.nfo` (`<episodedetails>`) for every episode.
class MediaSidecarService {
  MediaSidecarService({SidecarLocation? Function(String videoUri)? locate, Future<List<int>?> Function(String url)? download})
    : _locate = locate ?? _defaultLocate,
      _download = download ?? _downloadImage;

  final SidecarLocation? Function(String videoUri) _locate;
  final Future<List<int>?> Function(String url) _download;

  static final SmbBrowserService _smb = SmbBrowserService();
  static final Dio _dio = Dio()
    ..options.connectTimeout = const Duration(seconds: 10)
    ..options.receiveTimeout = const Duration(seconds: 20);

  // One SMB connection is shared by every sidecar operation, so they run one at a time.
  static Future<void> _queue = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<MediaSidecar?> read(String videoUri, ParsedVideoName parsed) async {
    final location = _locate(videoUri);
    if (location == null) return null;
    try {
      return await _serialized(() => _read(location.store, location.path, parsed));
    } catch (e) {
      debugPrint('MediaSidecar: reading next to $videoUri failed ($e)');
      return null;
    }
  }

  /// Writes the sidecar files for [media]; files that already exist are kept
  /// unless [overwrite] is set. Returns false when writing failed.
  Future<bool> write(String videoUri, ParsedVideoName parsed, MediaInfo media, {EpisodeInfo? episode, bool overwrite = false}) async {
    final location = _locate(videoUri);
    if (location == null) return false;
    try {
      await _serialized(() => _write(location.store, location.path, parsed, media, episode, overwrite));
      return true;
    } catch (e) {
      debugPrint('MediaSidecar: writing next to $videoUri failed ($e)');
      return false;
    }
  }

  static SidecarLocation? _defaultLocate(String videoUri) {
    if (videoUri.startsWith('smb://')) {
      final rest = videoUri.substring(6);
      final slash = rest.indexOf('/');
      if (slash <= 0) return null;
      final serverId = rest.substring(0, slash);
      final server = PlayraStorage.getServers().where((s) => s.id == serverId).firstOrNull;
      if (server == null) return null;
      return (store: SmbSidecarStore(_smb, server), path: rest.substring(slash));
    }
    if (videoUri.contains('://')) return null;
    return (store: const LocalSidecarStore(), path: videoUri);
  }

  static Future<List<int>?> _downloadImage(String url) async {
    final response = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    return response.data;
  }

  Future<MediaSidecar?> _read(SidecarStore store, String video, ParsedVideoName parsed) async {
    final paths = store.paths;
    final own = _Nfo.parse(await store.readText(paths.setExtension(video, '.nfo')));

    if (own?.kind == 'movie') {
      final media = own!.toMedia(MediaType.movie);
      return media == null ? null : MediaSidecar(media: media);
    }

    final isEpisode = own?.kind == 'episodedetails' || parsed.isTV;
    if (!isEpisode) {
      final folderMovie = _Nfo.parse(await store.readText(paths.join(paths.dirname(video), 'movie.nfo')));
      final media = folderMovie?.kind == 'movie' ? folderMovie!.toMedia(MediaType.movie) : null;
      return media == null ? null : MediaSidecar(media: media);
    }

    final episode = own?.kind == 'episodedetails' ? own!.toEpisode(parsed) : null;
    final dir = paths.dirname(video);
    final folders = {
      seriesFolder(paths, video, [parsed.cleanName]),
      dir,
      paths.dirname(dir),
    }.where((f) => f != paths.rootPrefix(f));
    for (final folder in folders) {
      final show = _Nfo.parse(await store.readText(paths.join(folder, 'tvshow.nfo')));
      final media = show?.kind == 'tvshow' ? show!.toMedia(MediaType.tv) : null;
      if (media != null) return MediaSidecar(media: media, episode: episode);
    }
    return null;
  }

  Future<void> _write(SidecarStore store, String video, ParsedVideoName parsed, MediaInfo media, EpisodeInfo? episode, bool overwrite) async {
    final paths = store.paths;
    final videoNfo = paths.setExtension(video, '.nfo');

    if (media.type == MediaType.movie) {
      await _writeUnlessPresent(store, videoNfo, () => _movieXml(media), overwrite);
      await _writePoster(store, '${paths.withoutExtension(video)}-poster.jpg', media, overwrite);
      return;
    }

    final showFolder = seriesFolder(paths, video, [parsed.cleanName, media.title, media.originalTitle]);
    await _writeUnlessPresent(store, paths.join(showFolder, 'tvshow.nfo'), () => _showXml(media), overwrite);
    await _writePoster(store, paths.join(showFolder, 'poster.jpg'), media, overwrite);

    final season = episode?.season ?? parsed.season;
    final number = episode?.episode ?? parsed.episode;
    if (season == null || number == null) return;

    if (!overwrite) {
      final existing = await store.readText(videoNfo);
      if (existing != null) {
        // An episode file left over from a show that has since been corrected is replaced; anything else is kept.
        final showTitle = _Nfo.parse(existing)?.text('showtitle');
        if (showTitle == null || showTitle == media.title || showTitle == media.originalTitle) return;
      }
    }
    await store.write(videoNfo, utf8.encode(_episodeXml(media, season, number, episode)));
  }

  Future<void> _writeUnlessPresent(SidecarStore store, String path, String Function() content, bool overwrite) async {
    if (!overwrite && await store.exists(path)) return;
    await store.write(path, utf8.encode(content()));
  }

  Future<void> _writePoster(SidecarStore store, String path, MediaInfo media, bool overwrite) async {
    final posterPath = media.posterPath;
    if (posterPath == null || posterPath.isEmpty) return;
    if (!overwrite && await store.exists(path)) return;
    try {
      final bytes = await _download('https://image.tmdb.org/t/p/w780$posterPath');
      if (bytes == null || bytes.isEmpty) return;
      await store.write(path, bytes);
    } catch (e) {
      debugPrint('MediaSidecar: poster $path not saved ($e)');
    }
  }

  /// The folder that holds `tvshow.nfo`: the parent of a season folder
  /// ("Season 1", "S01", "1. série", or "Show.S01.1080p" inside a folder named
  /// after the show), otherwise the video's own folder.
  @visibleForTesting
  static String seriesFolder(p.Context paths, String videoPath, Iterable<String> showTitles) {
    final dir = paths.dirname(videoPath);
    final parent = paths.dirname(dir);
    if (parent == dir || parent == paths.rootPrefix(parent)) return dir;

    final name = paths.basename(dir);
    if (_isSeasonOnlyName(name)) return parent;
    if (_seasonMarker.hasMatch(name) && _matchesShow(paths.basename(parent), showTitles)) return parent;
    return dir;
  }

  static final RegExp _seasonWords = RegExp(r'season|series|serie|série|sezona|sezóna|řada|rada|staffel|saison|temporada', caseSensitive: false);

  static final RegExp _seasonMarker = RegExp(
    r'(^|[\s._\-\[(])(s\d{1,2}|(season|series|serie|série|sezona|sezóna|řada)[\s._\-]*\d{1,2}|\d{1,2}[\s._\-]*\.?[\s._\-]*(série|serie|řada|season))(?![\deE])',
    caseSensitive: false,
  );

  static bool _isSeasonOnlyName(String name) {
    final trimmed = name.trim();
    if (!RegExp(r'\d').hasMatch(trimmed)) return false;
    if (!_seasonWords.hasMatch(trimmed) && !RegExp(r'^[sS]\d{1,3}$').hasMatch(trimmed)) return false;
    final rest = trimmed.replaceAll(_seasonWords, '').replaceAll(RegExp(r'(^|[\s._\-])[sS](?=\d)'), ' ').replaceAll(RegExp(r'[\d\s._\-]'), '');
    return rest.isEmpty;
  }

  static String _normalize(String value) => value.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  static bool _matchesShow(String folderName, Iterable<String> showTitles) {
    final folder = _normalize(VideoNameParser.cleanTitle(folderName));
    if (folder.isEmpty) return false;
    return showTitles.map(_normalize).any((title) => title.isNotEmpty && (title.startsWith(folder) || folder.startsWith(title)));
  }

  static String _movieXml(MediaInfo media) => _document('movie', (b) {
    _element(b, 'title', media.title);
    _element(b, 'originaltitle', media.originalTitle);
    _element(b, 'year', _year(media.releaseDate));
    _element(b, 'premiered', media.releaseDate);
    _element(b, 'plot', media.overview);
    _commonMetadata(b, media);
  });

  static String _showXml(MediaInfo media) => _document('tvshow', (b) {
    final premiered = media.firstAirDate ?? media.releaseDate;
    _element(b, 'title', media.title);
    _element(b, 'originaltitle', media.originalTitle);
    _element(b, 'year', _year(premiered));
    _element(b, 'premiered', premiered);
    _element(b, 'plot', media.overview);
    _element(b, 'season', media.numberOfSeasons);
    _element(b, 'episode', media.numberOfEpisodes);
    _commonMetadata(b, media);
  });

  static String _episodeXml(MediaInfo show, int season, int number, EpisodeInfo? episode) => _document('episodedetails', (b) {
    _element(b, 'title', episode?.name);
    _element(b, 'showtitle', show.title);
    _element(b, 'season', season);
    _element(b, 'episode', number);
    _element(b, 'plot', episode?.overview);
    _element(b, 'aired', episode?.airDate);
    _ratings(b, episode?.voteAverage);
    if (episode != null && episode.stillUrl.isNotEmpty) _element(b, 'thumb', episode.stillUrl);
  });

  static void _commonMetadata(XmlBuilder b, MediaInfo media) {
    for (final genre in media.genres) {
      _element(b, 'genre', genre);
    }
    _ratings(b, media.voteAverage);
    _element(b, 'uniqueid', media.id, attributes: const {'type': 'tmdb', 'default': 'true'});
    if (media.posterUrl.isNotEmpty) _element(b, 'thumb', media.posterUrl, attributes: const {'aspect': 'poster'});
    if (media.backdropUrl.isNotEmpty) b.element('fanart', nest: () => _element(b, 'thumb', media.backdropUrl));
  }

  static void _ratings(XmlBuilder b, double? value) {
    if (value == null) return;
    b.element(
      'ratings',
      nest: () => b.element(
        'rating',
        attributes: const {'name': 'themoviedb', 'max': '10', 'default': 'true'},
        nest: () => _element(b, 'value', value.toStringAsFixed(1)),
      ),
    );
  }

  static String _document(String root, void Function(XmlBuilder b) body) {
    final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
    b.element(root, nest: () => body(b));
    return b.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  static void _element(XmlBuilder b, String name, Object? value, {Map<String, String> attributes = const {}}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return;
    b.element(name, attributes: attributes, nest: text);
  }

  static String? _year(String? date) => date != null && date.length >= 4 ? date.substring(0, 4) : null;
}

class _Nfo {
  _Nfo(this.root);

  final XmlElement root;

  String get kind => root.name.local;

  /// Kodi also accepts "hybrid" files with a scraper URL after the XML, so
  /// the root element is cut out when the whole text does not parse.
  static _Nfo? parse(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      return _Nfo(XmlDocument.parse(text).rootElement);
    } catch (_) {
      final match = RegExp(r'<(movie|tvshow|episodedetails)[\s>][\s\S]*</\1>').firstMatch(text);
      if (match == null) return null;
      try {
        return _Nfo(XmlDocument.parse(match.group(0)!).rootElement);
      } catch (_) {
        return null;
      }
    }
  }

  String? text(String name) {
    final value = root.getElement(name)?.innerText.trim();
    return value == null || value.isEmpty ? null : value;
  }

  int? get tmdbId {
    for (final id in root.findElements('uniqueid')) {
      if (id.getAttribute('type')?.toLowerCase() == 'tmdb') return int.tryParse(id.innerText.trim());
    }
    return int.tryParse(text('tmdbid') ?? '');
  }

  double? get rating {
    for (final rating in root.getElement('ratings')?.findElements('rating') ?? const <XmlElement>[]) {
      final value = double.tryParse(rating.getElement('value')?.innerText.trim() ?? '');
      if (value != null) return value;
    }
    return double.tryParse(text('rating') ?? '');
  }

  String? get _posterUrl {
    final thumbs = root.findElements('thumb').toList();
    final poster = thumbs.where((t) => t.getAttribute('aspect') == 'poster').firstOrNull ?? thumbs.firstOrNull;
    return poster?.innerText.trim();
  }

  String? get _fanartUrl => root.getElement('fanart')?.getElement('thumb')?.innerText.trim();

  /// "https://image.tmdb.org/t/p/w500/abc.jpg" → "/abc.jpg", the form [MediaInfo] stores.
  static String? _tmdbImagePath(String? url) {
    if (url == null) return null;
    final match = RegExp(r'image\.tmdb\.org/t/p/[^/]+(/.+)$').firstMatch(url);
    return match?.group(1);
  }

  MediaInfo? toMedia(MediaType type) {
    final id = tmdbId;
    if (id == null) return null;
    final premiered = text('premiered') ?? text('aired') ?? text('year');
    return MediaInfo(
      id: id,
      title: text('title') ?? '',
      originalTitle: text('originaltitle') ?? text('title') ?? '',
      overview: text('plot'),
      posterPath: _tmdbImagePath(_posterUrl),
      backdropPath: _tmdbImagePath(_fanartUrl),
      releaseDate: premiered,
      voteAverage: rating,
      genres: root.findElements('genre').map((g) => g.innerText.trim()).where((g) => g.isNotEmpty).toList(),
      type: type,
      numberOfSeasons: type == MediaType.tv ? int.tryParse(text('season') ?? '') : null,
      numberOfEpisodes: type == MediaType.tv ? int.tryParse(text('episode') ?? '') : null,
      firstAirDate: type == MediaType.tv ? premiered : null,
    );
  }

  EpisodeInfo? toEpisode(ParsedVideoName parsed) {
    final season = int.tryParse(text('season') ?? '') ?? parsed.season;
    final episode = int.tryParse(text('episode') ?? '') ?? parsed.episode;
    if (season == null || episode == null) return null;
    return EpisodeInfo(
      season: season,
      episode: episode,
      name: text('title'),
      overview: text('plot'),
      stillPath: _tmdbImagePath(text('thumb')),
      voteAverage: rating,
      airDate: text('aired'),
    );
  }
}
