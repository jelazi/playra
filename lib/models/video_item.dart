import 'dart:convert';

/// Playra video item – represents a video either on local disk or on a remote server.
enum VideoSource { local, smb, http }

class VideoItem {
  final String id; // stable id (path or server-uri)
  final String name;
  final String uri; // local path or smb://... or http://...
  final VideoSource source;
  final int? sizeBytes;
  final DateTime? modified;
  final String? folder; // parent folder name for grouping

  const VideoItem({required this.id, required this.name, required this.uri, required this.source, this.sizeBytes, this.modified, this.folder});

  String get displayName {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'uri': uri,
    'source': source.name,
    'sizeBytes': sizeBytes,
    'modified': modified?.toIso8601String(),
    'folder': folder,
  };

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
    id: json['id'] as String,
    name: json['name'] as String,
    uri: json['uri'] as String,
    source: VideoSource.values.firstWhere((v) => v.name == json['source'], orElse: () => VideoSource.local),
    sizeBytes: json['sizeBytes'] as int?,
    modified: json['modified'] != null ? DateTime.tryParse(json['modified'] as String) : null,
    folder: json['folder'] as String?,
  );

  String encode() => jsonEncode(toJson());
  static VideoItem decode(String s) => VideoItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// Supported video file extensions (lowercase, no dot).
const Set<String> kSupportedVideoExtensions = {
  'mp4',
  'mkv',
  'avi',
  'mov',
  'wmv',
  'flv',
  'webm',
  'mpeg',
  'mpg',
  'm4v',
  'ts',
  'mts',
  'm2ts',
  '3gp',
  '3g2',
  'ogv',
  'ogm',
  'rm',
  'rmvb',
  'vob',
  'asf',
  'divx',
  'f4v',
  'mxf',
  'qt',
};
