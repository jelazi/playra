import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:window_manager/window_manager.dart';

import '../bloc/settings/playra_settings_cubit.dart';
import '../models/player_settings.dart';
import '../models/server_connection.dart';
import '../models/subtitle_style_settings.dart';
import '../models/video_info.dart';
import '../models/video_item.dart';
import '../services/episode_continuation_service.dart';
import '../services/playra_storage.dart';
import '../services/smb_download_service.dart';
import '../services/video_hash_service.dart';
import 'player_launcher.dart';
import 'subtitle_search_screen.dart';

String _normalizeTrackPart(String? value) => (value ?? '').trim().toLowerCase();

String _stableAudioTrackKey(AudioTrack track) => '${_normalizeTrackPart(track.title)}|${_normalizeTrackPart(track.language)}';

String _stableSubtitleTrackKey(SubtitleTrack track) => '${_normalizeTrackPart(track.title)}|${_normalizeTrackPart(track.language)}';

({String title, String language, String id}) _parseStoredTrackKey(String storedKey) {
  final parts = storedKey.split('|');
  return (
    title: parts.isNotEmpty ? parts[0].trim().toLowerCase() : '',
    language: parts.length > 1 ? parts[1].trim().toLowerCase() : '',
    id: parts.length > 2 ? parts.sublist(2).join('|').trim() : '',
  );
}

class PlayraPlayerScreen extends StatefulWidget {
  final VideoItem video;

  const PlayraPlayerScreen({super.key, required this.video});

  @override
  State<PlayraPlayerScreen> createState() => _PlayraPlayerScreenState();
}

class _PlayraPlayerScreenState extends State<PlayraPlayerScreen> with WidgetsBindingObserver {
  static const List<String> _videoFitModes = ['scaleDown', 'contain'];

  late final Player _player;
  late final VideoController _videoController;

  final FocusNode _keyboardFocusNode = FocusNode();

  bool _showControls = true;
  bool _showOverlay = false;
  IconData? _overlayIcon;
  String? _overlayText;
  bool _playing = false;
  bool _isReady = false;
  bool _hasFatalPlaybackError = false;
  String? _fatalPlaybackMessage;
  String _videoFitMode = 'scaleDown';
  double _videoZoom = 1.0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Timer? _hideTimer;
  Timer? _overlayTimer;
  Timer? _resumePersistTimer;
  Timer? _syncSessionTimer;
  int _lastPersistedResumeMs = -1;
  int _lastPersistedDurationMs = -1;
  String? _videoHash;
  Duration? _pendingInitialResume;
  bool _initialResumeApplied = false;
  bool _initialResumeResolved = false;
  String? _pendingAudioTrackPref;
  String? _pendingSubtitleTrackPref;
  bool _preferredTracksApplied = false;
  int _preferredTrackRestoreAttempts = 0;

  bool _isDownloading = false;
  DownloadCancellationToken? _downloadToken;
  int? _dragSeekPositionMs;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<String>? _errorSub;
  Timer? _subtitleDelayPopupTimer;

  VideoItem? _nextEpisode;

  bool get _isDesktopPlatform {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  bool get _isTouchPlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();

    _player = Player(configuration: const PlayerConfiguration(title: 'Playra'));
    _videoController = VideoController(_player);

    _bindPlayerStreams();
    _openMedia();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _persistResumeNow();
    } else if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  Future<void> _onAppResumed() async {
    if (widget.video.source == VideoSource.smb) {
      try {
        await context.read<PlayerLauncher>().ensureSmbConnected(widget.video);
      } catch (_) {}
    }

    if (_hasFatalPlaybackError && mounted) {
      _openMedia();
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _hideTimer?.cancel();
    _overlayTimer?.cancel();
    _resumePersistTimer?.cancel();
    _syncSessionTimer?.cancel();
    _downloadToken?.cancel();
    _subtitleDelayPopupTimer?.cancel();
    unawaited(_persistResumeNow().catchError((error, stackTrace) {}));
    unawaited(_pushSessionUpdate(force: true).catchError((error, stackTrace) {}));
    WidgetsBinding.instance.removeObserver(this);
    _keyboardFocusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  void _bindPlayerStreams() {
    _playingSub = _player.stream.playing.listen((p) {
      if (!mounted) return;
      setState(() => _playing = p);
      unawaited(_pushSessionUpdate());
    });

    _positionSub = _player.stream.position.listen((pos) async {
      if (!mounted) return;
      setState(() => _position = pos);
      if (_duration.inMilliseconds > 0 && _initialResumeResolved) {
        _scheduleResumePersist();
      }
      _scheduleSessionSync();
    });

    _durationSub = _player.stream.duration.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
      final durationMs = dur.inMilliseconds;
      if (durationMs > 0 && durationMs != _lastPersistedDurationMs) {
        _lastPersistedDurationMs = durationMs;
        unawaited(PlayraStorage.setVideoDuration(widget.video.id, durationMs));
        unawaited(_applyInitialResumeIfNeeded());
        unawaited(_restorePreferredTracks());
      }
      _scheduleSessionSync();
    });

    _errorSub = _player.stream.error.listen((e) {
      _handlePlayerError(e, markFatal: _isCodecError(e));
    });
  }

