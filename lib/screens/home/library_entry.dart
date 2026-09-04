import '../../models/video_item.dart';

/// One row of the flat or smart-grouped library list: either a section header
/// or a video underneath it.
class LibraryEntry {
  final String? sectionKey;
  final String? title;
  final int count;
  final bool? expanded;
  final bool? smartGroup;
  final String? posterPath;
  final VideoItem? video;

  bool get isHeader => sectionKey != null;

  const LibraryEntry.header({
    required this.sectionKey,
    required this.title,
    required this.count,
    required this.expanded,
    required this.smartGroup,
    this.posterPath,
  }) : video = null;

  const LibraryEntry.video(this.video)
    : sectionKey = null,
      title = null,
      count = 0,
      expanded = null,
      smartGroup = null,
      posterPath = null;
}

/// One row of the folder-mirroring library list: the link to the parent
/// directory, a subfolder, or a video in the current directory.
class StructuredEntry {
  final String? path;
  final String? title;
  final int count;
  final VideoItem? video;
  final bool isParent;
  final bool highlighted;

  bool get isFolder => !isParent && path != null && video == null;

  const StructuredEntry.parent({required this.path, this.highlighted = false})
    : title = '..',
      count = 0,
      video = null,
      isParent = true;

  const StructuredEntry.folder({required this.path, required this.title, required this.count, this.highlighted = false})
    : video = null,
      isParent = false;

  const StructuredEntry.video(this.video, {this.highlighted = false})
    : path = null,
      title = null,
      count = 0,
      isParent = false;
}
