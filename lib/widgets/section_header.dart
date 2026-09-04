import 'package:flutter/material.dart';

/// Upper-case heading that introduces a group of settings or list rows.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.dense = false});

  final String title;

  /// Compact variant used inside sheets, where vertical space is tight.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: dense ? const EdgeInsets.fromLTRB(16, 16, 16, 4) : const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: dense
            ? theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.8)
            : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2, color: theme.colorScheme.primary),
      ),
    );
  }
}

/// Divider between two [SectionHeader] groups.
class SectionSeparator extends StatelessWidget {
  const SectionSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 0), child: Divider(height: 1, thickness: 1));
  }
}
