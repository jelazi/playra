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
                    // Fetch alternative subtitles when selecting a subtitle
                    context.read<SubtitleBloc>().add(FetchAlternativeSubtitles(subtitle));
                    if (isPhone) {
                      _showSubtitleBottomSheet(subtitle, isRelevant, state);
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
                              // Determine which subtitle data to use
                              ..._buildSubtitleDetails(subtitle, isSelected, state),
                            ],
                          ),
                          // Show alternative subtitles section for desktop when selected
                          if (isSelected) _buildDesktopAlternativesSection(state),
                        ] else ...[
                          const SizedBox(height: 4),
                          Text(
                            _buildMobileSubtitleInfo(subtitle, isSelected, state),
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

  Widget _buildDesktopAlternativesSection(SubtitleSearchResults state) {
    final alternatives = state.alternativeSubtitles;
    final isLoading = state.isLoadingAlternatives;

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Načítám alternativní titulky...', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    if (alternatives == null || alternatives.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 12, bottom: 8), child: Divider()),
        Row(
          children: [
            const Icon(Icons.list_alt, size: 18, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              'Alternativní titulky (${alternatives.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...alternatives.take(5).map((alt) => _buildDesktopAlternativeTile(alt)),
        if (alternatives.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('... a ${alternatives.length - 5} dalších', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
      ],
    );
  }

  Widget _buildDesktopAlternativeTile(Subtitle subtitle) {
    return InkWell(
      onTap: () {
        context.read<SubtitleBloc>().add(FetchAlternativeSubtitles(subtitle));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              radius: 12,
              child: Text(subtitle.language.toUpperCase(), style: const TextStyle(fontSize: 8, color: Colors.blue)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle.title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.uploader != null || subtitle.details != null)
                    Text(
                      [if (subtitle.uploader != null) subtitle.uploader, if (subtitle.details != null) subtitle.details].join(' • '),
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.download, size: 18, color: Colors.blue),
              onPressed: () => _downloadSubtitle(subtitle),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  void _showSubtitleBottomSheet(Subtitle subtitle, bool isRelevant, SubtitleSearchResults state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) => BlocBuilder<SubtitleBloc, SubtitleState>(
        builder: (context, currentState) {
          final alternatives = currentState is SubtitleSearchResults ? currentState.alternativeSubtitles : null;
          final isLoadingAlternatives = currentState is SubtitleSearchResults ? currentState.isLoadingAlternatives : false;

          // Use enhanced original if available and this is the selected subtitle
          final isSelected = currentState is SubtitleSearchResults && currentState.selectedSubtitle?.id == subtitle.id;
          final displaySubtitle = (isSelected && currentState.enhancedOriginal != null) ? currentState.enhancedOriginal! : subtitle;

          return SafeArea(
            child: DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) => SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      Text(displaySubtitle.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (displaySubtitle.movieName != null) Text('🎬 Film: ${displaySubtitle.movieName}'),
                      if (displaySubtitle.uploader != null) Text('👤 Nahrál: ${displaySubtitle.uploader}'),
                      if (displaySubtitle.details != null) Text('📋 Detaily: ${displaySubtitle.details}'),
                      if (displaySubtitle.downloadCount != null) Text('⬇️ Staženo: ${displaySubtitle.downloadCount}×'),
                      Text('📄 Formát: ${displaySubtitle.format.toUpperCase()}'),
                      Text('🌍 Jazyk: ${displaySubtitle.language.toUpperCase()}'),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _downloadSubtitle(subtitle); // Use original subtitle for download
                          },
                          icon: const Icon(Icons.download),
                          label: Text('subtitle.download_button'.tr()),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        ),
                      ),
                      // Alternative subtitles section
                      const SizedBox(height: 24),
                      if (isLoadingAlternatives) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Načítám alternativní titulky...', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ] else if (alternatives != null && alternatives.isNotEmpty) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.list_alt, size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'Alternativní titulky (${alternatives.length})',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...alternatives.map((alt) => _buildAlternativeSubtitleTile(alt, bottomSheetContext)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlternativeSubtitleTile(Subtitle subtitle, BuildContext bottomSheetContext) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          radius: 16,
          child: Text(subtitle.language.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.blue)),
        ),
        title: Text(subtitle.title, style: const TextStyle(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle.uploader != null || subtitle.details != null
            ? Text(
                [if (subtitle.uploader != null) subtitle.uploader, if (subtitle.details != null) subtitle.details].join(' • '),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.download, color: Colors.blue),
          onPressed: () {
            Navigator.pop(bottomSheetContext);
            _downloadSubtitle(subtitle);
          },
        ),
        onTap: () {
          // Switch to this alternative and fetch its alternatives
          Navigator.pop(bottomSheetContext);
          context.read<SubtitleBloc>().add(FetchAlternativeSubtitles(subtitle));
          // Show the bottom sheet for this new subtitle
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              final currentState = context.read<SubtitleBloc>().state;
              if (currentState is SubtitleSearchResults) {
                _showSubtitleBottomSheet(subtitle, false, currentState);
              }
            }
          });
        },
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

  // Helper function to determine which subtitle data to display
  Subtitle _getDisplaySubtitle(Subtitle subtitle, bool isSelected, SubtitleSearchResults state) {
    if (isSelected && state.selectedSubtitle?.id == subtitle.id && state.enhancedOriginal != null) {
      return state.enhancedOriginal!;
    }
    return subtitle;
  }

  // Helper function to build subtitle detail widgets for desktop
  List<Widget> _buildSubtitleDetails(Subtitle subtitle, bool isSelected, SubtitleSearchResults state) {
    final displaySubtitle = _getDisplaySubtitle(subtitle, isSelected, state);

    final details = <Widget>[];

    if (displaySubtitle.movieName != null && displaySubtitle.movieName!.isNotEmpty) {
      details.add(Text('🎬 ${displaySubtitle.movieName}', style: const TextStyle(fontSize: 12)));
    }

    if (displaySubtitle.uploader != null && displaySubtitle.uploader!.isNotEmpty) {
      details.add(Text('👤 ${displaySubtitle.uploader}', style: const TextStyle(fontSize: 12)));
    }

    if (displaySubtitle.details != null && displaySubtitle.details!.isNotEmpty) {
      details.add(Text('📋 ${displaySubtitle.details}', style: const TextStyle(fontSize: 12)));
    }

    if (displaySubtitle.downloadCount != null && displaySubtitle.downloadCount!.isNotEmpty) {
      details.add(Text('⬇️ ${displaySubtitle.downloadCount}×', style: const TextStyle(fontSize: 12)));
    }

    details.add(Text('📄 ${displaySubtitle.format.toUpperCase()}', style: const TextStyle(fontSize: 12)));

    return details;
  }

  // Helper function to build subtitle info string for mobile
  String _buildMobileSubtitleInfo(Subtitle subtitle, bool isSelected, SubtitleSearchResults state) {
    final displaySubtitle = _getDisplaySubtitle(subtitle, isSelected, state);

    final format = displaySubtitle.format.toUpperCase();
    final uploader = displaySubtitle.uploader?.isNotEmpty == true ? displaySubtitle.uploader! : "?";
    final downloadCount = displaySubtitle.downloadCount?.isNotEmpty == true ? displaySubtitle.downloadCount! : "0";

    return '$format • $uploader • ${downloadCount}× staženo';
  }
}
