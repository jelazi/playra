import 'package:flutter/material.dart';

/// A bold label above a selectable value, used in the file/media info dialogs.
class LabelledValue extends StatelessWidget {
  const LabelledValue({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}
