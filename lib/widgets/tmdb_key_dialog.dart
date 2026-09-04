import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/secret_store.dart';
import '../../services/tmdb_service.dart';

/// Asks for the TMDB API key and stores it in the encrypted secret box.
///
/// Returns true when a key was saved or removed. The stored key is never put
/// back into the field — the dialog only reports whether one exists.
Future<bool> showTmdbKeyDialog(BuildContext context) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _TmdbKeyDialog(),
  );
  return saved ?? false;
}

class _TmdbKeyDialog extends StatefulWidget {
  const _TmdbKeyDialog();

  @override
  State<_TmdbKeyDialog> createState() => _TmdbKeyDialogState();
}

class _TmdbKeyDialogState extends State<_TmdbKeyDialog> {
  final _controller = TextEditingController();
  final _tmdb = TmdbService();

  bool _obscured = true;
  bool _verifying = false;
  String? _error;

  bool get _hasStoredKey => SecretStore.tmdbApiKey.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'settings.tmdb_key_invalid_format'.tr());
      return;
    }
    if (!TmdbService.isWellFormedKey(key)) {
      setState(() => _error = 'settings.tmdb_key_invalid_format'.tr());
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    final accepted = await _tmdb.verifyKey(key);
    if (!mounted) return;

    if (!accepted) {
      setState(() {
        _verifying = false;
        _error = 'settings.tmdb_key_rejected'.tr();
      });
      return;
    }

    await SecretStore.setTmdbApiKey(key);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _remove() async {
    await SecretStore.setTmdbApiKey('');
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('settings.tmdb_key'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('settings.tmdb_key_hint'.tr()),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_verifying,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 32,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]'))],
            decoration: InputDecoration(
              labelText: 'settings.tmdb_key'.tr(),
              hintText: _hasStoredKey ? 'settings.tmdb_key_stored'.tr() : null,
              errorText: _error,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscured ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
            onSubmitted: (_) => _verifying ? null : _save(),
          ),
          if (_verifying)
            Row(
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Text('settings.tmdb_key_verifying'.tr()),
              ],
            ),
        ],
      ),
      actions: [
        if (_hasStoredKey)
          TextButton(
            onPressed: _verifying ? null : _remove,
            child: Text('settings.tmdb_key_remove'.tr(), style: const TextStyle(color: Colors.red)),
          ),
        TextButton(onPressed: _verifying ? null : () => Navigator.of(context).pop(false), child: Text('common.cancel'.tr())),
        FilledButton(onPressed: _verifying ? null : _save, child: Text('common.save'.tr())),
      ],
    );
  }
}
