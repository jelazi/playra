import 'package:media_kit/media_kit.dart';

/// Track identity helpers.
///
/// media_kit reassigns numeric track ids between sessions, so a remembered
/// audio or subtitle choice is stored as a normalised "title|language" key and
/// matched again on the next open.
String normalizeTrackPart(String? value) => (value ?? '').trim().toLowerCase();

String stableAudioTrackKey(AudioTrack track) => '${normalizeTrackPart(track.title)}|${normalizeTrackPart(track.language)}';

String stableSubtitleTrackKey(SubtitleTrack track) => '${normalizeTrackPart(track.title)}|${normalizeTrackPart(track.language)}';

({String title, String language, String id}) parseStoredTrackKey(String storedKey) {
  final parts = storedKey.split('|');
  return (
    title: parts.isNotEmpty ? parts[0].trim().toLowerCase() : '',
    language: parts.length > 1 ? parts[1].trim().toLowerCase() : '',
    id: parts.length > 2 ? parts.sublist(2).join('|').trim() : '',
  );
}
