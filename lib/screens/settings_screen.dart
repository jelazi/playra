import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../bloc/library/library_cubit.dart';
import '../bloc/settings/playra_settings_cubit.dart';
import '../models/player_settings.dart';
import '../models/subtitle_style_settings.dart';
import '../services/playra_storage.dart';
import 'library_management_screen.dart';
import 'servers_screen.dart';
import 'subtitle_manager_screen.dart';
import 'video_library_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<String> _defaultTrackLanguageOptions = ['', 'cs', 'en', 'sk', 'de', 'fr', 'es', 'it', 'ru', 'uk', 'ja'];

  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  String _doubleClickActionLabel(BuildContext context, String value) {
    switch (value) {
      case 'none':
        return 'settings.desktop_action_none'.tr();
      case 'fullscreen':
        return 'settings.desktop_action_fullscreen'.tr();
      case 'fit':
        return 'settings.desktop_action_fit'.tr();
      case 'toggleControls':
        return 'settings.desktop_action_toggle_controls'.tr();
      case 'seekBackward':
        return 'settings.desktop_action_seek_back'.tr();
      case 'seekForward':
        return 'settings.desktop_action_seek_forward'.tr();
      case 'volumeUp':
        return 'settings.desktop_action_volume_up'.tr();
      case 'volumeDown':
        return 'settings.desktop_action_volume_down'.tr();
      case 'brightnessUp':
        return 'settings.desktop_action_brightness_up'.tr();
      case 'brightnessDown':
        return 'settings.desktop_action_brightness_down'.tr();
      default:
        return value;
    }
  }

  String _wheelActionLabel(String value) {
    switch (value) {
      case 'none':
        return 'settings.desktop_action_none'.tr();
      case 'seek':
        return 'settings.desktop_wheel_seek'.tr();
      case 'volume':
        return 'settings.desktop_wheel_volume'.tr();
      case 'brightness':
        return 'settings.desktop_wheel_brightness'.tr();
      default:
        return value;
    }
  }

  String _trackLanguageLabel(String code) {
    switch (code) {
      case 'cs':
        return 'Čeština';
      case 'en':
        return 'English';
      case 'sk':
        return 'Slovenčina';
      case 'de':
        return 'Deutsch';
      case 'fr':
        return 'Français';
      case 'es':
        return 'Español';
      case 'it':
        return 'Italiano';
      case 'ru':
        return 'Русский';
      case 'uk':
        return 'Українська';
      case 'ja':
        return '日本語';
      default:
        return 'settings.default_track_language_none'.tr();
    }
  }

  String _formatShortcut(KeyEvent event) {
    final parts = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) parts.add('Ctrl');
    if (HardwareKeyboard.instance.isAltPressed) parts.add('Alt');
    if (HardwareKeyboard.instance.isShiftPressed) parts.add('Shift');
    if (HardwareKeyboard.instance.isMetaPressed) parts.add('Meta');

    final key = event.logicalKey;
    final label = key.keyLabel.trim();
    if (label.isNotEmpty && label.length <= 2) {
      parts.add(label.toUpperCase());
    } else {
      switch (key) {
        case LogicalKeyboardKey.space:
          parts.add('Space');
          break;
        case LogicalKeyboardKey.enter:
          parts.add('Enter');
          break;
        case LogicalKeyboardKey.arrowLeft:
          parts.add('Arrow Left');
          break;
        case LogicalKeyboardKey.arrowRight:
          parts.add('Arrow Right');
          break;
        case LogicalKeyboardKey.arrowUp:
          parts.add('Arrow Up');
          break;
        case LogicalKeyboardKey.arrowDown:
          parts.add('Arrow Down');
          break;
        default:
          final name = key.debugName ?? key.keyLabel;
          parts.add(name.replaceFirst('Logical Keyboard Key ', ''));
      }
    }
    return parts.join('+');
  }

  Future<String?> _captureShortcutDialog(BuildContext context, String title, {bool forDoubleClick = false}) async {
    final focusNode = FocusNode();
    String? captured;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(title),
          content: KeyboardListener(
            focusNode: focusNode,
            autofocus: true,
            onKeyEvent: (event) {
              if (event is KeyDownEvent) {
                final formatted = _formatShortcut(event);
                if (formatted.isNotEmpty) {
                  if (forDoubleClick) {
                    final mods = <String>[];
                    if (HardwareKeyboard.instance.isControlPressed) mods.add('Ctrl');
                    if (HardwareKeyboard.instance.isAltPressed) mods.add('Alt');
                    if (HardwareKeyboard.instance.isShiftPressed) mods.add('Shift');
                    if (HardwareKeyboard.instance.isMetaPressed) mods.add('Meta');
                    captured = mods.isEmpty ? 'Double Click' : '${mods.join('+')}+Double Click';
                  } else {
                    captured = formatted;
                  }
                  setStateDialog(() {});
                }
              }
            },
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(ctx).colorScheme.outline),
              ),
              child: Text(captured ?? 'settings.press_shortcut'.tr(), style: Theme.of(ctx).textTheme.titleMedium),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('common.cancel'.tr())),
            FilledButton(onPressed: captured == null ? null : () => Navigator.of(ctx).pop(captured), child: Text('common.save'.tr())),
          ],
        ),
      ),
    );

    focusNode.dispose();
    return result ?? captured;
  }

  Future<String?> _showTextInputDialog(BuildContext context, {required String title, required String initialValue, bool obscureText = false}) async {
    var currentValue = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          obscureText: obscureText,
          autofocus: true,
          decoration: InputDecoration(labelText: title),
          onChanged: (value) => currentValue = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('common.cancel'.tr())),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(currentValue.trim()), child: Text('common.save'.tr())),
        ],
      ),
    );
    return result;
  }

  Future<void> _showAppInfoDialog(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('settings.section_about'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${'settings.app_name'.tr()}: ${info.appName}'),
            Text('${'settings.app_version'.tr()}: ${info.version}+${info.buildNumber}'),
            Text('${'settings.app_build'.tr()}: ${info.buildNumber}'),
            Text('${'settings.app_package'.tr()}: ${info.packageName}'),
            Text('${'settings.app_copyright'.tr()}: © 2026 Playra'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              showLicensePage(context: context, applicationName: info.appName, applicationVersion: '${info.version}+${info.buildNumber}');
            },
            child: Text('settings.app_licenses'.tr()),
          ),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('common.ok'.tr())),
        ],
      ),
    );
  }

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
              _section(context, 'settings.section_player'.tr()),
              SwitchListTile(
                title: Text('settings.resume_playback'.tr()),
                subtitle: Text('settings.resume_playback_hint'.tr()),
                value: p.resumePlayback,
                onChanged: (v) => context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(resumePlayback: v)),
              ),
              SwitchListTile(
                title: Text('settings.gestures'.tr()),
                subtitle: Text(_isDesktop ? 'settings.gestures_desktop_forced_off'.tr() : 'settings.gestures_hint'.tr()),
                value: p.gesturesEnabled,
                onChanged: _isDesktop ? null : (v) => context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(gesturesEnabled: v)),
              ),
              ListTile(
                title: Text('settings.touch_seek_sensitivity'.tr()),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('settings.touch_seek_sensitivity_hint'.tr()),
                    Slider(
                      min: 0.5,
                      max: 12.0,
                      divisions: 23,
                      value: p.touchSeekSensitivity,
                      label: p.touchSeekSensitivity.toStringAsFixed(1),
                      onChanged: (v) => context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(touchSeekSensitivity: v)),
                    ),
                  ],
                ),
              ),
              ListTile(
                title: Text('settings.smb_cache_size'.tr()),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('settings.smb_cache_size_hint'.tr()),
                    Slider(
                      min: 16,
                      max: 512,
                      divisions: 31,
                      value: p.smbStreamCacheSizeMb.toDouble().clamp(16, 512),
                      label: '${p.smbStreamCacheSizeMb} MB',
                      onChanged: (v) {
                        final rounded = ((v / 16).round() * 16).clamp(16, 512);
                        context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(smbStreamCacheSizeMb: rounded));
                      },
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                title: Text('settings.keep_screen_on'.tr()),
                value: p.keepScreenOn,
                onChanged: (v) => context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(keepScreenOn: v)),
              ),
              ListTile(
                title: Text('settings.default_audio_language'.tr()),
                subtitle: Text('settings.default_audio_language_hint'.tr()),
                trailing: DropdownButton<String>(
                  value: p.defaultAudioLanguage,
                  items: _defaultTrackLanguageOptions.map((code) => DropdownMenuItem(value: code, child: Text(_trackLanguageLabel(code)))).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(defaultAudioLanguage: v));
                    }
                  },
                ),
              ),
              ListTile(
                title: Text('settings.default_subtitle_language'.tr()),
                subtitle: Text('settings.default_subtitle_language_hint'.tr()),
                trailing: DropdownButton<String>(
                  value: p.defaultSubtitleLanguage,
                  items: _defaultTrackLanguageOptions.map((code) => DropdownMenuItem(value: code, child: Text(_trackLanguageLabel(code)))).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(defaultSubtitleLanguage: v));
                    }
                  },
                ),
              ),
              ListTile(
                title: Text('settings.clear_all_resume'.tr()),
                trailing: const Icon(Icons.delete_sweep),
                onTap: () async {
                  await PlayraStorage.clearAllResume();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('settings.cleared'.tr())));
                  }
                },
              ),

              if (_isDesktop) ...[
                _sectionSeparator(),
                _section(context, 'settings.section_desktop_controls'.tr()),
                SwitchListTile(
                  title: Text('settings.desktop_shortcuts_enabled'.tr()),
                  value: p.desktopShortcutsEnabled,
                  onChanged: (v) => context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(desktopShortcutsEnabled: v)),
                ),
                ListTile(
                  title: Text('settings.desktop_key_play_pause'.tr()),
                  subtitle: Text(p.desktopPlayPauseShortcut),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final value = await _captureShortcutDialog(context, 'settings.desktop_key_play_pause'.tr());
                      if (value != null && context.mounted) {
                        context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(desktopPlayPauseShortcut: value));
                      }
                    },
                  ),
                ),
                ListTile(
                  title: Text('settings.desktop_key_fullscreen'.tr()),
                  subtitle: Text(p.desktopFullscreenShortcut),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final value = await _captureShortcutDialog(context, 'settings.desktop_key_fullscreen'.tr());
                      if (value != null && context.mounted) {
                        context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(desktopFullscreenShortcut: value));
                      }
                    },
                  ),
                ),
                ListTile(
                  title: Text('settings.desktop_key_seek_back'.tr()),
                  subtitle: Text(p.desktopSeekBackwardShortcut),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final value = await _captureShortcutDialog(context, 'settings.desktop_key_seek_back'.tr());
                      if (value != null && context.mounted) {
                        context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(desktopSeekBackwardShortcut: value));
                      }
                    },
                  ),
                ),
                ListTile(
                  title: Text('settings.desktop_key_seek_forward'.tr()),
                  subtitle: Text(p.desktopSeekForwardShortcut),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final value = await _captureShortcutDialog(context, 'settings.desktop_key_seek_forward'.tr());
                      if (value != null && context.mounted) {
                        context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(desktopSeekForwardShortcut: value));
                      }
                    },
                  ),
                ),
                ListTile(
                  title: Text('settings.desktop_double_click_shortcut'.tr()),
                  trailing: DropdownButton<String>(
                    value: p.desktopDoubleClickAction,
                    items: kDesktopDoubleClickActionOptions.map((a) => DropdownMenuItem(value: a, child: Text(_doubleClickActionLabel(context, a)))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(desktopDoubleClickAction: v));
                      }
                    },
                  ),
                ),
                ListTile(
                  title: Text('settings.desktop_wheel_action'.tr()),
                  trailing: DropdownButton<String>(
                    value: p.desktopWheelAction,
                    items: kDesktopWheelActionOptions.map((a) => DropdownMenuItem(value: a, child: Text(_wheelActionLabel(a)))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(desktopWheelAction: v));
                      }
                    },
                  ),
                ),
                ListTile(
                  title: Text('settings.desktop_wheel_step'.tr()),
                  subtitle: Slider(
                    min: 1,
                    max: 30,
                    divisions: 29,
                    value: p.desktopWheelStep,
                    label: p.desktopWheelStep.toStringAsFixed(0),
                    onChanged: (v) => context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(desktopWheelStep: v)),
                  ),
                ),
              ],

              _sectionSeparator(),
              _section(context, 'settings.section_subtitles'.tr()),
              ListTile(
                leading: const Icon(Icons.subtitles),
                title: Text('subtitle.search_title'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VideoLibraryScreen())),
              ),
              SwitchListTile(
                title: Text('settings.subtitles_enabled'.tr()),
                value: s.enabled,
                onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(enabled: v)),
              ),
              ListTile(
                title: Text('settings.subtitle_size'.tr()),
                subtitle: Slider(
                  min: 10,
                  max: 96,
                  divisions: 86,
                  value: s.fontSize,
                  label: s.fontSize.toStringAsFixed(0),
                  onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(fontSize: v)),
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
                  onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(outlineWidth: v)),
                ),
              ),
              SwitchListTile(
                title: Text('settings.subtitle_bold'.tr()),
                value: s.bold,
                onChanged: (v) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(bold: v)),
              ),
              ListTile(
                title: Text('settings.subtitle_font'.tr()),
                trailing: DropdownButton<String>(
                  value: s.fontFamily,
                  items: kAvailableSubtitleFonts.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(fontFamily: v));
                    }
                  },
                ),
              ),
              _colorTile(context, 'settings.subtitle_text_color'.tr(), s.textColor, (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(textColor: c))),
              _colorTile(
                context,
                'settings.subtitle_bg_color'.tr(),
                s.backgroundColor,
                (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(backgroundColor: c)),
                allowTransparent: true,
              ),
              _colorTile(context, 'settings.subtitle_outline_color'.tr(), s.outlineColor, (c) => context.read<PlayraSettingsCubit>().updateStyle(s.copyWith(outlineColor: c))),
              ListTile(
                leading: const Icon(Icons.cloud_download),
                title: Text('settings.subtitle_manager'.tr()),
                subtitle: Text('settings.subtitle_manager_hint'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubtitleManagerScreen())),
              ),

              _sectionSeparator(),
              _section(context, 'settings.section_library'.tr()),
              ListTile(
                leading: const Icon(Icons.create_new_folder),
                title: Text('settings.library_management_title'.tr()),
                subtitle: Text('settings.library_management_hint'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LibraryManagementScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text('settings.refresh_library'.tr()),
                subtitle: Text('settings.refresh_library_hint'.tr()),
                onTap: () => context.read<LibraryCubit>().refresh(),
              ),

              _sectionSeparator(),
              _section(context, 'home.servers'.tr()),
              ListTile(
                leading: const Icon(Icons.dns),
                title: Text('home.servers'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServersScreen())),
              ),

              _sectionSeparator(),
              _section(context, 'settings.section_sync'.tr()),
              ListTile(
                title: Text('settings.sync_username'.tr()),
                subtitle: Text(p.syncUsername.isEmpty ? 'settings.sync_not_configured'.tr() : p.syncUsername),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final value = await _showTextInputDialog(context, title: 'settings.sync_username'.tr(), initialValue: p.syncUsername);
                  if (value != null && context.mounted) {
                    context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(syncUsername: value));
                  }
                },
              ),
              ListTile(
                title: Text('settings.sync_password'.tr()),
                subtitle: Text(p.syncPassword.isEmpty ? 'settings.sync_not_configured'.tr() : '••••••••'),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final value = await _showTextInputDialog(context, title: 'settings.sync_password'.tr(), initialValue: p.syncPassword, obscureText: true);
                  if (value != null && context.mounted) {
                    context.read<PlayraSettingsCubit>().updatePlayer(p.copyWith(syncPassword: value));
                  }
                },
              ),
              ListTile(leading: const Icon(Icons.sync), title: Text('settings.sync_hint'.tr())),

              _sectionSeparator(),
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

              _sectionSeparator(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text('settings.section_about'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAppInfoDialog(context),
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
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.2, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _sectionSeparator() {
    return const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 0), child: Divider(height: 1, thickness: 1));
  }

  Widget _colorTile(BuildContext context, String title, int currentColor, ValueChanged<int> onChanged, {bool allowTransparent = false}) {
    final palette = <int>[0xFFFFFFFF, 0xFFFFEB3B, 0xFFFF5252, 0xFF40C4FF, 0xFF69F0AE, 0xFFFFA726, 0xFFE040FB, 0xFFB0BEC5, 0xFF000000, if (allowTransparent) 0x00000000, 0x80000000];
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
                  .map(
                    (c) => GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c),
                          border: Border.all(color: c == currentColor ? Colors.blue : Colors.grey, width: c == currentColor ? 3 : 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: c == 0x00000000 ? const Icon(Icons.block, size: 20) : null,
                      ),
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
