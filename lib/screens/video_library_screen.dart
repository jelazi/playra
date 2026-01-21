import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;

import '../bloc/subtitle/subtitle_bloc.dart';
import '../bloc/subtitle/subtitle_event.dart';
import '../bloc/subtitle/subtitle_state.dart';
import '../models/media_info.dart';
import '../models/video_info.dart';
import '../services/media_cache_service.dart';
import '../services/settings_service.dart';
import '../services/subtitle_file_service.dart';
import '../services/tmdb_service.dart';
import '../services/video_name_parser.dart';
import 'subtitle_search_screen.dart';
import 'video_player_screen.dart';
import 'video_selection_screen.dart';

class VideoLibraryScreen extends StatefulWidget {
  const VideoLibraryScreen({super.key});

  @override
  State<VideoLibraryScreen> createState() => _VideoLibraryScreenState();
}

class _VideoLibraryScreenState extends State<VideoLibraryScreen> {
  final List<VideoInfo> _videos = [];
  VideoInfo? _selectedVideo;
  MediaInfo? _selectedMediaInfo;
  bool _isSearching = false;
  bool _isDragging = false;
  bool _isFromCache = false; // Příznak, že info je z cache

  final TmdbService _tmdbService = TmdbService();

  // Breakpoint pro responzivní layout
  static const double _tabletBreakpoint = 600;