  bool _isCodecError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('codec') ||
        normalized.contains('decoder') ||
        normalized.contains('decode') ||
        normalized.contains('ffmpeg') ||
        normalized.contains('hwdec') ||
        normalized.contains('mediacodec');
  }

  Future<bool> _runPlayerAction(Future<void> Function() action, {required String operation, bool markFatal = false}) async {
    try {
      await action();
      return true;
    } catch (e, st) {
      debugPrint('Playra player action failed [$operation]: $e\n$st');
      _handlePlayerError(e.toString(), markFatal: markFatal || _isCodecError(e.toString()));
      return false;
    }
  }

  void _handlePlayerError(String rawError, {bool markFatal = false}) {
    if (!mounted) return;

    final codecError = _isCodecError(rawError);
    final message = codecError ? 'Codec error during playback. Try another file or encoding.' : 'Playback error: $rawError';

    if (markFatal || codecError) {
      setState(() {
        _hasFatalPlaybackError = true;
        _fatalPlaybackMessage = message;
        _isReady = true;
      });
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openMedia() async {
    try {
      final settings = PlayraStorage.getPlayerSettings();

      setState(() {
        _hasFatalPlaybackError = false;
        _fatalPlaybackMessage = null;
        _isReady = false;
      });

      final opened = await _runPlayerAction(() => _player.open(Media(widget.video.uri)), operation: 'open media', markFatal: true);
      if (!opened || !mounted) return;

      final resume = PlayraStorage.getResume(widget.video.id);
      if (settings.resumePlayback && resume != null && resume > 0) {
        _pendingInitialResume = Duration(milliseconds: resume);
        await _applyInitialResumeIfNeeded();
      } else {
        _initialResumeResolved = true;
      }

      _pendingAudioTrackPref = PlayraStorage.getPreferredAudioTrackKey(widget.video.id);
      _pendingSubtitleTrackPref = PlayraStorage.getPreferredSubtitleTrackKey(widget.video.id);

      await _applyStoredSubtitleDelay();

      await _attachAutoSubtitleIfAvailable();

      await _restorePreferredTracks();

      _videoHash = await VideoHashService.hashForVideo(widget.video);
      if (_videoHash != null) {
        await PlayraStorage.bindVideoToHash(videoId: widget.video.id, hash: _videoHash!, title: widget.video.displayName, sizeBytes: widget.video.sizeBytes);
        await PlayraStorage.addRecent(widget.video);
      }

      final next = await EpisodeContinuationService.findNextEpisode(widget.video);
      if (mounted) {
        setState(() {
          _nextEpisode = next;
          _isReady = true;
        });
      }

      _startHideTimer();
      _scheduleSessionSync();
      _schedulePreferredTrackRestore();
    } catch (e, st) {
      debugPrint('Playra player open media flow failed: $e\n$st');
      _handlePlayerError(e.toString(), markFatal: true);
    }
  }

  Future<void> _applyStoredSubtitleDelay() async {
    final delayMs = PlayraStorage.getSubtitleDelayMs(widget.video.id);
    final seconds = (delayMs / 1000.0).toStringAsFixed(3);
    final dynamic platform = _player.platform;
    try {
      await platform.setProperty('sub-delay', seconds);
    } catch (_) {}
  }

  Future<void> _applyInitialResumeIfNeeded() async {
    if (_initialResumeApplied) {
      _initialResumeResolved = true;
      return;
    }

    final target = _pendingInitialResume;
    if (target == null || target <= Duration.zero) {
      _initialResumeResolved = true;
      return;
    }

    final durationMs = _duration.inMilliseconds;
    if (durationMs <= 0) return;

    final maxTargetMs = durationMs > 2000 ? durationMs - 2000 : durationMs;
    final targetMs = target.inMilliseconds.clamp(0, maxTargetMs);
    if (targetMs <= 0) {
      _pendingInitialResume = null;
      _initialResumeApplied = true;
      _initialResumeResolved = true;
      return;
    }

    final clampedTarget = Duration(milliseconds: targetMs);
    for (var attempt = 0; attempt < 4; attempt++) {
      final moved = await _runPlayerAction(() => _player.seek(clampedTarget), operation: 'initial resume seek');
      if (!moved) break;
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final currentMs = _player.state.position.inMilliseconds;
      if ((currentMs - targetMs).abs() <= 1500) {
        break;
      }
    }

    _pendingInitialResume = null;
    _initialResumeApplied = true;
    _initialResumeResolved = true;
    _scheduleResumePersist();
    _scheduleSessionSync();
  }

  void _scheduleSessionSync() {
    if (_syncSessionTimer?.isActive ?? false) return;
    _syncSessionTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_pushSessionUpdate());
    });
  }

  Future<void> _pushSessionUpdate({bool force = false}) async {
    final hash = _videoHash;
    if (hash == null || hash.isEmpty) return;

    final positionMs = _position.inMilliseconds;
    if (!force && positionMs <= 0) return;

    final audioTrack = PlayraStorage.getPreferredAudioTrackKey(widget.video.id);
    final subtitleTrack = PlayraStorage.getPreferredSubtitleTrackKey(widget.video.id);

    await PlayraStorage.saveNowPlayingSession(<String, dynamic>{
      'videoId': widget.video.id,
      'title': widget.video.displayName,
      'videoHash': hash,
      'positionMs': positionMs,
      'durationMs': _duration.inMilliseconds,
      'isPlaying': _playing,
      'audioTrack': audioTrack,
      'subtitleTrack': subtitleTrack,
      'sizeBytes': widget.video.sizeBytes,
      'source': widget.video.source.name,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _attachAutoSubtitleIfAvailable() async {
    final preferred = PlayraStorage.getPreferredSubtitleTrackKey(widget.video.id);
    if (preferred != null && preferred.isNotEmpty) return;

    final settings = PlayraStorage.getPlayerSettings();
    if (settings.defaultSubtitleLanguage.trim().isNotEmpty) return;

    final current = _player.state.track.subtitle;
    if (current.id != 'auto' && current.id != 'no') {
      return;
    }

    final candidates = await _subtitleCandidates();
    if (candidates.isEmpty) return;

    final first = candidates.first;
    final track = SubtitleTrack.uri(first, title: p.basename(Uri.parse(first).path));
    final subtitleSet = await _runPlayerAction(() => _player.setSubtitleTrack(track), operation: 'set auto subtitle');
    if (!subtitleSet) return;
    await PlayraStorage.savePreferredSubtitleTrackKey(widget.video.id, _subtitleTrackKey(track));
  }

  Future<List<String>> _subtitleCandidates() async {
    final out = <String>[];

    // SMB playback is converted to local HTTP proxy URL, but the original SMB URI
    // remains in `video.id` and identifies when we should probe proxy sibling files.
    if (widget.video.id.startsWith('smb://')) {
      final fromProxy = await _subtitleCandidatesForProxyVideoUrl(widget.video.uri);
      out.addAll(fromProxy);
      return out;
    }

    if (widget.video.source == VideoSource.local) {
      final localPath = widget.video.uri;
      final dir = p.dirname(localPath);
      final base = p.basenameWithoutExtension(localPath);
      final names = <String>['$base.srt', '$base.cs.srt', '$base.cz.srt', '$base.czech.srt', '$base.en.srt', '$base.english.srt'];
      for (final name in names) {
        final candidate = p.join(dir, name);
        if (await File(candidate).exists()) {
          out.add(Uri.file(candidate).toString());
        }
      }
    }

    return out;
  }

  Future<List<String>> _subtitleCandidatesForProxyVideoUrl(String videoUrl) async {
    try {
      final uri = Uri.parse(videoUrl);
      final segments = uri.pathSegments;
      if (segments.length < 3 || segments.first != 'play') return const [];

      final videoName = segments.last;
      final dot = videoName.lastIndexOf('.');
      if (dot <= 0) return const [];
      final base = videoName.substring(0, dot);

      final names = <String>['$base.srt', '$base.cs.srt', '$base.cz.srt', '$base.czech.srt', '$base.en.srt', '$base.english.srt'];

      final found = <String>[];
      for (final name in names) {
        final candidateSegments = [...segments]..[candidateIndex(segments)] = name;
        final candidate = uri.replace(pathSegments: candidateSegments, query: null, fragment: null);
        if (await _remoteFileExists(candidate)) {
          found.add(candidate.toString());
        }
      }

      return found;
    } catch (_) {
      return const [];
    }
  }

  int candidateIndex(List<String> segments) => segments.length - 1;

  Future<bool> _remoteFileExists(Uri uri) async {
    final client = HttpClient();
    try {
      final req = await client.headUrl(uri);
      final res = await req.close();
      return res.statusCode == HttpStatus.ok || res.statusCode == HttpStatus.partialContent;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void _scheduleResumePersist() {
    if (_resumePersistTimer?.isActive ?? false) return;
    _resumePersistTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_persistResumeNow());
    });
  }

  Future<void> _persistResumeNow() async {
    final ms = _position.inMilliseconds;
    if (ms <= 0 || ms == _lastPersistedResumeMs) return;
    _lastPersistedResumeMs = ms;
    await PlayraStorage.setResume(widget.video.id, ms);
  }

  Future<void> _restorePreferredTracks() async {
    final audioPref = _pendingAudioTrackPref ?? PlayraStorage.getPreferredAudioTrackKey(widget.video.id);
    final subPref = _pendingSubtitleTrackPref ?? PlayraStorage.getPreferredSubtitleTrackKey(widget.video.id);
    final settings = PlayraStorage.getPlayerSettings();

    var appliedAudio = audioPref == null;
    var appliedSubtitle = subPref == null;

    if (audioPref != null) {
      final tracks = _player.state.tracks.audio;
      final matched = _matchAudioTrack(tracks, audioPref);
      if (matched != null) {
        final setAudio = await _runPlayerAction(() => _player.setAudioTrack(matched), operation: 'restore preferred audio track');
        if (!setAudio) return;
        appliedAudio = true;
      }
    } else {
      final defaultAudioLang = settings.defaultAudioLanguage.trim();
      if (defaultAudioLang.isNotEmpty) {
        final tracks = _player.state.tracks.audio;
        final matched = _matchAudioTrackByLanguage(tracks, defaultAudioLang);
        if (matched != null) {
          final setAudio = await _runPlayerAction(() => _player.setAudioTrack(matched), operation: 'set default audio language track');
          if (!setAudio) return;
          await PlayraStorage.savePreferredAudioTrackKey(widget.video.id, _audioTrackKey(matched));
          appliedAudio = true;
        }
      }
    }

    if (subPref != null) {
      final tracks = _player.state.tracks.subtitle;
      final matched = _matchSubtitleTrack(tracks, subPref);
      if (matched != null) {
        final setSub = await _runPlayerAction(() => _player.setSubtitleTrack(matched), operation: 'restore preferred subtitle track');
        if (!setSub) return;
        appliedSubtitle = true;
      }
    } else {
      final defaultSubtitleLang = settings.defaultSubtitleLanguage.trim();
      if (defaultSubtitleLang.isNotEmpty) {
        final tracks = _player.state.tracks.subtitle;
        final matched = _matchSubtitleTrackByLanguage(tracks, defaultSubtitleLang);
        if (matched != null) {
          final setSub = await _runPlayerAction(() => _player.setSubtitleTrack(matched), operation: 'set default subtitle language track');
          if (!setSub) return;
          await PlayraStorage.savePreferredSubtitleTrackKey(widget.video.id, _subtitleTrackKey(matched));
          appliedSubtitle = true;
        }
      }
    }

    if (appliedAudio) _pendingAudioTrackPref = null;
    if (appliedSubtitle) _pendingSubtitleTrackPref = null;
    _preferredTracksApplied = appliedAudio && appliedSubtitle;
  }

  void _schedulePreferredTrackRestore() {
    if (_preferredTracksApplied) return;
    if (_preferredTrackRestoreAttempts >= 8) return;

    _preferredTrackRestoreAttempts += 1;
    Timer(const Duration(milliseconds: 500), () async {
      if (!mounted || _preferredTracksApplied) return;
      await _restorePreferredTracks();
      _schedulePreferredTrackRestore();
    });
  }

  AudioTrack? _matchAudioTrack(List<AudioTrack> tracks, String storedKey) {
    final parsed = _parseStoredTrackKey(storedKey);

    for (final track in tracks) {
      if (_audioTrackKey(track) == storedKey) return track;
    }

    for (final track in tracks) {
      if (_stableAudioTrackKey(track) == '${parsed.title}|${parsed.language}') return track;
    }

    if (parsed.title.isNotEmpty) {
      for (final track in tracks) {
        if (_normalizeTrackPart(track.title) == parsed.title) return track;
      }
    }

    if (parsed.language.isNotEmpty) {
      for (final track in tracks) {
        if (_normalizeTrackPart(track.language) == parsed.language) return track;
      }
    }

    return null;
  }

  AudioTrack? _matchAudioTrackByLanguage(List<AudioTrack> tracks, String languageCode) {
    for (final track in tracks) {
      if (_isLanguageMatch(track.language, languageCode)) return track;
    }
    return null;
  }

  SubtitleTrack? _matchSubtitleTrack(List<SubtitleTrack> tracks, String storedKey) {
    final parsed = _parseStoredTrackKey(storedKey);

    for (final track in tracks) {
      if (_subtitleTrackKey(track) == storedKey) return track;
    }

    for (final track in tracks) {
      if (_stableSubtitleTrackKey(track) == '${parsed.title}|${parsed.language}') return track;
    }

    if (parsed.title.isNotEmpty) {
      for (final track in tracks) {
        if (_normalizeTrackPart(track.title) == parsed.title) return track;
      }
    }

    if (parsed.language.isNotEmpty) {
      for (final track in tracks) {
        if (_normalizeTrackPart(track.language) == parsed.language) return track;
      }
    }

    return null;
  }

  SubtitleTrack? _matchSubtitleTrackByLanguage(List<SubtitleTrack> tracks, String languageCode) {
    for (final track in tracks) {
      if (_isLanguageMatch(track.language, languageCode)) return track;
    }
    return null;
  }

  bool _isLanguageMatch(String? trackLanguage, String expectedLanguage) {
    final track = _normalizeTrackPart(trackLanguage);
    final expected = _normalizeTrackPart(expectedLanguage);
    if (track.isEmpty || expected.isEmpty) return false;
    if (track == expected) return true;
    if (track.startsWith('$expected-')) return true;
    if (track.startsWith('${expected}_')) return true;
    if (track.startsWith(expected)) return true;
    return false;
  }

  String _audioTrackKey(AudioTrack t) {
    return _stableAudioTrackKey(t);
  }

  String _subtitleTrackKey(SubtitleTrack t) {
    return _stableSubtitleTrackKey(t);
  }

  Future<void> _seekRelative(Duration delta) async {
    final target = _position + delta;
    final maxMs = _duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds;
    final clamped = Duration(milliseconds: target.inMilliseconds.clamp(0, maxMs));
    final seekOk = await _runPlayerAction(() => _player.seek(clamped), operation: 'relative seek');
    if (!seekOk) return;
    _scheduleResumePersist();
    _flashOverlay(delta.isNegative ? Icons.fast_rewind : Icons.fast_forward, _formatDuration(clamped));
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _showControls = false);
    });
  }

  void _flashOverlay(IconData icon, String text) {
    _overlayTimer?.cancel();
    setState(() {
      _showOverlay = true;
      _overlayIcon = icon;
      _overlayText = text;
    });
    _overlayTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _showOverlay = false);
    });
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '$m:${two(s)}';
  }

  void _toggleFullscreenFit() {
    final currentIndex = _videoFitModes.indexOf(_videoFitMode);
    final nextIndex = (currentIndex + 1) % _videoFitModes.length;
    final nextMode = _videoFitModes[nextIndex];
    setState(() => _videoFitMode = nextMode);
    _flashOverlay(_videoFitIcon(nextMode), _videoFitLabel(nextMode));
  }

  void _setVideoFitMode(String mode) {
    setState(() => _videoFitMode = mode);
    _flashOverlay(_videoFitIcon(mode), _videoFitLabel(mode));
    _startHideTimer();
  }

  void _setVideoZoom(double zoom) {
    final clamped = zoom.clamp(1.0, 2.5);
    setState(() => _videoZoom = clamped);
    _flashOverlay(Icons.zoom_in, '${clamped.toStringAsFixed(2)}x');
    _startHideTimer();
  }

  void _resetVideoScale() {
    setState(() {
      _videoFitMode = 'scaleDown';
      _videoZoom = 1.0;
    });
    _flashOverlay(Icons.center_focus_strong, '1.00x');
    _startHideTimer();
  }

  BoxFit _currentVideoBoxFit() {
    switch (_videoFitMode) {
      case 'scaleDown':
        return BoxFit.scaleDown;
      case 'contain':
      default:
        return BoxFit.contain;
    }
  }

  IconData _videoFitIcon(String mode) {
    switch (mode) {
      case 'scaleDown':
        return Icons.photo_size_select_small;
      case 'contain':
      default:
        return Icons.fit_screen;
    }
  }

  String _videoFitLabel(String mode) {
    switch (mode) {
      case 'scaleDown':
        return 'Original';
      case 'contain':
      default:
        return 'Fit';
    }
  }

  Future<void> _showVideoScaleOptions() async {
    _startHideTimer();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: StatefulBuilder(
          builder: (sheetCtx, setSheetState) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: SizedBox(width: 40, child: Divider(thickness: 4, color: Colors.grey)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Video Scale',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _videoFitModes.map((mode) {
                    final selected = _videoFitMode == mode;
                    return ChoiceChip(
                      label: Text(_videoFitLabel(mode)),
                      selected: selected,
                      onSelected: (_) {
                        _setVideoFitMode(mode);
                        setSheetState(() {});
                      },
                      labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
                      selectedColor: Colors.white,
                      backgroundColor: Colors.grey[800],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.zoom_in, color: Colors.white70),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        min: 1.0,
                        max: 2.5,
                        divisions: 15,
                        value: _videoZoom,
                        label: '${_videoZoom.toStringAsFixed(2)}x',
                        onChanged: (value) {
                          _setVideoZoom(value);
                          setSheetState(() {});
                        },
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${_videoZoom.toStringAsFixed(2)}x',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      _resetVideoScale();
                      setSheetState(() {});
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playNextEpisode() async {
    final next = _nextEpisode;
    if (next == null) return;
    await PlayraStorage.addRecent(next);
    if (!mounted) return;
    await context.read<PlayerLauncher>().launchReplacement(context, next);
  }

  Future<void> _onDoubleTapToggleFullscreen() async {
    if (_isDesktopPlatform) {
      final settings = PlayraStorage.getPlayerSettings();
      final action = settings.desktopDoubleClickAction;
      if (action == 'none') {
        return;
      }
      _executeDesktopAction(action);
      return;
    }

    if (_playing) {
      await _runPlayerAction(() => _player.pause(), operation: 'pause on double tap');
      _flashOverlay(Icons.pause, 'Pause');
    } else {
      await _runPlayerAction(() => _player.play(), operation: 'play on double tap');
      _flashOverlay(Icons.play_arrow, 'Play');
    }
    _startHideTimer();
  }

  String _formatShortcutFromKeyEvent(KeyEvent event) {
    final parts = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) parts.add('Ctrl');
    if (HardwareKeyboard.instance.isAltPressed) parts.add('Alt');
    if (HardwareKeyboard.instance.isShiftPressed) parts.add('Shift');
    if (HardwareKeyboard.instance.isMetaPressed) parts.add('Meta');

    final key = event.logicalKey;
    final label = key.keyLabel.trim();
    if (label.isNotEmpty && label.length <= 2) {
      parts.add(label.toUpperCase());
      return parts.join('+');
    }

    if (key == LogicalKeyboardKey.space) {
      parts.add('Space');
    } else if (key == LogicalKeyboardKey.enter) {
      parts.add('Enter');
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      parts.add('Arrow Left');
    } else if (key == LogicalKeyboardKey.arrowRight) {
      parts.add('Arrow Right');
    } else if (key == LogicalKeyboardKey.arrowUp) {
      parts.add('Arrow Up');
    } else if (key == LogicalKeyboardKey.arrowDown) {
      parts.add('Arrow Down');
    } else {
      final name = key.debugName ?? key.keyLabel;
      parts.add(name.replaceFirst('Logical Keyboard Key ', ''));
    }

    return parts.join('+');
  }

  bool _shortcutMatches(KeyEvent event, String shortcut) {
    final normalizedTarget = shortcut.replaceAll(' ', '').toLowerCase();
    final normalizedCurrent = _formatShortcutFromKeyEvent(event).replaceAll(' ', '').toLowerCase();
    return normalizedTarget == normalizedCurrent;
  }

  bool _hasAnyModifierPressed() {
    return HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isMetaPressed;
  }

  bool _shortcutRequiresNoModifier(String shortcut) {
    final s = shortcut.toLowerCase();
    return !s.contains('ctrl') && !s.contains('alt') && !s.contains('shift') && !s.contains('meta');
  }

  bool _shortcutAllowedInCurrentModifierState(String shortcut) {
    if (_shortcutRequiresNoModifier(shortcut)) {
      return !_hasAnyModifierPressed();
    }
    return true;
  }

  bool _tryHandleShortcut(KeyEvent event, String shortcut, VoidCallback handler) {
    if (shortcut.trim().isEmpty) return false;
    if (!_shortcutAllowedInCurrentModifierState(shortcut)) return false;
    if (_shortcutMatches(event, shortcut)) {
      handler();
      return true;
    }
    return false;
  }

  Future<void> _toggleDesktopFullscreen() async {
    if (!_isDesktopPlatform) return;
    final isFullscreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFullscreen);
    _flashOverlay(!isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, !isFullscreen ? 'Fullscreen' : 'Windowed');
    _startHideTimer();
  }

  KeyEventResult _handleDesktopKeyEvent(KeyEvent event, PlayerSettings settings) {
    if (!_isDesktopPlatform || !settings.desktopShortcutsEnabled) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (_tryHandleShortcut(event, settings.desktopPlayPauseShortcut, () {
      unawaited(_runPlayerAction(() => _playing ? _player.pause() : _player.play(), operation: 'desktop shortcut play/pause'));
      _startHideTimer();
    })) {
      return KeyEventResult.handled;
    }

    if (_shortcutMatches(event, settings.desktopFullscreenShortcut) && _shortcutAllowedInCurrentModifierState(settings.desktopFullscreenShortcut)) {
      _toggleDesktopFullscreen();
      return KeyEventResult.handled;
    }

    if (_tryHandleShortcut(event, settings.desktopSeekBackwardShortcut, () {
      _seekRelative(Duration(seconds: -settings.seekStepSeconds.toInt()));
    })) {
      return KeyEventResult.handled;
    }

    if (_tryHandleShortcut(event, settings.desktopSeekForwardShortcut, () {
      _seekRelative(Duration(seconds: settings.seekStepSeconds.toInt()));
    })) {
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _executeDesktopAction(String action) async {
    final settings = PlayraStorage.getPlayerSettings();
    switch (action) {
      case 'fullscreen':
        _toggleDesktopFullscreen();
        break;
      case 'fit':
        _toggleFullscreenFit();
        break;
      case 'toggleControls':
        _toggleControls();
        break;
      case 'seekBackward':
        await _seekRelative(Duration(seconds: -settings.seekStepSeconds.toInt()));
        break;
      case 'seekForward':
        await _seekRelative(Duration(seconds: settings.seekStepSeconds.toInt()));
        break;
      case 'volumeUp':
        try {
          final current = await FlutterVolumeController.getVolume() ?? 0.5;
          final next = (current + 0.1).clamp(0.0, 1.0);
          await FlutterVolumeController.setVolume(next);
          _flashOverlay(Icons.volume_up, '${(next * 100).round()}%');
        } catch (_) {}
        break;
      case 'volumeDown':
        try {
          final current = await FlutterVolumeController.getVolume() ?? 0.5;
          final next = (current - 0.1).clamp(0.0, 1.0);
          await FlutterVolumeController.setVolume(next);
          _flashOverlay(Icons.volume_down, '${(next * 100).round()}%');
        } catch (_) {}
        break;
      case 'brightnessUp':
        try {
          final current = await ScreenBrightness.instance.application;
          final next = (current + 0.1).clamp(0.0, 1.0);
          await ScreenBrightness.instance.setApplicationScreenBrightness(next);
          _flashOverlay(Icons.brightness_6, '${(next * 100).round()}%');
        } catch (_) {}
        break;
      case 'brightnessDown':
        try {
          final current = await ScreenBrightness.instance.application;
          final next = (current - 0.1).clamp(0.0, 1.0);
          await ScreenBrightness.instance.setApplicationScreenBrightness(next);
          _flashOverlay(Icons.brightness_6, '${(next * 100).round()}%');
        } catch (_) {}
        break;
    }
  }

  Future<void> _onDesktopPointerSignal(PointerSignalEvent signal, PlayerSettings settings) async {
    if (!_isDesktopPlatform || !settings.desktopShortcutsEnabled) return;
    if (signal is! PointerScrollEvent) return;

    final dir = signal.scrollDelta.dy > 0 ? -1.0 : 1.0;
    final action = settings.desktopWheelAction;

    if (action == 'none') return;

    if (action == 'seek') {
      await _seekRelative(Duration(seconds: (dir * settings.desktopWheelStep).round()));
      return;
    }

    if (action == 'volume') {
      final current = await FlutterVolumeController.getVolume() ?? 0.5;
      final delta = settings.desktopWheelStep / 100.0;
      final next = (current + (dir * delta)).clamp(0.0, 1.0);
      await FlutterVolumeController.setVolume(next);
      _flashOverlay(Icons.volume_up, '${(next * 100).round()}%');
      return;
    }

    if (action == 'brightness') {
      try {
        final current = await ScreenBrightness.instance.application;
        final delta = settings.desktopWheelStep / 100.0;
        final next = (current + (dir * delta)).clamp(0.0, 1.0);
        await ScreenBrightness.instance.setApplicationScreenBrightness(next);
        _flashOverlay(Icons.brightness_6, '${(next * 100).round()}%');
      } catch (_) {}
    }
  }

  Future<void> _onVerticalDrag(DragUpdateDetails d, bool isLeft) async {
    final settings = PlayraStorage.getPlayerSettings();
    if (_isDesktopPlatform || !settings.gesturesEnabled) return;
    final size = MediaQuery.of(context).size;
    final delta = -d.delta.dy / (size.height * 0.6);
    if (isLeft) {
      try {
        final current = await ScreenBrightness.instance.application;
        final newVal = (current + delta).clamp(0.0, 1.0);
        await ScreenBrightness.instance.setApplicationScreenBrightness(newVal);
        _flashOverlay(Icons.brightness_6, '${(newVal * 100).round()}%');
      } catch (_) {}
    } else {
      try {
        final current = await FlutterVolumeController.getVolume() ?? 0.5;
        final newVal = (current + delta).clamp(0.0, 1.0);
        await FlutterVolumeController.setVolume(newVal);
        _flashOverlay(Icons.volume_up, '${(newVal * 100).round()}%');
      } catch (_) {}
    }
  }

  void _onHorizontalDragStart(DragStartDetails _, PlayerSettings settings) {
    if (_isDesktopPlatform || !settings.gesturesEnabled) return;
    _dragSeekPositionMs = _position.inMilliseconds;
  }

  void _onHorizontalDrag(DragUpdateDetails d, PlayerSettings settings) {
    if (_isDesktopPlatform || !settings.gesturesEnabled) return;

    final sensitivity = settings.touchSeekSensitivity.clamp(0.5, 12.0);
    final baseDeltaMs = ((d.primaryDelta ?? 0) * 560).round();
    final deltaMs = (baseDeltaMs * sensitivity).round();
    final currentBase = _dragSeekPositionMs ?? _position.inMilliseconds;
    final maxMs = _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds;
    final targetMs = (currentBase + deltaMs).clamp(0, maxMs);
    _dragSeekPositionMs = targetMs;

    final clamped = Duration(milliseconds: targetMs);
    unawaited(_runPlayerAction(() => _player.seek(clamped), operation: 'drag seek'));
    setState(() => _position = clamped);
    _scheduleResumePersist();
    _flashOverlay(deltaMs.isNegative ? Icons.fast_rewind : Icons.fast_forward, _formatDuration(clamped));
  }

  void _onHorizontalDragEnd(DragEndDetails _, PlayerSettings settings) {
    if (_isDesktopPlatform || !settings.gesturesEnabled) return;
    _dragSeekPositionMs = null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayraSettingsCubit, PlayraSettingsState>(
      builder: (context, settings) {
        final subtitleCfg = _subtitleConfig(settings.subtitleStyle);
        final touchGesturesEnabled = settings.player.gesturesEnabled;

        return Focus(
          focusNode: _keyboardFocusNode,
          autofocus: _isDesktopPlatform,
          onKeyEvent: (node, event) => _handleDesktopKeyEvent(event, settings.player),
          child: Listener(
            onPointerSignal: (signal) => _onDesktopPointerSignal(signal, settings.player),
            child: Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                top: false,
                bottom: false,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: _videoZoom == 1.0
                          ? Video(controller: _videoController, fit: _currentVideoBoxFit(), controls: (_) => const SizedBox.shrink(), subtitleViewConfiguration: subtitleCfg)
                          : Transform.scale(
                              scale: _videoZoom,
                              child: Video(
                                controller: _videoController,
                                fit: _currentVideoBoxFit(),
                                controls: (_) => const SizedBox.shrink(),
                                subtitleViewConfiguration: subtitleCfg,
                              ),
                            ),
                    ),

                    Positioned.fill(
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _toggleControls,
                              onDoubleTap: _onDoubleTapToggleFullscreen,
                              onVerticalDragUpdate: touchGesturesEnabled ? (d) => _onVerticalDrag(d, true) : null,
                              onHorizontalDragStart: touchGesturesEnabled ? (d) => _onHorizontalDragStart(d, settings.player) : null,
                              onHorizontalDragUpdate: touchGesturesEnabled ? (d) => _onHorizontalDrag(d, settings.player) : null,
                              onHorizontalDragEnd: touchGesturesEnabled ? (d) => _onHorizontalDragEnd(d, settings.player) : null,
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _toggleControls,
                              onDoubleTap: _onDoubleTapToggleFullscreen,
                              onVerticalDragUpdate: touchGesturesEnabled ? (d) => _onVerticalDrag(d, false) : null,
                              onHorizontalDragStart: touchGesturesEnabled ? (d) => _onHorizontalDragStart(d, settings.player) : null,
                              onHorizontalDragUpdate: touchGesturesEnabled ? (d) => _onHorizontalDrag(d, settings.player) : null,
                              onHorizontalDragEnd: touchGesturesEnabled ? (d) => _onHorizontalDragEnd(d, settings.player) : null,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_showOverlay && _overlayText != null)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_overlayIcon != null) ...[Icon(_overlayIcon, color: Colors.white, size: 28), const SizedBox(width: 10)],
                              Text(_overlayText!, style: const TextStyle(color: Colors.white, fontSize: 18)),
                            ],
                          ),
                        ),
                      ),

                    if (_showControls) Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
                    if (_showControls) Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar(MediaQuery.of(context).size)),

                    if (_hasFatalPlaybackError) Positioned.fill(child: _buildFatalPlaybackOverlay()),

                    if (!_isReady) const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFatalPlaybackOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            color: Colors.grey[900],
            margin: const EdgeInsets.symmetric(horizontal: 24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                  const SizedBox(height: 10),
                  const Text(
                    'Playback failed',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fatalPlaybackMessage ?? 'An unexpected playback error occurred.',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
                      const SizedBox(width: 10),
                      FilledButton(onPressed: _openMedia, child: const Text('Retry')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  SubtitleViewConfiguration _subtitleConfig(SubtitleStyleSettings s) {
    if (!s.enabled) {
      return const SubtitleViewConfiguration(visible: false);
    }
    return SubtitleViewConfiguration(
      visible: true,
      style: TextStyle(
        height: 1.4,
        fontSize: s.fontSize,
        fontFamily: s.fontFamily,
        color: Color(s.textColor),
        fontWeight: s.bold ? FontWeight.bold : FontWeight.normal,
        backgroundColor: Color(s.backgroundColor),
        shadows: s.outlineWidth > 0
            ? [
                for (final dx in [-s.outlineWidth, 0.0, s.outlineWidth])
                  for (final dy in [-s.outlineWidth, 0.0, s.outlineWidth])
                    if (dx != 0 || dy != 0) Shadow(offset: Offset(dx, dy), color: Color(s.outlineColor), blurRadius: 0),
              ]
            : null,
      ),
      textAlign: TextAlign.center,
      padding: EdgeInsets.fromLTRB(16, 0, 16, s.bottomPadding),
    );
  }

  /// Downloads the current SMB video (and subtitle sidecars) to the device's
  /// local documents folder using direct SMB reads. Shows a progress dialog.
  Future<void> _downloadToDevice() async {
    if (_isDownloading) return;

    final videoName = widget.video.name;
    final uri = widget.video.id;
    if (!uri.startsWith('smb://')) return;
    final rest = uri.substring(6);
    final slash = rest.indexOf('/');
    if (slash < 0) return;
    final serverId = rest.substring(0, slash);
    final smbPath = rest.substring(slash);
    final server = PlayraStorage.getServers().firstWhere(
      (s) => s.id == serverId,
      orElse: () => ServerConnection(id: '', name: '', type: ServerType.smb, host: ''),
    );
    if (server.id.isEmpty) return;

    final launcher = context.read<PlayerLauncher>();

    final token = DownloadCancellationToken();
    setState(() {
      _isDownloading = true;
      _downloadToken = token;
    });

    String? received;
    String? total;
    double? progress;
    void Function(void Function())? refreshDialog;
    var lastDialogUpdateMs = 0;
    var isDialogOpen = true;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              refreshDialog = setDialogState;
              return AlertDialog(
                title: Text('downloads.downloading'.tr()),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 12),
                    Text(received != null && total != null ? '$received / $total' : videoName, style: const TextStyle(fontSize: 13), textAlign: TextAlign.center),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      token.cancel();
                      Navigator.of(ctx).pop();
                    },
                    child: Text('common.cancel'.tr()),
                  ),
                ],
              );
            },
          );
        },
      ).whenComplete(() => isDialogOpen = false),
    );

    try {
      await SmbDownloadService.downloadVideoDirect(
        browser: launcher.browser,
        server: server,
        smbPath: smbPath,
        videoName: videoName,
        onProgress: (r, t, name) {
          received = SmbDownloadService.formatBytes(r);
          total = t > 0 ? SmbDownloadService.formatBytes(t) : '?';
          progress = t > 0 ? (r / t).clamp(0.0, 1.0) : null;

          final now = DateTime.now().millisecondsSinceEpoch;
          if (refreshDialog != null && (now - lastDialogUpdateMs >= 100 || t > 0 && r >= t)) {
            lastDialogUpdateMs = now;
            refreshDialog!.call(() {});
          }
        },
        cancellationToken: token,
      );

      if (isDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;

      if (!token.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('downloads.download_done'.tr(args: [widget.video.displayName]))));
      }
    } catch (e) {
      if (isDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;
      if (!token.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('downloads.download_error'.tr(args: [e.toString()]))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadToken = null;
        });
      }
    }
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent]),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              widget.video.displayName,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.subtitles, color: Colors.white),
            tooltip: 'player.subtitle_track'.tr(),
            onPressed: _showSubtitleOptions,
          ),
          IconButton(
            icon: const Icon(Icons.audiotrack, color: Colors.white),
            tooltip: 'player.audio_track'.tr(),
            onPressed: _pickAudioTrack,
          ),
          IconButton(
            icon: Icon(_videoFitIcon(_videoFitMode), color: Colors.white),
            tooltip: 'Video Scale',
            onPressed: _showVideoScaleOptions,
          ),
          if (_isDesktopPlatform)
            IconButton(
              icon: const Icon(Icons.fullscreen, color: Colors.white),
              tooltip: 'Fullscreen',
              onPressed: _toggleDesktopFullscreen,
            ),
          if (_nextEpisode != null)
            IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.white),
              tooltip: 'video.continue_next_episode'.tr(),
              onPressed: _playNextEpisode,
            ),
          if (!_isDesktopPlatform && widget.video.source == VideoSource.smb)
            IconButton(
              icon: _isDownloading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download, color: Colors.white),
              tooltip: 'downloads.download_to_device'.tr(),
              onPressed: _isDownloading ? null : _downloadToDevice,
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(Size size) {
    final dur = _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds;
    final trackHeight = _isTouchPlatform ? 18.0 : 4.0;
    final thumbRadius = _isTouchPlatform ? 14.0 : 8.0;
    final overlayRadius = _isTouchPlatform ? 24.0 : 14.0;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_formatDuration(_position), style: const TextStyle(color: Colors.white, fontSize: 12)),
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: Center(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: trackHeight,
                        thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbRadius),
                        overlayShape: RoundSliderOverlayShape(overlayRadius: overlayRadius),
                        activeTrackColor: Colors.redAccent,
                      ),
                      child: Slider(
                        value: _position.inMilliseconds.clamp(0, dur).toDouble(),
                        max: dur.toDouble(),
                        min: 0,
                        onChanged: (v) {
                          setState(() => _position = Duration(milliseconds: v.toInt()));
                        },
                        onChangeEnd: (v) {
                          unawaited(_runPlayerAction(() => _player.seek(Duration(milliseconds: v.toInt())), operation: 'seek from progress bar'));
                          _scheduleResumePersist();
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_30, color: Colors.white, size: 30),
                onPressed: () => _seekRelative(const Duration(seconds: -30)),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white, size: 32),
                onPressed: () => _seekRelative(const Duration(seconds: -10)),
              ),
              const SizedBox(width: 8),
              IconButton(
                iconSize: 72,
                icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
                onPressed: () {
                  unawaited(_runPlayerAction(() => _playing ? _player.pause() : _player.play(), operation: 'bottom controls play/pause'));
                  _startHideTimer();
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white, size: 32),
                onPressed: () => _seekRelative(const Duration(seconds: 10)),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.forward_30, color: Colors.white, size: 30),
                onPressed: () => _seekRelative(const Duration(seconds: 30)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAudioTrack() async {
    final tracks = _player.state.tracks.audio;
    final current = _player.state.track.audio;
    final picked = await _showTrackPicker<AudioTrack>(title: 'player.audio_track'.tr(), tracks: tracks, current: current, label: (t) => t.title ?? t.language ?? t.id);
    if (picked != null) {
      final setAudio = await _runPlayerAction(() => _player.setAudioTrack(picked), operation: 'set picked audio track');
      if (!setAudio) return;
      await PlayraStorage.savePreferredAudioTrackKey(widget.video.id, _audioTrackKey(picked));
    }
  }

  Future<void> _showSubtitleOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _SubtitleOptionsSheet(player: _player, video: widget.video, onOpenSubtitleDelayPopup: _showSubtitleDelayPopup),
    );
  }

  Future<void> _setSubtitleDelayMs(int value) async {
    final clamped = value.clamp(-120000, 120000);
    await PlayraStorage.saveSubtitleDelayMs(widget.video.id, clamped);

    final dynamic platform = _player.platform;
    final seconds = (clamped / 1000.0).toStringAsFixed(3);
    try {
      await platform.setProperty('sub-delay', seconds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Playback error: $e')));
      }
    }
  }

  String _subtitleDelayLabel(int valueMs) {
    final value = (valueMs / 1000).toStringAsFixed(2);
    if (valueMs == 0) return '0.00 s';
    return valueMs > 0 ? '+$value s' : '$value s';
  }

  void _restartSubtitleDelayPopupTimer(BuildContext dialogContext) {
    _subtitleDelayPopupTimer?.cancel();
    _subtitleDelayPopupTimer = Timer(const Duration(seconds: 10), () {
      if (Navigator.of(dialogContext, rootNavigator: true).canPop()) {
        Navigator.of(dialogContext, rootNavigator: true).pop();
      }
    });
  }

  Future<void> _showSubtitleDelayPopup() async {
    var currentDelayMs = PlayraStorage.getSubtitleDelayMs(widget.video.id);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        _restartSubtitleDelayPopupTimer(dialogCtx);
        return StatefulBuilder(
          builder: (ctx, setDialogState) => Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 72, vertical: 24),
            backgroundColor: Colors.black.withValues(alpha: 0.72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'settings.subtitle_delay'.tr(),
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitleDelayLabel(currentDelayMs),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _delayActionButton(
                        icon: Icons.remove_circle_outline,
                        label: '-10',
                        onTap: () async {
                          _restartSubtitleDelayPopupTimer(dialogCtx);
                          currentDelayMs = (currentDelayMs - 10000).clamp(-120000, 120000);
                          await _setSubtitleDelayMs(currentDelayMs);
                          if (!mounted) return;
                          setDialogState(() {});
                        },
                      ),
                      _delayActionButton(
                        icon: Icons.exposure_neg_1,
                        label: '-1',
                        onTap: () async {
                          _restartSubtitleDelayPopupTimer(dialogCtx);
                          currentDelayMs = (currentDelayMs - 1000).clamp(-120000, 120000);
                          await _setSubtitleDelayMs(currentDelayMs);
                          if (!mounted) return;
                          setDialogState(() {});
                        },
                      ),
                      _delayActionButton(
                        icon: Icons.restart_alt,
                        label: '0',
                        onTap: () async {
                          _restartSubtitleDelayPopupTimer(dialogCtx);
                          currentDelayMs = 0;
                          await _setSubtitleDelayMs(currentDelayMs);
                          if (!mounted) return;
                          setDialogState(() {});
                        },
                      ),
                      _delayActionButton(
                        icon: Icons.exposure_plus_1,
                        label: '+1',
                        onTap: () async {
                          _restartSubtitleDelayPopupTimer(dialogCtx);
                          currentDelayMs = (currentDelayMs + 1000).clamp(-120000, 120000);
                          await _setSubtitleDelayMs(currentDelayMs);
                          if (!mounted) return;
                          setDialogState(() {});
                        },
                      ),
                      _delayActionButton(
                        icon: Icons.add_circle_outline,
                        label: '+10',
                        onTap: () async {
                          _restartSubtitleDelayPopupTimer(dialogCtx);
                          currentDelayMs = (currentDelayMs + 10000).clamp(-120000, 120000);
                          await _setSubtitleDelayMs(currentDelayMs);
                          if (!mounted) return;
                          setDialogState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _subtitleDelayPopupTimer?.cancel();
  }

  Widget _delayActionButton({required IconData icon, required String label, required Future<void> Function() onTap}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          unawaited(onTap());
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<T?> _showTrackPicker<T>({required String title, required List<T> tracks, required T current, required String Function(T) label}) async {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...tracks.map(
              (t) => ListTile(
                leading: Icon(t == current ? Icons.radio_button_checked : Icons.radio_button_off, color: Colors.white),
                title: Text(label(t), style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(ctx).pop(t),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtitleOptionsSheet extends StatefulWidget {
  final Player player;
  final VideoItem video;
  final Future<void> Function() onOpenSubtitleDelayPopup;

  const _SubtitleOptionsSheet({required this.player, required this.video, required this.onOpenSubtitleDelayPopup});

  @override
  State<_SubtitleOptionsSheet> createState() => _SubtitleOptionsSheetState();
}

class _SubtitleOptionsSheetState extends State<_SubtitleOptionsSheet> {
  static const List<int> _palette = [0xFFFFFFFF, 0xFFFFEB3B, 0xFFFF5252, 0xFF40C4FF, 0xFF69F0AE, 0xFFFFA726, 0xFFE040FB, 0xFFB0BEC5, 0xFF000000];

  static const List<int> _paletteWithTransparent = [
    0xFFFFFFFF,
    0xFFFFEB3B,
    0xFFFF5252,
    0xFF40C4FF,
    0xFF69F0AE,
    0xFFFFA726,
    0xFFE040FB,
    0xFFB0BEC5,
    0xFF000000,
    0x00000000,
    0x80000000,
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayraSettingsCubit, PlayraSettingsState>(
      builder: (context, settings) {
        final s = settings.subtitleStyle;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                ),
              ),

              _sectionHeader('player.subtitle_track'.tr()),
              ..._buildTrackTiles(s),

              const Divider(color: Colors.grey),

              ListTile(
                leading: const Icon(Icons.folder_open, color: Colors.white),
                title: Text('player.load_subtitle_file'.tr(), style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  final res = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['srt', 'ass', 'ssa', 'vtt', 'sub'],
                    dialogTitle: 'player.load_subtitle_file'.tr(),
                  );
                  if (res != null && res.files.isNotEmpty && res.files.first.path != null) {
                    final path = res.files.first.path!;
                    final track = SubtitleTrack.uri(Uri.file(path).toString(), title: res.files.first.name);
                    try {
                      await widget.player.setSubtitleTrack(track);
                    } catch (e, st) {
                      debugPrint('Playra subtitle track set failed [file picker]: $e\n$st');
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Playback error: $e')));
                      }
                      return;
                    }
                    await PlayraStorage.savePreferredSubtitleTrackKey(widget.video.id, _subtitleTrackKey(track));
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
              ),

              const Divider(color: Colors.grey),

              _sectionHeader('settings.section_subtitles'.tr()),
              SwitchListTile(
                tileColor: Colors.transparent,
                title: Text('settings.subtitles_enabled'.tr(), style: const TextStyle(color: Colors.white)),
                value: s.enabled,
                onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(enabled: v)),
              ),
              ListTile(
                title: Text('settings.subtitle_delay'.tr(), style: const TextStyle(color: Colors.white)),
                subtitle: Text('settings.subtitle_delay_popup_hint'.tr(), style: const TextStyle(color: Colors.grey)),
                trailing: const Icon(Icons.tune, color: Colors.white70),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  await Future<void>.delayed(const Duration(milliseconds: 120));
                  await widget.onOpenSubtitleDelayPopup();
                },
              ),
              ListTile(
                title: Text('settings.subtitle_size'.tr(), style: const TextStyle(color: Colors.white)),
                subtitle: Slider(
                  min: 10,
                  max: 96,
                  divisions: 86,
                  value: s.fontSize,
                  label: s.fontSize.toStringAsFixed(0),
                  onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(fontSize: v)),
                ),
              ),
              ListTile(
                title: Text('settings.subtitle_bottom_padding'.tr(), style: const TextStyle(color: Colors.white)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('settings.subtitle_bottom_padding_hint'.tr(), style: const TextStyle(color: Colors.grey)),
                    Slider(
                      min: 8,
                      max: 160,
                      divisions: 76,
                      value: s.bottomPadding.clamp(8, 160),
                      label: s.bottomPadding.toStringAsFixed(0),
                      onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(bottomPadding: v)),
                    ),
                  ],
                ),
              ),
              ListTile(
                title: Text('settings.subtitle_outline'.tr(), style: const TextStyle(color: Colors.white)),
                subtitle: Slider(
                  min: 0,
                  max: 5,
                  divisions: 10,
                  value: s.outlineWidth,
                  label: s.outlineWidth.toStringAsFixed(1),
                  onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(outlineWidth: v)),
                ),
              ),
              SwitchListTile(
                tileColor: Colors.transparent,
                title: Text('settings.subtitle_bold'.tr(), style: const TextStyle(color: Colors.white)),
                value: s.bold,
                onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(bold: v)),
              ),
              ListTile(
                title: Text('settings.subtitle_font'.tr(), style: const TextStyle(color: Colors.white)),
                trailing: DropdownButton<String>(
                  dropdownColor: Colors.grey[850],
                  value: s.fontFamily,
                  style: const TextStyle(color: Colors.white),
                  items: kAvailableSubtitleFonts.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(fontFamily: v));
                    }
                  },
                ),
              ),
              _colourTile(context, 'settings.subtitle_text_color'.tr(), s.textColor, _palette, (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(textColor: c))),
              _colourTile(
                context,
                'settings.subtitle_bg_color'.tr(),
                s.backgroundColor,
                _paletteWithTransparent,
                (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(backgroundColor: c)),
              ),
              _colourTile(
                context,
                'settings.subtitle_outline_color'.tr(),
                s.outlineColor,
                _palette,
                (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(outlineColor: c)),
              ),

              const Divider(color: Colors.grey),

              if (widget.video.source == VideoSource.local)
                ListTile(
                  leading: const Icon(Icons.cloud_download, color: Colors.white),
                  title: Text('player.download_subtitles'.tr(), style: const TextStyle(color: Colors.white)),
                  subtitle: Text('player.download_subtitles_hint'.tr(), style: const TextStyle(color: Colors.grey)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white),
                  onTap: () async {
                    // Pause playback before leaving the player to open subtitle search.
                    try {
                      await widget.player.pause();
                    } catch (e, st) {
                      debugPrint('Playra pause before subtitle search failed: $e\n$st');
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    final videoInfo = VideoInfo(path: widget.video.uri, name: widget.video.name, directory: _dirOf(widget.video.uri));
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SubtitleSearchScreen(videoInfo: videoInfo)));
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String _subtitleTrackKey(SubtitleTrack t) {
    return _stableSubtitleTrackKey(t);
  }

  List<Widget> _buildTrackTiles(SubtitleStyleSettings s) {
    final tracks = widget.player.state.tracks.subtitle;
    final current = widget.player.state.track.subtitle;
    if (tracks.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('player.no_subtitle_tracks'.tr(), style: const TextStyle(color: Colors.grey)),
        ),
      ];
    }

    return tracks.map((t) {
      final label = t.title ?? t.language ?? t.id;
      return ListTile(
        leading: Icon(t == current ? Icons.radio_button_checked : Icons.radio_button_off, color: Colors.white),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        onTap: () async {
          try {
            await widget.player.setSubtitleTrack(t);
          } catch (e, st) {
            debugPrint('Playra subtitle track set failed [sheet select]: $e\n$st');
            if (mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Playback error: $e')));
            }
            return;
          }
          await PlayraStorage.savePreferredSubtitleTrackKey(widget.video.id, _subtitleTrackKey(t));
          if (mounted) setState(() {});
        },
      );
    }).toList();
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[400], letterSpacing: 0.8),
      ),
    );
  }

  Widget _colourTile(BuildContext context, String title, int current, List<int> palette, ValueChanged<int> onChanged) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Color(current),
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: current == 0x00000000 ? const Icon(Icons.block, size: 16) : null,
      ),
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: palette
                  .map(
                    (c) => GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c),
                          border: Border.all(color: c == current ? Colors.blue : Colors.grey, width: c == current ? 3 : 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: c == 0x00000000 ? const Icon(Icons.block, size: 20) : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }

  String _dirOf(String path) {
    final slash = path.lastIndexOf(Platform.pathSeparator);
    return slash > 0 ? path.substring(0, slash) : '';
  }
}
