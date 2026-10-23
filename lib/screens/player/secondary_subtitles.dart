import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Picture-based subtitle codecs (Blu-ray PGS, DVD VobSub, DVB). They carry no
/// text, so mpv has to draw them into the video itself.
const Set<String> _bitmapSubtitleCodecs = {'hdmv_pgs_subtitle', 'pgssub', 'dvd_subtitle', 'dvdsub', 'vobsub', 'dvb_subtitle', 'dvbsub', 'xsub'};

bool isBitmapSubtitle(SubtitleTrack? track) => track != null && _bitmapSubtitleCodecs.contains(track.codec?.toLowerCase());

/// mpv's secondary subtitle track (`secondary-sid`), a second line shown
/// under the main subtitles, e.g. for learning a language. media_kit has no
/// API for it but already delivers its text in `player.state.subtitle[1]`.
class SecondarySubtitles {
  SecondarySubtitles(this._player);

  final Player _player;

  /// The secondary track, or null when it is off.
  final ValueNotifier<SubtitleTrack?> selected = ValueNotifier<SubtitleTrack?>(null);

  NativePlayer? get _native {
    final platform = _player.platform;
    return platform is NativePlayer ? platform : null;
  }

  Future<void> select(SubtitleTrack track) async {
    final native = _native;
    if (native == null) return;
    await native.setProperty('secondary-sid', track.id);
    await native.setProperty('secondary-sub-visibility', isBitmapSubtitle(track) ? 'yes' : 'no');
    selected.value = track;
  }

  /// Loads a subtitle file without changing the main track and shows it as
  /// the secondary one.
  Future<SubtitleTrack?> addFile(String uri, String title) async {
    final native = _native;
    if (native == null) return null;
    await native.command(['sub-add', uri, 'auto', title]);

    // sub-add appends the new track to the end of mpv's track list.
    final count = int.tryParse(await native.getProperty('track-list/count')) ?? 0;
    for (var i = count - 1; i >= 0; i--) {
      if (await native.getProperty('track-list/$i/type') != 'sub') continue;
      final track = SubtitleTrack(await native.getProperty('track-list/$i/id'), title, null, uri: true);
      await select(track);
      return track;
    }
    return null;
  }

  Future<void> off() async {
    await _native?.setProperty('secondary-sid', 'no');
    await _native?.setProperty('secondary-sub-visibility', 'no');
    selected.value = null;
  }

  /// The main track as mpv numbers it. A file loaded through media_kit is
  /// known to it only by URI, so the id comes from mpv's `sid`.
  Future<SubtitleTrack?> mainTrack() async {
    final sid = await _native?.getProperty('sid');
    if (sid == null || sid.isEmpty || sid == 'no' || sid == 'auto') return null;
    return _player.state.tracks.subtitle.where((t) => t.id == sid).firstOrNull ?? SubtitleTrack(sid, null, null);
  }

  /// Text subtitles are drawn by the app; a picture-based main track only
  /// shows when mpv draws it.
  Future<void> syncMainTrackRendering(SubtitleTrack track) async {
    await _native?.setProperty('sub-visibility', isBitmapSubtitle(track) ? 'yes' : 'no');
  }

  void dispose() => selected.dispose();
}
