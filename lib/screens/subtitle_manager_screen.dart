import 'package:flutter/material.dart';

import 'library/video_library_screen.dart';

/// The legacy subtitle workflow (search/login/download/edit) lives in
/// [VideoLibraryScreen]. This wrapper just gives it a clean entry point
/// from the new settings screen.
class SubtitleManagerScreen extends StatelessWidget {
  const SubtitleManagerScreen({super.key});

  @override
  Widget build(BuildContext context) => const VideoLibraryScreen();
}
