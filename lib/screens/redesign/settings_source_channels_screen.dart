import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../platform/livebridge_platform.dart';

class SettingsSourceChannelsScreen extends StatefulWidget {
  const SettingsSourceChannelsScreen({super.key});

  @override
  State<SettingsSourceChannelsScreen> createState() =>
      _SettingsSourceChannelsScreenState();
}

class _SettingsSourceChannelsScreenState
    extends State<SettingsSourceChannelsScreen> {
  List<Map<String, dynamic>> _channels = [];
  final Set<String> _saving = {};
  String _query = '';
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final raw = await LiveBridgePlatform.getSourceChannels();
      final values = (jsonDecode(raw) as List)
          .cast<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
      if (mounted) setState(() => _channels = values);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(Map<String, dynamic> item, bool enabled) async {
    final key = jsonEncode([item['packageName'], item['channelId']]);
    setState(() => _saving.add(key));
    try {
      final saved = await LiveBridgePlatform.setSourceChannelEnabled(
        item['packageName'] as String,
        item['channelId'] as String,
        enabled,
      );
      if (!saved) throw StateError('Save failed');
      if (mounted) setState(() => item['enabled'] = enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).sourceChannelsError)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final rows = _channels
        .where(
          (v) =>
              '${v['appLabel']} ${v['packageName']} ${v['name']} ${v['channelId']}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.sourceChannelsTitle),
        actions: [
          IconButton(
            tooltip: s.sourceChannelsRefresh,
            onPressed: _loading || _saving.isNotEmpty ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(s.sourceChannelsDescription),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                labelText: s.sourceChannelsSearch,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                ? Center(child: Text(s.sourceChannelsError))
                : _channels.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(s.sourceChannelsEmpty),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final item = rows[index];
                      final key = jsonEncode([
                        item['packageName'],
                        item['channelId'],
                      ]);
                      return SwitchListTile(
                        title: Text(
                          '${item['appLabel'] ?? item['packageName']} · ${item['name']}',
                        ),
                        subtitle: Text(
                          '${item['packageName']}\n${item['channelId']}',
                        ),
                        isThreeLine: true,
                        value: item['enabled'] == true,
                        onChanged: _saving.contains(key)
                            ? null
                            : (value) => _setEnabled(item, value),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
