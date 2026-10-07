import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/app_models.dart';
import '../../platform/livebridge_platform.dart';
import 'editor_word_lists.dart';

class SettingsTextFiltersScreen extends StatefulWidget {
  const SettingsTextFiltersScreen({super.key});
  @override
  State<SettingsTextFiltersScreen> createState() =>
      _SettingsTextFiltersScreenState();
}

class _SettingsTextFiltersScreenState extends State<SettingsTextFiltersScreen> {
  final _allow = TextEditingController();
  final _deny = TextEditingController();
  final _template = TextEditingController();
  Map<String, dynamic> _rules = {};
  Map<String, String> _apps = {};
  String _scope = '*';
  bool _all = false;
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final filters = LiveBridgePlatform.getNotificationTextFilters();
      final apps = LiveBridgePlatform.getInstalledApps().catchError(
        (_) => <InstalledApp>[],
      );
      final observedFuture = LiveBridgePlatform.getSourceChannels().catchError(
        (_) => "[]",
      );
      final rules = Map<String, dynamic>.from(jsonDecode(await filters) as Map);
      final installed = await apps;
      final observed = jsonDecode(await observedFuture) as List;
      if (!mounted) return;
      _rules = rules;
      _apps = {for (final app in installed) app.packageName: app.label};
      for (final item in observed) {
        _apps.putIfAbsent(
          item['packageName'] as String,
          () => (item['appLabel'] ?? item['packageName']) as String,
        );
      }
      for (final pkg in rules.keys.where((v) => v != '*')) {
        _apps.putIfAbsent(pkg, () => pkg);
      }
      _readScope();
    } catch (_) {
      if (mounted) _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _readScope() {
    final rule = _rules[_scope] as Map? ?? {};
    _allow.text = ((rule['allow'] as List?) ?? []).join('\n');
    _deny.text = ((rule['deny'] as List?) ?? []).join('\n');
    _all = rule['all'] == true;
    _template.text = rule['template'] as String? ?? '';
  }

  void _stash() {
    final allow = editorWords(_allow.text);
    final deny = editorWords(_deny.text);
    if (allow.isEmpty && deny.isEmpty && _template.text.trim().isEmpty) {
      _rules.remove(_scope);
    } else {
      _rules[_scope] = {
        'allow': allow,
        'deny': deny,
        'all': _all,
        'template': _template.text.trim(),
      };
    }
  }

  Future<void> _save() async {
    _stash();
    final s = AppStrings.of(context);
    if (_rules.values.any(
      (v) =>
          !validEditorWords(((v['allow'] as List?) ?? []).cast<String>()) ||
          !validEditorWords(((v['deny'] as List?) ?? []).cast<String>()) ||
          ((v['template'] as String?)?.length ?? 0) > 200,
    )) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.editorLimit)));
      return;
    }
    setState(() => _saving = true);
    try {
      if (!await LiveBridgePlatform.setNotificationTextFilters(
        jsonEncode(_rules),
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
    _allow.dispose();
    _deny.dispose();
    _template.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final apps = _apps.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Scaffold(
      appBar: AppBar(title: Text(s.textFiltersTitle)),
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
          ? Center(child: Text(s.settingsSaveError))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(s.filterHelp),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _scope,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(value: '*', child: Text(s.filterAllApps)),
                    for (final app in apps)
                      DropdownMenuItem(
                        value: app.key,
                        child: Text(app.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          _stash();
                          setState(() {
                            _scope = value;
                            _readScope();
                          });
                        },
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('allowWords'),
                  controller: _allow,
                  enabled: !_saving,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: s.filterAllowWords,
                    border: const OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  title: Text(s.filterMatchAll),
                  value: _all,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _all = value),
                ),
                TextField(
                  key: const ValueKey('denyWords'),
                  controller: _deny,
                  enabled: !_saving,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: s.filterDenyWords,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('textTemplate'),
                  controller: _template,
                  enabled: !_saving,
                  maxLength: 200,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: s.filterTemplateTitle,
                    border: const OutlineInputBorder(),
                  ),
                ),
                Text(s.filterTemplateHelp),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}
