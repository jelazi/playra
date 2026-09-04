import 'package:flutter/material.dart';

/// Swatches offered for subtitle text and outline colours.
const List<int> kColorPalette = [0xFFFFFFFF, 0xFFFFEB3B, 0xFFFF5252, 0xFF40C4FF, 0xFF69F0AE, 0xFFFFA726, 0xFFE040FB, 0xFFB0BEC5, 0xFF000000];

/// [kColorPalette] plus fully transparent and half-transparent black, for
/// backgrounds where "no fill" is a valid choice.
const List<int> kColorPaletteWithTransparent = [...kColorPalette, 0x00000000, 0x80000000];

const int _transparent = 0x00000000;

/// Row showing the current ARGB colour, opening a swatch picker when tapped.
///
/// Colours come from the ambient [Theme], so the same tile works on a settings
/// page and inside the player's dark overlay.
class ColorPickerTile extends StatelessWidget {
  const ColorPickerTile({super.key, required this.title, required this.color, required this.onChanged, this.palette = kColorPalette});

  final String title;
  final int color;
  final ValueChanged<int> onChanged;
  final List<int> palette;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: _Swatch(color: color, size: 28, selected: false),
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: palette
                  .map(
                    (c) => GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(c),
                      child: _Swatch(color: c, size: 40, selected: c == color),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.size, required this.selected});

  final int color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(color),
        border: Border.all(color: selected ? theme.colorScheme.primary : theme.dividerColor, width: selected ? 3 : 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: color == _transparent ? Icon(Icons.block, size: size / 2) : null,
    );
  }
}
