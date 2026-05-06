import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/library/library_cubit.dart';
import '../bloc/settings/playra_settings_cubit.dart';
import '../models/subtitle_style_settings.dart';
import '../services/playra_storage.dart';
import 'subtitle_manager_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr())),
      body: BlocBuilder<PlayraSettingsCubit, PlayraSettingsState>(
        builder: (context, state) {
          final p = state.player;
          final s = state.subtitleStyle;
          return ListView(
            children: [
              _section(context, 'settings.section_general'.tr()),
              ListTile(
                title: Text('settings.language'.tr()),
                trailing: DropdownButton<String>(
                  value: context.locale.languageCode,
                  items: const [
                    DropdownMenuItem(value: 'cs', child: Text('Čeština')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (v) {
                    if (v != null) context.setLocale(Locale(v));
                  },
                ),
              ),

              _section(context, 'settings.section_player'.tr()),
              SwitchListTile(
                title: Text('settings.resume_playback'.tr()),
                subtitle: Text('settings.resume_playback_hint'.tr()),
                value: p.resumePlayback,
                onChanged: (v) =>
                    context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(resumePlayback: v)),
              ),
              SwitchListTile(
                title: Text('settings.gestures'.tr()),
                subtitle: Text('settings.gestures_hint'.tr()),
                value: p.gesturesEnabled,
                onChanged: (v) =>
                    context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(gesturesEnabled: v)),
              ),
              SwitchListTile(
                title: Text('settings.keep_screen_on'.tr()),
                value: p.keepScreenOn,
                onChanged: (v) =>
                    context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(keepScreenOn: v)),
              ),
              ListTile(
                title: Text('settings.clear_all_resume'.tr()),
                trailing: const Icon(Icons.delete_sweep),
                onTap: () async {
                  await PlayraStorage.clearAllResume();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('settings.cleared'.tr())),
                    );
                  }
                },
              ),

              _section(context, 'settings.section_library'.tr()),
              ...p.libraryFolders.map((f) => ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => context.read<LibraryCubit>().removeFolder(f),
                    ),
                  )),
              if (p.libraryFolders.isEmpty)
                ListTile(title: Text('settings.no_folders'.tr())),

              _section(context, 'settings.section_subtitles'.tr()),
              SwitchListTile(
                title: Text('settings.subtitles_enabled'.tr()),
                value: s.enabled,
                onChanged: (v) =>
                    context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(enabled: v)),
              ),
              ListTile(
                title: Text('settings.subtitle_size'.tr()),
                subtitle: Slider(
                  min: 10,
                  max: 48,
                  divisions: 38,
                  value: s.fontSize,
                  label: s.fontSize.toStringAsFixed(0),
                  onChanged: (v) =>
                      context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(fontSize: v)),
                ),
              ),
              ListTile(
                title: Text('settings.subtitle_outline'.tr()),
                subtitle: Slider(
                  min: 0,
                  max: 5,
                  divisions: 10,
                  value: s.outlineWidth,
                  label: s.outlineWidth.toStringAsFixed(1),
                  onChanged: (v) =>
                      context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(outlineWidth: v)),
                ),
              ),
              SwitchListTile(
                title: Text('settings.subtitle_bold'.tr()),
                value: s.bold,
                onChanged: (v) =>
                    context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(bold: v)),
              ),
              ListTile(
                title: Text('settings.subtitle_font'.tr()),
                trailing: DropdownButton<String>(
                  value: s.fontFamily,
                  items: kAvailableSubtitleFonts
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(fontFamily: v));
                    }
                  },
                ),
              ),
              _colorTile(context, 'settings.subtitle_text_color'.tr(), s.textColor,
                  (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(textColor: c))),
              _colorTile(context, 'settings.subtitle_bg_color'.tr(), s.backgroundColor,
                  (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(backgroundColor: c)),
                  allowTransparent: true),
              _colorTile(context, 'settings.subtitle_outline_color'.tr(), s.outlineColor,
                  (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(outlineColor: c))),

              ListTile(
                leading: const Icon(Icons.cloud_download),
                title: Text('settings.subtitle_manager'.tr()),
                subtitle: Text('settings.subtitle_manager_hint'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubtitleManagerScreen()),
                ),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _colorTile(BuildContext context, String title, int currentColor, ValueChanged<int> onChanged,
      {bool allowTransparent = false}) {
    final palette = <int>[
      0xFFFFFFFF, 0xFFFFEB3B, 0xFFFF5252, 0xFF40C4FF, 0xFF69F0AE, 0xFFFFA726,
      0xFFE040FB, 0xFFB0BEC5, 0xFF000000,
      if (allowTransparent) 0x00000000, 0x80000000,
    ];
    return ListTile(
      title: Text(title),
      trailing: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Color(currentColor),
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: palette
                  .map((c) => GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(c),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Color(c),
                            border: Border.all(
                              color: c == currentColor ? Colors.blue : Colors.grey,
                              width: c == currentColor ? 3 : 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: c == 0x00000000
                              ? const Icon(Icons.block, size: 20)
                              : null,
                        ),
                      ))
                  .toList(),
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
