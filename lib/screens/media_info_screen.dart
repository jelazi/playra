import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/media_info.dart';
import '../models/video_item.dart';
import '../services/episode_continuation_service.dart';
import '../services/media_lookup_service.dart';
import '../services/playra_storage.dart';
import '../services/poster_cache_service.dart';
import '../services/tmdb_service.dart';
import '../services/video_hash_service.dart';
import '../services/video_name_parser.dart';
import 'player_launcher.dart';

/// Full-screen view that shows TMDB info (poster, title, overview) for a
/// [VideoItem] before the user decides to play it.
///
/// The lookup is done automatically on open. For TV episodes, localized
/// episode text is fetched from TMDB and machine-translated when needed.
class MediaInfoScreen extends StatefulWidget {
  final VideoItem video;

  const MediaInfoScreen({super.key, required this.video});

  @override
  State<MediaInfoScreen> createState() => _MediaInfoScreenState();
}

class _MediaInfoScreenState extends State<MediaInfoScreen> {
  late final MediaLookupService _lookup;
  bool _didInitialLookup = false;

  MediaInfo? _media;
  EpisodeInfo? _episode;
  ParsedVideoName? _parsed;
  String? _videoHash;
  VideoItem? _nextEpisode;
  bool _loading = true;
  bool _notFound = false;
  Color _appBarForeground = Colors.white;