  bool _isTabletOrDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= _tabletBreakpoint;
  }

  @override
  void initState() {
    super.initState();

    // Zkontrolovat, zda je uživatel přihlášen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLoginStatus();
    });
  }

  /// Refresh subtitle status for all videos (both from Hive and file system)
  void _refreshSubtitleStates() {
    setState(() {
      for (int i = 0; i < _videos.length; i++) {
        _videos[i] = SubtitleFileService.updateVideoInfoWithSubtitles(_videos[i]);
      }
    });
  }

  void _checkLoginStatus() {
    final settings = SettingsService.getSettings();
    final subtitleBloc = context.read<SubtitleBloc>();

    // Pokud už jsme přihlášeni, nic nedělat
    if (subtitleBloc.state is SubtitleLoggedIn) {
      return;
    }

    // Zkusit auto-login pokud máme uložené údaje
    if (settings.username != null && settings.username!.isNotEmpty && settings.password != null && settings.password!.isNotEmpty) {
      print('🔵 VideoLibraryScreen: Attempting auto-login');
      subtitleBloc.add(AutoLoginToTitulky());
    } else {
      // Zobrazit přihlášení
      _showLoginDialog();
    }
  }

  void _showLoginDialog() {
    showDialog(context: context, barrierDismissible: false, builder: (context) => const VideoSelectionScreen(isDialog: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('video.library_title'.tr()),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Přepínač jazyků UI
          PopupMenuButton<String>(
            onSelected: (String languageCode) async {
              await context.setLocale(Locale(languageCode));
              await SettingsService.updateLanguage(languageCode);
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'cs', child: Text('🇨🇿 Čeština')),
              const PopupMenuItem<String>(value: 'en', child: Text('🇬🇧 English')),
            ],
            icon: const Icon(Icons.language),
          ),
          // Logout
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'auth.logout_button'.tr(),
            onPressed: () {
              context.read<SubtitleBloc>().add(LogoutFromTitulky());
              _showLoginDialog();
            },
          ),
        ],
      ),
      body: _isTabletOrDesktop(context)
          ? Row(
              children: [
                // Levá strana - Info o vybraném videu
                Expanded(flex: 3, child: _buildVideoInfo()),
                const VerticalDivider(width: 1),
                // Pravá strana - Seznam videí
                Expanded(flex: 2, child: _buildVideoList()),
              ],
            )
          : _buildVideoList(), // Na telefonu pouze seznam
    );
  }

  // Obrazovka detailu pro telefon
  void _showVideoDetailScreen(VideoInfo video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _VideoDetailScreen(
          video: video,
          mediaInfo: _selectedMediaInfo,
          isSearching: _isSearching,
          isFromCache: _isFromCache,
          onPlay: () => _playVideo(video),
          onSearchSubtitles: _searchSubtitles,
          onEditMediaInfo: () => _editMediaInfo(video),
          onSearchAgain: () => _searchMediaInfo(video),
        ),
      ),
    );
  }

  Widget _buildVideoInfo() {
    if (_selectedVideo == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('video.select_video_from_list'.tr(), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster a základní info
          if (_selectedMediaInfo != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster
                if (_selectedMediaInfo!.posterUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      _selectedMediaInfo!.posterUrl,
                      width: 200,
                      height: 300,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(width: 200, height: 300, color: Colors.grey[300], child: const Icon(Icons.movie, size: 64)),
                    ),
                  ),
                const SizedBox(width: 24),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(_selectedMediaInfo!.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      if (_selectedMediaInfo!.originalTitle != _selectedMediaInfo!.title)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SelectableText(
                            _selectedMediaInfo!.originalTitle,
                            style: TextStyle(fontSize: 16, color: Colors.grey[600], fontStyle: FontStyle.italic),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Žánry
                      if (_selectedMediaInfo!.genres.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          children: _selectedMediaInfo!.genres.map((genre) {
                            return Chip(label: Text(genre), backgroundColor: Colors.blue[100]);
                          }).toList(),
                        ),
                      const SizedBox(height: 16),
                      // Hodnocení
                      if (_selectedMediaInfo!.voteAverage != null)
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 24),
                            const SizedBox(width: 8),
                            SelectableText(_selectedMediaInfo!.voteAverage!.toStringAsFixed(1), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            SelectableText(' / 10', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                          ],
                        ),
                      const SizedBox(height: 16),
                      // Rok vydání / Sezóny
                      if (_selectedMediaInfo!.type == MediaType.movie && _selectedMediaInfo!.releaseDate != null)
                        SelectableText('video.release_date'.tr() + ': ${_selectedMediaInfo!.releaseDate}', style: const TextStyle(fontSize: 16)),
                      if (_selectedMediaInfo!.type == MediaType.tv) ...[
                        if (_selectedMediaInfo!.numberOfSeasons != null)
                          SelectableText('video.seasons'.tr() + ': ${_selectedMediaInfo!.numberOfSeasons}', style: const TextStyle(fontSize: 16)),
                        if (_selectedMediaInfo!.numberOfEpisodes != null)
                          SelectableText('video.episodes'.tr() + ': ${_selectedMediaInfo!.numberOfEpisodes}', style: const TextStyle(fontSize: 16)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Popis
            if (_selectedMediaInfo!.overview != null && _selectedMediaInfo!.overview!.isNotEmpty) ...[
              SelectableText('video.overview'.tr(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(_selectedMediaInfo!.overview!, style: const TextStyle(fontSize: 16, height: 1.5)),
              const SizedBox(height: 24),
            ],
            // Tlačítka pro přehrávání a vyhledání titulků
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _playVideo(_selectedVideo!),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('video.play'.tr()),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _searchSubtitles(),
                    icon: const Icon(Icons.subtitles),
                    label: Text('subtitle.search_button'.tr()),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Info o cache a tlačítko pro editaci
            if (_isFromCache) ...[
              Row(
                children: [
                  Icon(Icons.cached, size: 16, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Text('video.cached_info'.tr(), style: TextStyle(fontSize: 14, color: Colors.green[700])),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // Tlačítko pro změnu přiřazení
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(onPressed: () => _editMediaInfo(_selectedVideo!), icon: const Icon(Icons.edit), label: Text('video.edit_media_info'.tr())),
            ),
          ] else if (_isSearching) ...[
            const Center(child: CircularProgressIndicator()),
          ] else ...[
            SelectableText(_selectedVideo!.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('video.no_media_info'.tr()),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(onPressed: () => _searchMediaInfo(_selectedVideo!), icon: const Icon(Icons.refresh), label: Text('video.search_again'.tr())),
                const SizedBox(width: 12),
                ElevatedButton.icon(onPressed: () => _editMediaInfo(_selectedVideo!), icon: const Icon(Icons.search), label: Text('video.manual_search'.tr())),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoList() {
    final isPhone = !_isTabletOrDesktop(context);

    return Stack(
      children: [
        Column(
          children: [
            // Drop zone
            Expanded(
              child: DropTarget(
                onDragDone: (details) {
                  _addVideosFromPaths(details.files.map((f) => f.path).toList());
                },
                onDragEntered: (details) {
                  setState(() => _isDragging = true);
                },
                onDragExited: (details) {
                  setState(() => _isDragging = false);
                },
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: _isDragging ? Colors.blue : Colors.transparent, width: 2)),
                  child: _videos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.video_library_outlined, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                isPhone ? 'video.tap_to_add'.tr() : 'video.drag_drop_hint'.tr(),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600], fontSize: 16),
                              ),
                              if (isPhone) ...[
                                const SizedBox(height: 16),
                                ElevatedButton.icon(onPressed: _pickVideos, icon: const Icon(Icons.add), label: Text('video.add_videos'.tr())),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _videos.length,
                          itemBuilder: (context, index) {
                            final video = _videos[index];
                            final isSelected = _selectedVideo == video;
                            
                            return ListTile(
                              selected: isSelected,
                              leading: Stack(
                                children: [
                                  Icon(
                                    Icons.movie,
                                    color: video.hasAnySubtitles ? Colors.green : null,
                                  ),
                                  // Subtitle indicator
                                  if (video.hasAnySubtitles)
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: video.hasPhysicalSubtitles ? Colors.green : Colors.orange,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.subtitles,
                                          color: Colors.white,
                                          size: 10,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(video.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(path.dirname(video.path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                  if (video.hasAnySubtitles)
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.subtitles,
                                          size: 12,
                                          color: video.hasPhysicalSubtitles ? Colors.green : Colors.orange,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            video.hasPhysicalSubtitles 
                                                ? 'Soubory titulků (${video.subtitleFiles.length})'
                                                : 'Stažené přes aplikaci',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: video.hasPhysicalSubtitles ? Colors.green[700] : Colors.orange[700],
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              trailing: isPhone
                                  ? IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _selectVideo(video))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(icon: const Icon(Icons.play_circle_outline, size: 24), tooltip: 'video.play'.tr(), onPressed: () => _playVideo(video)),
                                        IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => _removeVideo(video)),
                                      ],
                                    ),
                              onTap: () => _selectVideo(video),
                              onLongPress: isPhone ? () => _showVideoOptionsMenu(video) : null,
                            );
                          },
                        ),
                ),
              ),
            ),
            // Tlačítka - pouze na tabletu/desktopu
            if (!isPhone) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(onPressed: _pickVideos, icon: const Icon(Icons.add), label: Text('video.add_videos'.tr())),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(onPressed: _videos.isNotEmpty ? _refreshSubtitleStates : null, icon: const Icon(Icons.refresh), label: const Text('Aktualizovat titulky')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(onPressed: _videos.isNotEmpty ? _clearAll : null, icon: const Icon(Icons.clear_all), label: Text('video.clear_all'.tr())),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        // FAB pro telefon
        if (isPhone && _videos.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(onPressed: _pickVideos, child: const Icon(Icons.add)),
          ),
      ],
    );
  }

  // Menu pro dlouhé stisknutí na telefonu
  void _showVideoOptionsMenu(VideoInfo video) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text('video.play'.tr()),
              onTap: () {
                Navigator.pop(context);
                _playVideo(video);
              },
            ),
            ListTile(
              leading: const Icon(Icons.subtitles),
              title: Text('subtitle.search_button'.tr()),
              onTap: () {
                Navigator.pop(context);
                _selectVideo(video);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text('video.remove'.tr()),
              onTap: () {
                Navigator.pop(context);
                _removeVideo(video);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickVideos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg', '3gp'],
      allowMultiple: true,
      dialogTitle: 'video.select_videos'.tr(),
    );

    if (result != null && result.files.isNotEmpty) {
      final paths = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
      _addVideosFromPaths(paths);
    }
  }

  void _addVideosFromPaths(List<String> paths) {
    for (final filePath in paths) {
      // Kontrola, zda už video není v seznamu
      if (_videos.any((v) => v.path == filePath)) continue;

      final fileName = path.basename(filePath);
      final fileDir = path.dirname(filePath);

      // Create VideoInfo and check for subtitles
      var videoInfo = VideoInfo(path: filePath, name: fileName, directory: fileDir);
      videoInfo = SubtitleFileService.updateVideoInfoWithSubtitles(videoInfo);

      setState(() {
        _videos.add(videoInfo);
      });

      // Automaticky vyhledat info o prvním přidaném videu
      if (_videos.length == 1) {
        _selectVideo(videoInfo);
      }
    }
  }

  void _removeVideo(VideoInfo video) {
    setState(() {
      _videos.remove(video);
      if (_selectedVideo == video) {
        _selectedVideo = null;
        _selectedMediaInfo = null;
        if (_videos.isNotEmpty) {
          _selectVideo(_videos.first);
        }
      }
    });
  }

  void _playVideo(VideoInfo video) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => VideoPlayerScreen(videoInfo: video)));
  }

  void _clearAll() {
    setState(() {
      _videos.clear();
      _selectedVideo = null;
      _selectedMediaInfo = null;
    });
  }

  void _selectVideo(VideoInfo video) {
    setState(() {
      _selectedVideo = video;
      _selectedMediaInfo = null;
    });
    _searchMediaInfo(video).then((_) {
      // Na telefonu otevřít detail screen po načtení
      if (!_isTabletOrDesktop(context) && mounted) {
        _showVideoDetailScreen(video);
      }
    });
  }

  Future<void> _searchMediaInfo(VideoInfo video) async {
    setState(() => _isSearching = true);

    try {
      // Parsovat název souboru
      final parsed = VideoNameParser.parse(video.path);
      print('Parsed name: ${parsed.cleanName}');
      print('Is TV: ${parsed.isTV}, Season: ${parsed.season}, Episode: ${parsed.episode}');

      // Zkontrolovat cache
      final cached = MediaCacheService.getMapping(parsed.cleanName);
      if (cached != null) {
        print('✅ Found in cache: ${cached.title}');

        // Načíst detaily z cache
        final language = context.locale.languageCode;
        MediaInfo? details;

        if (cached.mediaType == 'movie') {
          details = await _tmdbService.getMovieDetails(cached.tmdbId, language);
        } else {
          details = await _tmdbService.getTVDetails(cached.tmdbId, language);
        }

        if (mounted) {
          setState(() {
            _selectedMediaInfo = details ?? MediaCacheService.cacheToMediaInfo(cached);
            _isFromCache = true;
            _isSearching = false;
          });
        }
        return;
      }

      // Vyhledat v TMDB
      final language = context.locale.languageCode;
      final results = await _tmdbService.search(query: parsed.cleanName, language: language, searchMovies: !parsed.isTV, searchTV: parsed.isTV, year: parsed.year);

      if (results.isNotEmpty) {
        // Zobrazit dialog s výběrem
        if (mounted) {
          setState(() => _isSearching = false);

          final selectedMedia = await _showMediaSelectionDialog(results, parsed.cleanName);

          if (selectedMedia != null) {
            setState(() => _isSearching = true);

            // Získat detaily
            MediaInfo? details;
            if (selectedMedia.type == MediaType.movie) {
              details = await _tmdbService.getMovieDetails(selectedMedia.id, language);
            } else {
              details = await _tmdbService.getTVDetails(selectedMedia.id, language);
            }

            final finalInfo = details ?? selectedMedia;

            // Uložit do cache
            await MediaCacheService.saveMapping(parsed.cleanName, finalInfo);
            print('💾 Saved to cache: ${parsed.cleanName} → ${finalInfo.title}');

            if (mounted) {
              setState(() {
                _selectedMediaInfo = finalInfo;
                _isFromCache = false;
                _isSearching = false;
              });
            }
          } else {
            setState(() => _isSearching = false);
          }
        }
      } else {
        if (mounted) {
          setState(() => _isSearching = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('video.media_not_found'.tr())));
        }
      }
    } catch (e) {
      print('Error searching media info: $e');
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('video.search_error'.tr())));
      }
    }
  }

  // Funkce pro editaci přiřazení
  Future<void> _editMediaInfo(VideoInfo video) async {
    final parsed = VideoNameParser.parse(video.path);

    // Zobrazit dialog pro ruční vyhledávání
    final selectedMedia = await _showManualSearchDialog(parsed.cleanName);

    if (selectedMedia != null && mounted) {
      // Uložit do cache
      await MediaCacheService.saveMapping(parsed.cleanName, selectedMedia);

      setState(() {
        _selectedMediaInfo = selectedMedia;
        _isFromCache = false;
      });
    }
  }

  Future<MediaInfo?> _showMediaSelectionDialog(List<MediaInfo> results, String cleanName) async {
    final selected = await showDialog<MediaInfo>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('video.select_media'.tr()),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length > 10 ? 10 : results.length,
            itemBuilder: (context, index) {
              final media = results[index];
              return ListTile(
                leading: media.posterPath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          media.posterUrl,
                          width: 40,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 40, height: 60, color: Colors.grey[300], child: const Icon(Icons.movie, size: 24)),
                        ),
                      )
                    : Container(width: 40, height: 60, color: Colors.grey[300], child: const Icon(Icons.movie, size: 24)),
                title: Text(media.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (media.originalTitle != media.title) Text(media.originalTitle, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    Text(
                      '${media.releaseDate?.substring(0, 4) ?? '?'} • ${media.type == MediaType.movie ? 'Film' : 'Seriál'} • ⭐ ${media.voteAverage?.toStringAsFixed(1) ?? '?'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                onTap: () => Navigator.pop(context, media),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('common.cancel'.tr())),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(context); // Zavřít první dialog
              await _showManualSearchDialog(cleanName);
            },
            icon: const Icon(Icons.search),
            label: Text('video.manual_search'.tr()),
          ),
        ],
      ),
    );

    // Pokud selected je null (Cancel nebo Ruční vyhledávání), zkusit ruční vyhledávání
    if (selected == null && mounted) {
      return await _showManualSearchDialog(cleanName);
    }

    return selected;
  }

  // Dialog pro ruční vyhledávání
  Future<MediaInfo?> _showManualSearchDialog(String initialQuery) async {
    final controller = TextEditingController(text: initialQuery);
    List<MediaInfo> searchResults = [];
    bool isSearching = false;

    return showDialog<MediaInfo>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('video.manual_search'.tr()),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
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

                        setDialogState(() {
                          isSearching = true;
                          searchResults = [];
                        });

                        final language = context.locale.languageCode;
                        final results = await _tmdbService.search(query: controller.text.trim(), language: language, searchMovies: true, searchTV: true);

                        setDialogState(() {
                          searchResults = results;
                          isSearching = false;
                        });
                      },
                    ),
                  ),
                  onSubmitted: (value) async {
                    if (value.trim().isEmpty) return;

                    setDialogState(() {
                      isSearching = true;
                      searchResults = [];
                    });

                    final language = context.locale.languageCode;
                    final results = await _tmdbService.search(query: value.trim(), language: language, searchMovies: true, searchTV: true);

                    setDialogState(() {
                      searchResults = results;
                      isSearching = false;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isSearching
                      ? const Center(child: CircularProgressIndicator())
                      : searchResults.isEmpty
                      ? Center(
                          child: Text('video.manual_search_hint'.tr(), style: TextStyle(color: Colors.grey[600])),
                        )
                      : ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final media = searchResults[index];
                            return ListTile(
                              leading: media.posterPath != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        media.posterUrl,
                                        width: 40,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(width: 40, height: 60, color: Colors.grey[300], child: const Icon(Icons.movie, size: 24)),
                                      ),
                                    )
                                  : Container(width: 40, height: 60, color: Colors.grey[300], child: const Icon(Icons.movie, size: 24)),
                              title: Text(media.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (media.originalTitle != media.title) Text(media.originalTitle, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                  Text(
                                    '${media.releaseDate?.substring(0, 4) ?? '?'} • ${media.type == MediaType.movie ? 'Film' : 'Seriál'} • ⭐ ${media.voteAverage?.toStringAsFixed(1) ?? '?'}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              onTap: () => Navigator.pop(context, media),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('common.cancel'.tr()))],
        ),
      ),
    );
  }

  void _searchSubtitles() {
    if (_selectedVideo == null || _selectedMediaInfo == null) return;

    // Vytvořit upravené VideoInfo s názvem z TMDB
    final videoInfo = VideoInfo(path: _selectedVideo!.path, name: _selectedMediaInfo!.title, directory: _selectedVideo!.directory);

    Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => SubtitleSearchScreen(videoInfo: videoInfo))
    ).then((_) {
      // Refresh subtitle states after returning from subtitle search
      _refreshSubtitleStates();
    });
  }
}

// Obrazovka detailu videa pro telefon
class _VideoDetailScreen extends StatelessWidget {
  final VideoInfo video;
  final MediaInfo? mediaInfo;
  final bool isSearching;
  final bool isFromCache;
  final VoidCallback onPlay;
  final VoidCallback onSearchSubtitles;
  final VoidCallback onEditMediaInfo;
  final VoidCallback onSearchAgain;

  const _VideoDetailScreen({
    required this.video,
    required this.mediaInfo,
    required this.isSearching,
    required this.isFromCache,
    required this.onPlay,
    required this.onSearchSubtitles,
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
              // Poster - na telefonu menší a centrovaný
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
              // Název
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
              // Žánry
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
              // Hodnocení a rok
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
              // Popis
              if (mediaInfo!.overview != null && mediaInfo!.overview!.isNotEmpty) ...[
                Text('video.overview'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText(mediaInfo!.overview!, style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 24),
              ],
              // Tlačítka
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
              const SizedBox(height: 8),
              // Info o cache
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
              // Nenalezeno
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
