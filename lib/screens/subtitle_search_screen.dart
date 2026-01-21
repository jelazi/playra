import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/subtitle/subtitle_bloc.dart';
import '../bloc/subtitle/subtitle_event.dart';
import '../bloc/subtitle/subtitle_state.dart';
import '../models/subtitle.dart';
import '../models/video_info.dart';
import 'video_player_screen.dart';

class SubtitleSearchScreen extends StatefulWidget {
  final VideoInfo videoInfo;

  const SubtitleSearchScreen({super.key, required this.videoInfo});

  @override
  State<SubtitleSearchScreen> createState() => _SubtitleSearchScreenState();
}

class _SubtitleSearchScreenState extends State<SubtitleSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isManualSearch = false;

  @override
  void initState() {
    super.initState();
    // Automatically start subtitle search
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubtitleBloc>().add(SearchSubtitles(widget.videoInfo));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('subtitle.search_title'.tr()), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: Column(
        children: [
          _buildVideoInfoCard(),
          _buildSearchField(),
          Expanded(
            child: BlocConsumer<SubtitleBloc, SubtitleState>(
              listener: (context, state) {
                if (state is SubtitleError) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: Colors.red));
                } else if (state is SubtitleDownloaded) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Titulky uloženy: ${state.path}'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)));
                  // After download, open player with subtitles - use push instead of pushReplacement
                  // so user can go back to subtitle selection
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VideoPlayerScreen(videoInfo: widget.videoInfo, subtitlePath: state.path),
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state is SubtitleSearching) {
                  return const Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('subtitle.searching')]),
                  );
                } else if (state is SubtitleSearchResults) {
                  return _buildSubtitleList(state);
                } else if (state is SubtitleDownloading) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text('subtitle.downloading'.tr(args: [state.subtitle.title])),
                      ],
                    ),
                  );
                }
                return Center(child: Text('common.loading'.tr()));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoInfoCard() {
    final isPhone = MediaQuery.of(context).size.width < 600;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isPhone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.video_file, size: 40, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.videoInfo.name,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.videoInfo.path.split('/').last,
                              style: const TextStyle(fontSize: 12, color: Colors.blue),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(onPressed: () => _playVideoWithoutSubtitles(), icon: const Icon(Icons.play_arrow), label: Text('video.play'.tr())),
                  ),
                ],
              )
            : Row(
                children: [
                  const Icon(Icons.video_file, size: 48, color: Colors.blue),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(widget.videoInfo.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SelectableText('File: ${widget.videoInfo.path.split('/').last}', style: const TextStyle(fontSize: 13, color: Colors.blue)),
                        const SizedBox(height: 2),
                        SelectableText(widget.videoInfo.directory, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _playVideoWithoutSubtitles(),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('video.play'.tr()),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchField() {
    return BlocBuilder<SubtitleBloc, SubtitleState>(
      buildWhen: (previous, current) {
        // Update when searchQuery changes
        if (current is SubtitleSearching && previous is! SubtitleSearching) return true;
        if (current is SubtitleSearchResults) return true;
        return false;
      },
      builder: (context, state) {
        // Set input text according to current query
        if (!_isManualSearch) {
          if (state is SubtitleSearching && state.searchQuery != null) {
            _searchController.text = state.searchQuery!;
          } else if (state is SubtitleSearchResults) {
            _searchController.text = state.searchQuery;
          }
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(hintText: 'Vyhledávací dotaz...', border: InputBorder.none, isDense: true),
                    onChanged: (_) => _isManualSearch = true,
                    onSubmitted: (_) => _performManualSearch(),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    // Reset to automatic query
                    _isManualSearch = false;
                    context.read<SubtitleBloc>().add(SearchSubtitles(widget.videoInfo));
                  },
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Obnovit automatický dotaz',
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(onPressed: _performManualSearch, icon: const Icon(Icons.search, size: 18), label: const Text('Hledat')),
              ],
            ),
          ),
        );
      },
    );
  }

  void _performManualSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _isManualSearch = true;
      context.read<SubtitleBloc>().add(SearchSubtitlesManual(widget.videoInfo, query));
    }
  }

  Widget _buildSubtitleList(SubtitleSearchResults state) {
    final displayedSubtitles = state.displayedSubtitles;

    if (displayedSubtitles.isEmpty) {
      return Center(child: Text('subtitle.no_results'.tr()));
    }

    return Column(
      children: [
        // Header s informacemi o relevanci
        if (state.sortedSubtitles != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.filter_list, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    state.showOthers ? 'Zobrazeno všech ${state.subtitles.length} titulků' : 'Zobrazeno ${state.sortedSubtitles!.relevantCount} nejrelevantnějších titulků',
                    style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
                if (state.hasHiddenSubtitles)
                  TextButton.icon(
                    onPressed: () => context.read<SubtitleBloc>().add(ToggleShowOtherSubtitles()),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: Text('Zobrazit dalších ${state.hiddenCount}'),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  ),
                if (state.showOthers && state.sortedSubtitles!.hasOthers)
                  TextButton.icon(
                    onPressed: () => context.read<SubtitleBloc>().add(ToggleShowOtherSubtitles()),
                    icon: const Icon(Icons.visibility_off, size: 18),
                    label: const Text('Skrýt ostatní'),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  ),
              ],
            ),
          ),

        // Subtitle list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: displayedSubtitles.length + (state.hasMore || state.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              // Last item is "Load More" button
              if (index == displayedSubtitles.length) {
                return _buildLoadMoreButton(state);
              }

              final subtitle = displayedSubtitles[index];
              final isSelected = state.selectedSubtitle?.id == subtitle.id;

              // Determine if subtitle is relevant
              final isRelevant = state.sortedSubtitles?.relevant.contains(subtitle) ?? true;

              // Responsive layout
              final isPhone = MediaQuery.of(context).size.width < 600;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: isSelected ? Colors.blue.shade50 : (!isRelevant ? Colors.grey.shade100 : null),
                child: InkWell(
                  onTap: () {
                    context.read<SubtitleBloc>().add(SelectSubtitle(subtitle));
                    if (isPhone) {
                      _showSubtitleBottomSheet(subtitle, isRelevant);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isRelevant ? Colors.blue : Colors.grey,
                                  radius: isPhone ? 16 : 20,
                                  child: Text(
                                    subtitle.language.toUpperCase(),
                                    style: TextStyle(color: Colors.white, fontSize: isPhone ? 10 : 12),
                                  ),
                                ),
                                if (isRelevant && index < 3)
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                      child: const Icon(Icons.check, color: Colors.white, size: 10),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    subtitle.title,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: isPhone ? 14 : 16, color: isRelevant ? null : Colors.grey.shade600),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (isRelevant && index == 0)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                                      child: const Text(
                                        'DOPORUČENO',
                                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (!isPhone)
                              ElevatedButton.icon(
                                onPressed: () => _downloadSubtitle(subtitle),
                                icon: const Icon(Icons.download, size: 18),
                                label: const Text('Stáhnout'),
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), backgroundColor: isRelevant ? null : Colors.grey),
                              ),
                            if (isPhone) Icon(Icons.chevron_right, color: Colors.grey[400]),
                          ],
                        ),
                        if (!isPhone) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            children: [
                              if (subtitle.movieName != null && subtitle.movieName!.isNotEmpty) Text('🎬 ${subtitle.movieName}', style: const TextStyle(fontSize: 12)),
                              if (subtitle.uploader != null) Text('👤 ${subtitle.uploader}', style: const TextStyle(fontSize: 12)),
                              if (subtitle.downloadCount != null) Text('⬇️ ${subtitle.downloadCount}×', style: const TextStyle(fontSize: 12)),
                              Text('📄 ${subtitle.format.toUpperCase()}', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 4),
                          Text(
                            '${subtitle.format.toUpperCase()} • ${subtitle.uploader ?? "?"} • ${subtitle.downloadCount ?? 0}× staženo',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showSubtitleBottomSheet(Subtitle subtitle, bool isRelevant) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (subtitle.movieName != null) Text('🎬 Film: ${subtitle.movieName}'),
              if (subtitle.uploader != null) Text('👤 Nahrál: ${subtitle.uploader}'),
              if (subtitle.downloadCount != null) Text('⬇️ Staženo: ${subtitle.downloadCount}×'),
              Text('📄 Formát: ${subtitle.format.toUpperCase()}'),
              Text('🌍 Jazyk: ${subtitle.language.toUpperCase()}'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _downloadSubtitle(subtitle);
                  },
                  icon: const Icon(Icons.download),
                  label: Text('subtitle.download_button'.tr()),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _playVideoWithoutSubtitles() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => VideoPlayerScreen(videoInfo: widget.videoInfo)));
  }

  void _downloadSubtitle(Subtitle subtitle) {
    context.read<SubtitleBloc>().add(DownloadSubtitle(subtitle, widget.videoInfo));
  }

  Widget _buildLoadMoreButton(SubtitleSearchResults state) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: state.isLoadingMore
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  SelectableText('Načítám další titulky...'),
                ],
              )
            : ElevatedButton.icon(
                onPressed: () => context.read<SubtitleBloc>().add(LoadMoreSubtitles()),
                icon: const Icon(Icons.expand_more),
                label: SelectableText('Načíst další titulky (strana ${state.currentPage + 1})'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              ),
      ),
    );
  }
}