  @override
  void initState() {
    super.initState();
    _lookup = MediaLookupService(TmdbService());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialLookup) return;
    _didInitialLookup = true;
    _startLookup();
  }

  Future<void> _startLookup() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });

    final language = context.locale.languageCode;
    _videoHash = await VideoHashService.hashForVideo(widget.video);
    if (_videoHash != null) {
      await PlayraStorage.bindVideoToHash(videoId: widget.video.id, hash: _videoHash!, title: widget.video.displayName, sizeBytes: widget.video.sizeBytes);
    }
    final result = await _lookup.lookupForFile(widget.video.uri, language, videoHash: _videoHash);

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _loading = false;
        _notFound = true;
        _parsed = VideoNameParser.parse(widget.video.uri);
      });
      return;
    }

    _media = result.mediaInfo;
    _parsed = result.parsed;

    // Adapt app bar foreground (title/back/edit icons) to the backdrop image.
    _updateAppBarForegroundFromBackdrop(result.mediaInfo.backdropUrl);

    // Keep a local small poster for recents cards.
    final posterPath = await PosterCacheService.cacheSmallPoster(result.mediaInfo);
    if (posterPath != null) {
      await PlayraStorage.saveRecentPosterPath(widget.video, posterPath);
    }

    // Pre-compute next episode suggestion for local TV files.
    _nextEpisode = await EpisodeContinuationService.findNextEpisode(widget.video);

    // For TV episodes, also load the English episode synopsis.
    if (result.mediaInfo.type == MediaType.tv && result.parsed.isTV && result.parsed.season != null && result.parsed.episode != null) {
      final ep = await _lookup.fetchEpisodeInfo(result.mediaInfo.id, result.parsed.season!, result.parsed.episode!, language);
      if (mounted) _episode = ep;
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _updateAppBarForegroundFromBackdrop(String backdropUrl) async {
    if (backdropUrl.isEmpty) {
      if (!mounted) return;
      setState(() => _appBarForeground = Theme.of(context).colorScheme.onSurface);
      return;
    }

    try {
      final byteData = await NetworkAssetBundle(Uri.parse(backdropUrl)).load(backdropUrl);
      final bytes = byteData.buffer.asUint8List();

      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 28, targetHeight: 28);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();

      if (rgba == null) return;

      final data = rgba.buffer.asUint8List();
      double luminanceSum = 0;
      int count = 0;
      for (int i = 0; i <= data.length - 4; i += 4) {
        final r = data[i] / 255.0;
        final g = data[i + 1] / 255.0;
        final b = data[i + 2] / 255.0;

        final linearR = r <= 0.03928 ? r / 12.92 : ((r + 0.055) / 1.055);
        final linearG = g <= 0.03928 ? g / 12.92 : ((g + 0.055) / 1.055);
        final linearB = b <= 0.03928 ? b / 12.92 : ((b + 0.055) / 1.055);
        final l = 0.2126 * linearR + 0.7152 * linearG + 0.0722 * linearB;
        luminanceSum += l;
        count++;
      }

      if (count == 0 || !mounted) return;
      final avgLuminance = luminanceSum / count;

      setState(() {
        _appBarForeground = avgLuminance < 0.46 ? Colors.white : Colors.black87;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _appBarForeground = Colors.white);
    }
  }

  Future<void> _play() async {
    // Save to recent before navigating to player.
    await PlayraStorage.addRecent(widget.video);
    if (!mounted) return;
    await context.read<PlayerLauncher>().launch(context, widget.video);
    // Refresh parent (home) after returning so recents shows.
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _playNextEpisode() async {
    final next = _nextEpisode;
    if (next == null) return;
    await PlayraStorage.addRecent(next);
    if (!mounted) return;
    await context.read<PlayerLauncher>().launch(context, next);
  }

  void _showManualSearch() async {
    final picked = await _showSearchDialog();
    if (picked == null || !mounted) return;
    await _lookup.saveMapping(widget.video.uri, picked);
    // Reload from cache.
    await _startLookup();
  }

  void _showRenameSearch() async {
    final initial = _parsed?.cleanName.isNotEmpty == true ? _parsed!.cleanName : VideoNameParser.parse(widget.video.uri).cleanName;
    final controller = TextEditingController(text: initial);

    final customQuery = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('video.change_search_name'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: 'video.manual_search_hint'.tr()),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('common.cancel'.tr())),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: Text('common.ok'.tr())),
        ],
      ),
    );

    if (customQuery == null || customQuery.trim().isEmpty) return;
    final picked = await _showSearchDialog(initialQuery: customQuery.trim());
    if (picked == null || !mounted) return;
    await _lookup.saveMapping(widget.video.uri, picked);
    await _startLookup();
  }

  Future<MediaInfo?> _showSearchDialog({String? initialQuery}) async {
    final controller = TextEditingController(text: initialQuery ?? VideoNameParser.parse(widget.video.uri).cleanName);
    List<MediaInfo> results = [];
    bool searching = false;
    MediaInfo? picked;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('video.manual_search'.tr()),
          content: SizedBox(
            width: double.maxFinite,
            height: 480,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'video.manual_search_hint'.tr(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () async {
                        if (controller.text.trim().isEmpty) return;
                        setS(() {
                          searching = true;
                          results = [];
                        });
                        final lang = ctx.locale.languageCode;
                        final res = await _lookup.searchCandidates(controller.text.trim(), lang);
                        setS(() {
                          results = res;
                          searching = false;
                        });
                      },
                    ),
                  ),
                  onSubmitted: (v) async {
                    if (v.trim().isEmpty) return;
                    setS(() {
                      searching = true;
                      results = [];
                    });
                    final lang = ctx.locale.languageCode;
                    final res = await _lookup.searchCandidates(v.trim(), lang);
                    setS(() {
                      results = res;
                      searching = false;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: searching
                      ? const Center(child: CircularProgressIndicator())
                      : results.isEmpty
                      ? Center(
                          child: Text('video.manual_search_hint'.tr(), style: const TextStyle(color: Colors.grey)),
                        )
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final m = results[i];
                            final year = (m.releaseDate != null && m.releaseDate!.length >= 4) ? m.releaseDate!.substring(0, 4) : '?';
                            return ListTile(
                              leading: m.posterPath != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        m.posterUrl,
                                        width: 36,
                                        height: 54,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const SizedBox(width: 36, height: 54),
                                      ),
                                    )
                                  : const SizedBox(width: 36),
                              title: Text(m.title),
                              subtitle: Text(
                                '$year · '
                                '${m.type == MediaType.movie ? 'Film' : 'Seriál'} · '
                                '⭐ ${m.voteAverage?.toStringAsFixed(1) ?? '?'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onTap: () {
                                picked = m;
                                Navigator.of(ctx).pop();
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('common.cancel'.tr()))],
        ),
      ),
    );
    return picked;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notFound
          ? _buildNotFound()
          : _buildContent(),
    );
  }

  Widget _buildNotFound() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(floating: true, title: Text(widget.video.displayName, maxLines: 1, overflow: TextOverflow.ellipsis)),
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.movie_outlined, size: 72, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('video.media_not_found'.tr(), style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(icon: const Icon(Icons.search), label: Text('video.manual_search'.tr()), onPressed: _showManualSearch),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(icon: const Icon(Icons.edit), label: Text('video.change_search_name'.tr()), onPressed: _showRenameSearch),
                      const SizedBox(width: 12),
                      FilledButton.icon(icon: const Icon(Icons.play_arrow), label: Text('video.play'.tr()), onPressed: _play),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final media = _media!;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return CustomScrollView(
      slivers: [
        // Backdrop / AppBar
        SliverAppBar(
          expandedHeight: isPortrait ? 220 : 0,
          pinned: true,
          foregroundColor: _appBarForeground,
          flexibleSpace: media.backdropUrl.isNotEmpty
              ? FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(media.backdropUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          title: Text(media.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(icon: const Icon(Icons.edit), tooltip: 'video.edit_media_info'.tr(), onPressed: _showManualSearch),
            IconButton(icon: const Icon(Icons.drive_file_rename_outline), tooltip: 'video.change_search_name'.tr(), onPressed: _showRenameSearch),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster + basic info row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (media.posterUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(media.posterUrl, width: 120, height: 180, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      ),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(media.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                          if (media.originalTitle != media.title) ...[
                            const SizedBox(height: 4),
                            Text(
                              media.originalTitle,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: Colors.grey),
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (media.voteAverage != null)
                            Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 18),
                                const SizedBox(width: 4),
                                Text(media.voteAverage!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(' / 10', style: TextStyle(color: Colors.grey[600])),
                              ],
                            ),
                          const SizedBox(height: 6),
                          if (media.type == MediaType.movie && media.releaseDate != null)
                            _infoChip(Icons.calendar_today, media.releaseDate!.length >= 4 ? media.releaseDate!.substring(0, 4) : media.releaseDate!),
                          if (media.type == MediaType.tv) ...[
                            if (media.numberOfSeasons != null) _infoChip(Icons.tv, '${media.numberOfSeasons} ${'video.seasons'.tr()}'),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // Genres
                if (media.genres.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: media.genres.map((g) => Chip(label: Text(g), visualDensity: VisualDensity.compact)).toList(),
                  ),
                ],

                // Overview
                if (media.overview != null && media.overview!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('video.overview'.tr(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(media.overview!, style: const TextStyle(height: 1.5)),
                ],

                // Episode info (TV)
                if (_episode != null) ...[
                  const Divider(height: 32),
                  Row(
                    children: [
                      const Icon(Icons.video_file, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'S${_parsed!.season!.toString().padLeft(2, '0')}'
                          'E${_parsed!.episode!.toString().padLeft(2, '0')}'
                          '${_episode!.name != null ? "  ${_episode!.name}" : ""}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (_episode!.overview != null && _episode!.overview!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_episode!.overview!, style: const TextStyle(height: 1.5)),
                  ],
                  if (_episode!.voteAverage != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(_episode!.voteAverage!.toStringAsFixed(1)),
                      ],
                    ),
                  ],
                ],

                if (_nextEpisode != null) ...[
                  const Divider(height: 32),
                  FilledButton.tonalIcon(onPressed: _playNextEpisode, icon: const Icon(Icons.skip_next), label: Text('video.continue_next_episode'.tr())),
                  const SizedBox(height: 8),
                  Text(_nextEpisode!.displayName, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Play FAB overlay – always visible at the bottom
// ---------------------------------------------------------------------------

/// Wraps [MediaInfoScreen] and adds a sticky "Play" button at the bottom.
class MediaInfoRoute extends StatelessWidget {
  final VideoItem video;

  const MediaInfoRoute({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return _MediaInfoRouteState(video: video);
  }
}

class _MediaInfoRouteState extends StatelessWidget {
  final VideoItem video;
  const _MediaInfoRouteState({required this.video});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MediaInfoScreen(video: video),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text('video.play'.tr()),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () async {
              // Add to recent
              await PlayraStorage.addRecent(video);
              if (!context.mounted) return;
              await context.read<PlayerLauncher>().launch(context, video);
              // Pop after returning from player
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }
}
