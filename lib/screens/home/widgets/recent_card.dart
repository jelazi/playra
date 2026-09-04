import 'package:flutter/material.dart';

import '../../../widgets/poster_image.dart';

/// Poster tile in the "recently played" strip.
class RecentCard extends StatelessWidget {
  const RecentCard({
    super.key,
    required this.title,
    required this.posterPath,
    required this.onTap,
    required this.onMenu,
    this.onSecondaryTapDown,
  });

  final String title;
  final String? posterPath;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      onLongPress: onMenu,
      child: Container(
        width: 92,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage.file(
                      posterPath,
                      width: 92,
                      height: 136,
                      borderRadius: BorderRadius.circular(8),
                      fallback: Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.movie, size: 34, color: Colors.grey),
                      ),
                    ),
                    const Positioned(top: 4, right: 4, child: Icon(Icons.play_circle_outline, color: Colors.white, size: 18)),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onMenu,
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.more_vert, color: Colors.white, size: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
