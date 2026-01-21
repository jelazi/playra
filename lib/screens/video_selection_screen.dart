import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;

import '../bloc/subtitle/subtitle_bloc.dart';
import '../bloc/subtitle/subtitle_event.dart';
import '../bloc/subtitle/subtitle_state.dart';
import '../models/video_info.dart';
import '../services/settings_service.dart';
import 'subtitle_search_screen.dart';

class VideoSelectionScreen extends StatelessWidget {
  final bool isDialog;

  const VideoSelectionScreen({super.key, this.isDialog = false});

  @override
  Widget build(BuildContext context) {
    final content = BlocListener<SubtitleBloc, SubtitleState>(
      listener: (context, state) async {
        if (state is SubtitleLoginFailed) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: Colors.red));
        } else if (state is SubtitleLoggedIn) {
          // Uložit username do Hive po úspěšném přihlášení
          await SettingsService.updateUsername(state.username);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('auth.login_success'.tr()), backgroundColor: Colors.green));
            // Pokud je to dialog, zavřít ho
            if (isDialog) {
              Navigator.of(context).pop();
            }
          }
        }
      },
      child: BlocBuilder<SubtitleBloc, SubtitleState>(
        builder: (context, state) {
          if (state is SubtitleInitial) {
            return _buildLoginForm(context);
          } else if (state is SubtitleLoggingIn) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is SubtitleLoggedIn || state is SubtitleSearching || state is SubtitleSearchResults) {
            return isDialog ? _buildLoginForm(context) : _buildVideoSelection(context);
          }
          return _buildLoginForm(context);
        },
      ),
    );

    if (isDialog) {
      return Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(title: Text('auth.login_title'.tr()), automaticallyImplyLeading: false),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('video.select_title'.tr()), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: content,
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    // Načíst uložené username z Hive
    final settings = SettingsService.getSettings();
    final usernameController = TextEditingController(text: settings.username ?? '');
    final passwordController = TextEditingController();

    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'auth.login_title'.tr(),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: usernameController,
                    decoration: InputDecoration(labelText: 'auth.username'.tr(), border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.person)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(labelText: 'auth.password'.tr(), border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.lock)),
                    onSubmitted: (_) {
                      _handleLogin(context, usernameController.text, passwordController.text);
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      _handleLogin(context, usernameController.text, passwordController.text);
                    },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Text('auth.login_button'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSelection(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.video_library, size: 64, color: Colors.blue),
                const SizedBox(height: 24),
                Text(
                  'video.select_video'.tr(),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'video.select_video_description'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => _selectVideoFile(context),
                  icon: const Icon(Icons.folder_open),
                  label: Text('video.select_button'.tr()),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    context.read<SubtitleBloc>().add(LogoutFromTitulky());
                  },
                  icon: const Icon(Icons.logout),
                  label: Text('auth.logout_button'.tr()),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleLogin(BuildContext context, String username, String password) {
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('auth.fill_all_fields'.tr()), backgroundColor: Colors.orange));
      return;
    }

    context.read<SubtitleBloc>().add(LoginToTitulky(username, password));
  }

  Future<void> _selectVideoFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg', '3gp'],
      dialogTitle: 'Vyberte video soubor',
    );

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      final fileName = path.basename(filePath);
      final fileDir = path.dirname(filePath);

      final videoInfo = VideoInfo(path: filePath, name: fileName, directory: fileDir);

      if (context.mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => SubtitleSearchScreen(videoInfo: videoInfo)));
      }
    }
  }
}
