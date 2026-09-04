import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../models/media_info.dart';
import '../../../models/video_info.dart';

class VideoDetailScreen extends StatelessWidget {
  final VideoInfo video;
  final MediaInfo? mediaInfo;
  final bool isSearching;
  final bool isFromCache;
  final VoidCallback onPlay;
  final VoidCallback onSearchSubtitles;
  final VoidCallback? onEditSubtitles;
  final VoidCallback onEditMediaInfo;
  final VoidCallback onSearchAgain;

  const VideoDetailScreen({
    super.key,
    required this.video,
    required this.mediaInfo,
    required this.isSearching,
    required this.isFromCache,
    required this.onPlay,
    required this.onSearchSubtitles,
    this.onEditSubtitles,
    required this.onEditMediaInfo,
    required this.onSearchAgain,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(mediaInfo?.title ?? video.name), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mediaInfo != null) ...[
              // Poster - smaller and centred on phones
              if (mediaInfo!.posterUrl.isNotEmpty)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      mediaInfo!.posterUrl,
                      width: 150,
                      height: 225,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(width: 150, height: 225, color: Colors.grey[300], child: const Icon(Icons.movie, size: 48)),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Title
              SelectableText(
                mediaInfo!.title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if (mediaInfo!.originalTitle != mediaInfo!.title)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Center(
                    child: SelectableText(
                      mediaInfo!.originalTitle,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600], fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Genres
              if (mediaInfo!.genres.isNotEmpty)
                Center(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: mediaInfo!.genres.map((genre) {
                      return Chip(
                        label: Text(genre, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.blue[100],
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 16),
              // Rating and year
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (mediaInfo!.voteAverage != null) ...[
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text('${mediaInfo!.voteAverage!.toStringAsFixed(1)}/10', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                  ],
                  if (mediaInfo!.releaseDate != null) Text(mediaInfo!.releaseDate!.substring(0, 4), style: const TextStyle(fontSize: 16)),
                  if (mediaInfo!.type == MediaType.tv) ...[
                    const SizedBox(width: 8),
                    Text('• ${mediaInfo!.numberOfSeasons ?? '?'} ${'video.seasons'.tr()}', style: const TextStyle(fontSize: 14)),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              // Overview
              if (mediaInfo!.overview != null && mediaInfo!.overview!.isNotEmpty) ...[
                Text('video.overview'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText(mediaInfo!.overview!, style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 24),
              ],
              // Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: Text('video.play'.tr()),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onSearchSubtitles,
                  icon: const Icon(Icons.subtitles),
                  label: Text('subtitle.search_button'.tr()),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              if (onEditSubtitles != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onEditSubtitles,
                    icon: const Icon(Icons.edit),
                    label: Text('player.edit_subtitles'.tr()),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // Cache info
              if (isFromCache)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cached, size: 16, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Text('video.cached_info'.tr(), style: TextStyle(fontSize: 14, color: Colors.green[700])),
                  ],
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(onPressed: onEditMediaInfo, icon: const Icon(Icons.edit), label: Text('video.edit_media_info'.tr())),
              ),
            ] else if (isSearching) ...[
              const Center(
                child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
              ),
            ] else ...[
              // Not found
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    Icon(Icons.movie_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    SelectableText(
                      video.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text('video.no_media_info'.tr(), style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(onPressed: onSearchAgain, icon: const Icon(Icons.refresh), label: Text('video.search_again'.tr())),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(onPressed: onEditMediaInfo, icon: const Icon(Icons.search), label: Text('video.manual_search'.tr())),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
