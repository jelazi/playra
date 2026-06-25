import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/downloads/downloads_cubit.dart';
import '../../bloc/streams/streams_cubit.dart';
import '../../models/cinemeta_meta.dart';
import '../../models/torrent_stream.dart';
import '../../models/video_item.dart';
import '../../services/movie_acquisition_service.dart';
import '../../services/playra_storage.dart';
import '../../services/torrentio_service.dart';
import '../player_launcher.dart';

/// Shows the list of Torrentio streams for [meta] with Stream / Download actions.
Future<void> showStreamSelectionSheet(BuildContext context, CinemetaMeta meta) {
  final torrentio = context.read<TorrentioService>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) => BlocProvider(
      create: (_) => StreamsCubit(torrentio)..loadMovie(meta.imdbId),
      child: _StreamSelectionSheet(meta: meta),
    ),
  );
}

class _StreamSelectionSheet extends StatelessWidget {
  const _StreamSelectionSheet({required this.meta});

  final CinemetaMeta meta;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      meta.year != null ? '${meta.name} (${meta.year})' : meta.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: BlocBuilder<StreamsCubit, StreamsState>(
                builder: (context, state) {
                  switch (state.status) {
                    case StreamsStatus.loading:
                      return const Center(child: CircularProgressIndicator());
                    case StreamsStatus.error:
                      return _message(context, Icons.error_outline, 'movies.streams_error'.tr(args: [state.error ?? '']));
                    case StreamsStatus.empty:
                      return _message(context, Icons.search_off, 'movies.streams_empty'.tr());
                    case StreamsStatus.results:
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: state.streams.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) => _StreamTile(meta: meta, stream: state.streams[index]),
                      );
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _message(BuildContext context, IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _StreamTile extends StatelessWidget {
  const _StreamTile({required this.meta, required this.stream});

  final CinemetaMeta meta;
  final TorrentStream stream;

  @override
  Widget build(BuildContext context) {
    final badges = <String>[
      if (stream.quality.isNotEmpty) stream.quality,
      if (stream.seeders != null) '👤 ${stream.seeders}',
      if (stream.formattedSize.isNotEmpty) stream.formattedSize,
    ];
    return ListTile(
      title: Text(stream.releaseName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: badges.isEmpty ? null : Text(badges.join('  •  ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: 'movies.stream'.tr(),
            onPressed: () => _stream(context),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'movies.download'.tr(),
            onPressed: () => _download(context),
          ),
        ],
      ),
    );
  }

  String _displayName() => meta.year != null ? '${meta.name} (${meta.year})' : meta.name;

  Future<void> _download(BuildContext context) async {
    final downloads = context.read<DownloadsCubit>();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(); // close the sheet
    messenger.showSnackBar(SnackBar(content: Text('movies.download_started'.tr(args: [_displayName()]))));
    // Fire-and-forget; progress is tracked by DownloadsCubit / DownloadsScreen.
    unawaited(downloads.startDownload(stream, displayName: _displayName()));
  }

  Future<void> _stream(BuildContext context) async {
    final launcher = context.read<PlayerLauncher>();
    final resolver = context.read<AcquisitionResolver>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final statusNotifier = ValueNotifier<String>('movies.resolving'.tr());
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 16),
            Expanded(child: ValueListenableBuilder<String>(valueListenable: statusNotifier, builder: (_, v, _) => Text(v))),
          ],
        ),
      ),
    );

    try {
      final settings = PlayraStorage.getPlayerSettings();
      final service = resolver.resolve(settings);
      final url = await service.resolveStreamUrl(stream, onStatus: (s) => statusNotifier.value = _statusLabel(s));
      if (!context.mounted) return;
      navigator.pop(); // close progress dialog
      navigator.pop(); // close the sheet

      final video = VideoItem(id: url, name: '${_displayName()}.mp4', uri: url, source: VideoSource.http);
      if (!navigator.mounted) return;
      await launcher.launch(navigator.context, video);
    } on AcquisitionException catch (e) {
      if (context.mounted) navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(_acquisitionErrorText(e))));
    } catch (e) {
      if (context.mounted) navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('movies.stream_error'.tr(args: [e.toString()]))));
    } finally {
      statusNotifier.dispose();
    }
  }

  String _statusLabel(String code) {
    if (code.startsWith('caching')) {
      final parts = code.split(':');
      final pct = parts.length > 1 ? parts[1] : '';
      return pct.isNotEmpty ? 'movies.status_caching_pct'.tr(args: [pct]) : 'movies.status_caching'.tr();
    }
    switch (code) {
      case 'adding':
        return 'movies.status_adding'.tr();
      case 'selecting':
        return 'movies.status_selecting'.tr();
      case 'unrestricting':
        return 'movies.status_unrestricting'.tr();
      default:
        return 'movies.resolving'.tr();
    }
  }

  String _acquisitionErrorText(AcquisitionException e) {
    switch (e.code) {
      case AcquisitionError.missingRealDebridKey:
        return 'movies.error_missing_rd_key'.tr();
      case AcquisitionError.torrentUnavailable:
        return 'movies.error_torrent_unavailable'.tr();
      case AcquisitionError.torrentStreamingDisabled:
        return 'movies.error_torrent_streaming_disabled'.tr();
      default:
        return 'movies.stream_error'.tr(args: [e.message]);
    }
  }
}
