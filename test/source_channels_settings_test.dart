import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/screens/redesign/settings_source_channels_screen.dart';

void main() {
  const channel = MethodChannel('livebridge/platform');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final writes = <Map>[];
  bool failSave = false;

  setUp(() {
    failSave = false;
    writes.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'getSourceChannels') {
        return jsonEncode([
          {
            'packageName': 'app.first',
            'channelId': 'ads',
            'name': 'Offers',
            'appLabel': 'First',
            'enabled': true,
          },
          {
            'packageName': 'app.first',
            'channelId': 'chat',
            'name': 'Messages',
            'appLabel': 'First',
            'enabled': true,
          },
          {
            'packageName': 'app.second',
            'channelId': 'ads',
            'name': 'Offers',
            'appLabel': 'Second',
            'enabled': false,
          },
        ]);
      }
      if (call.method == 'setSourceChannelEnabled') {
        writes.add(call.arguments as Map);
        if (failSave) throw PlatformException(code: 'failed');
        return true;
      }
      return false;
    });
  });

  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'channel exclusion targets one app and channel without changing siblings',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SettingsSourceChannelsScreen()),
      );
      await tester.pumpAndSettle();
      tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .first
          .onChanged!(false);
      await tester.pumpAndSettle();
      expect(writes.single, {
        'packageName': 'app.first',
        'channelId': 'ads',
        'enabled': false,
      });
      expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .map((w) => w.value)
            .toList(),
        [false, true, false],
      );
    },
  );

  testWidgets('failed save keeps channel enabled and displays an error', (
    tester,
  ) async {
    failSave = true;
    await tester.pumpWidget(
      const MaterialApp(home: SettingsSourceChannelsScreen()),
    );
    await tester.pumpAndSettle();
    tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .first
        .onChanged!(false);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .first
          .value,
      isTrue,
    );
    expect(
      find.text('Could not load or save channels. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
