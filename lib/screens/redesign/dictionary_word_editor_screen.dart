import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../platform/livebridge_platform.dart';
import 'editor_word_lists.dart';

class DictionaryWordEditorScreen extends StatefulWidget {
  const DictionaryWordEditorScreen({super.key});
  @override
  State<DictionaryWordEditorScreen> createState() =>
      _DictionaryWordEditorScreenState();
}

class _DictionaryWordEditorScreenState
    extends State<DictionaryWordEditorScreen> {
  static const fields = [
    'otp_strong_triggers',
    'progress_words',
    'weather_words',
    'weather_package_hints',
    'known_navigation_packages',
    'navigation_package_markers',
    'vpn_package_markers',
    'order_context_hints',
    'food_words',
    'food_packages',
    'taxi_words',
    'taxi_packages',
  ];
  final _controllers = {for (final key in fields) key: TextEditingController()};
  bool _loading = true;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await LiveBridgePlatform.getDictionaryWordAdditions();
      final data = jsonDecode(raw) as Map;
      if (!mounted) return;
      for (final key in fields) {
        _controllers[key]!.text = ((data[key] as List?) ?? []).join('\n');
      }
    } catch (_) {
      if (mounted) _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final words = {
      for (final key in fields) key: editorWords(_controllers[key]!.text),
    };
    final s = AppStrings.of(context);
    if (!words.values.every(validEditorWords)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.editorLimit)));
      return;
    }
    setState(() => _saving = true);
    try {
      if (!await LiveBridgePlatform.setDictionaryWordAdditions(
        jsonEncode(words),
      )) {
        throw StateError('save failed');
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.appPresentationSaved)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.settingsSaveError)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.dictionaryEditorTitle)),
      bottomNavigationBar: _loading || _failed
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(s.save),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(child: Text(s.dictionaryUpdateFailed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(s.wordEditorHelp),
                const SizedBox(height: 16),
                for (final key in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      key: ValueKey(key),
                      controller: _controllers[key],
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: s.dictionaryWordField(key),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () {
                          for (final c in _controllers.values) {
                            c.clear();
                          }
                        },
                  child: Text(s.editorClear),
                ),
              ],
            ),
    );
  }
}
