import 'dart:io';

import 'package:flutter/material.dart';

/// Poster artwork with a consistent fallback, whether it comes from the local
/// poster cache or straight from TMDB.
///
/// Decoding is capped at twice the layout size so grids of posters do not hold
/// full-resolution bitmaps in memory.
class PosterImage extends StatelessWidget {
  const PosterImage._({required this.width, required this.height, required this.fallback, required this.borderRadius, this.filePath, this.url});

  /// Poster already downloaded into the local cache.
  factory PosterImage.file(
    String? path, {
    required double width,
    required double height,
    required Widget fallback,
    BorderRadius borderRadius = BorderRadius.zero,
  }) => PosterImage._(filePath: path, width: width, height: height, fallback: fallback, borderRadius: borderRadius);

  /// Poster served by TMDB.
  factory PosterImage.network(
    String? url, {
    required double width,
    required double height,
    required Widget fallback,
    BorderRadius borderRadius = BorderRadius.zero,
  }) => PosterImage._(url: url, width: width, height: height, fallback: fallback, borderRadius: borderRadius);

  final String? filePath;
  final String? url;
  final double width;
  final double height;
  final Widget fallback;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final source = filePath ?? url;
    if (source == null || source.isEmpty) return fallback;

    final image = filePath != null
        ? Image.file(
            File(filePath!),
            width: width,
            height: height,
            fit: BoxFit.cover,
            cacheWidth: width.round() * 2,
            cacheHeight: height.round() * 2,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.network(url!, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);

    return borderRadius == BorderRadius.zero ? image : ClipRRect(borderRadius: borderRadius, child: image);
  }
}
