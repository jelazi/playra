import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/subtitle_style_settings.dart';
import 'color_picker_tile.dart';

/// The subtitle appearance controls, shared by the settings page and the
/// player's options sheet.
///
/// Every colour is taken from the ambient [Theme], so the caller decides how it
/// looks: the settings page uses the app theme, the player wraps this in a dark
/// one. That keeps a single copy of the controls instead of one per surface.
class SubtitleStyleControls extends StatelessWidget {
  const SubtitleStyleControls({
    super.key,
    required this.style,
    required this.onChanged,
    this.showEnabledSwitch = true,
    this.showBottomPadding = false,
    this.leading = const [],
    this.trailing = const [],
  });

  final SubtitleStyleSettings style;
  final ValueChanged<SubtitleStyleSettings> onChanged;

  /// The player hides this because the track list above already governs it.
  final bool showEnabledSwitch;

  /// Only the player offers this — it is a per-viewing tweak, not a preference.
  final bool showBottomPadding;

  /// Extra rows inserted after the enabled switch and at the very end, for
  /// controls that only one surface has (subtitle delay, subtitle manager).
  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEnabledSwitch)
          SwitchListTile(
            title: Text('settings.subtitles_enabled'.tr()),
            value: style.enabled,
            onChanged: (v) => onChanged(style.copyWith(enabled: v)),
          ),
        ...leading,
        _SliderTile(
          title: 'settings.subtitle_size'.tr(),
          value: style.fontSize,
          min: 10,
          max: 96,
          divisions: 86,
          label: style.fontSize.toStringAsFixed(0),
          onChanged: (v) => onChanged(style.copyWith(fontSize: v)),
        ),
        if (showBottomPadding)
          _SliderTile(
            title: 'settings.subtitle_bottom_padding'.tr(),
            hint: 'settings.subtitle_bottom_padding_hint'.tr(),
            value: style.bottomPadding.clamp(8, 160),
            min: 8,
            max: 160,
            divisions: 76,
            label: style.bottomPadding.toStringAsFixed(0),
            onChanged: (v) => onChanged(style.copyWith(bottomPadding: v)),
          ),
        _SliderTile(
          title: 'settings.subtitle_outline'.tr(),
          value: style.outlineWidth,
          min: 0,
          max: 5,
          divisions: 10,
          label: style.outlineWidth.toStringAsFixed(1),
          onChanged: (v) => onChanged(style.copyWith(outlineWidth: v)),
        ),
        SwitchListTile(
          title: Text('settings.subtitle_bold'.tr()),
          value: style.bold,
          onChanged: (v) => onChanged(style.copyWith(bold: v)),
        ),
        ListTile(
          title: Text('settings.subtitle_font'.tr()),
          trailing: DropdownButton<String>(
            value: style.fontFamily,
            items: kAvailableSubtitleFonts.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
            onChanged: (v) {
              if (v != null) onChanged(style.copyWith(fontFamily: v));
            },
          ),
        ),
        ColorPickerTile(
          title: 'settings.subtitle_text_color'.tr(),
          color: style.textColor,
          onChanged: (c) => onChanged(style.copyWith(textColor: c)),
        ),
        ColorPickerTile(
          title: 'settings.subtitle_bg_color'.tr(),
          color: style.backgroundColor,
          palette: kColorPaletteWithTransparent,
          onChanged: (c) => onChanged(style.copyWith(backgroundColor: c)),
        ),
        ColorPickerTile(
          title: 'settings.subtitle_outline_color'.tr(),
          color: style.outlineColor,
          onChanged: (c) => onChanged(style.copyWith(outlineColor: c)),
        ),
        ...trailing,
      ],
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    this.hint,
  });

  final String title;
  final String? hint;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final slider = Slider(min: min, max: max, divisions: divisions, value: value, label: label, onChanged: onChanged);
    return ListTile(
      title: Text(title),
      subtitle: hint == null
          ? slider
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hint!, style: Theme.of(context).textTheme.bodySmall),
                slider,
              ],
            ),
    );
  }
}
