import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/downloads/downloads_cubit.dart';
import '../downloads_screen.dart';

/// Persistent bar shown at the bottom of the home screen whenever there are
/// active or recently finished downloads. Tapping opens the downloads panel.
class DownloadStatusBar extends StatelessWidget {
  const DownloadStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DownloadsCubit, DownloadsState>(
      builder: (context, state) {
        if (state.tasks.isEmpty) return const SizedBox.shrink();

        final active = state.active;
        final theme = Theme.of(context);

        double? aggregate;
        if (active.isNotEmpty) {
          final withProgress = active.where((t) => t.progress != null).toList();
          if (withProgress.isNotEmpty) {
            aggregate = withProgress.map((t) => t.progress!).reduce((a, b) => a + b) / withProgress.length;
          }
        }

        final String title;
        final IconData icon;
        if (active.isNotEmpty) {
          title = 'downloads.downloading_count'.tr(args: [active.length.toString()]);
          icon = Icons.downloading;
        } else {
          final failed = state.tasks.any((t) => t.status == DownloadStatus.failed);
          title = failed ? 'downloads.some_failed'.tr() : 'downloads.all_done'.tr();
          icon = failed ? Icons.error_outline : Icons.download_done;
        }

        return Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: SafeArea(
            top: false,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            aggregate != null ? '$title • ${(aggregate * 100).toStringAsFixed(0)} %' : title,
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (active.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: aggregate, minHeight: 3),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
