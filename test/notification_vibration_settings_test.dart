import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/screens/redesign/settings_app_config_screen.dart';
import 'package:livebridge/widgets/redesign/lb_list_component.dart';

void main() {
  const channel = MethodChannel('livebridge/platform');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  bool vibrationEnabled = false;
  final writes = <bool>[];

  setUp(() {
    vibrationEnabled = false;
    writes.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'getConvertedNotificationVibrationEnabled':
          return vibrationEnabled;
        case 'setConvertedNotificationVibrationEnabled':
          vibrationEnabled = (call.arguments as Map)['value'] as bool;
          writes.add(vibrationEnabled);
          return true;
        case 'getConversionLogMaxBytes':
          return 5 * 1024 * 1024;
        case 'getAppLanguageTag':
          return 'system';
        default:
          return false;
      }
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  LbListItemData vibrationItem(WidgetTester tester) => tester
      .widgetList<LbListComponent>(find.byType(LbListComponent))
      .expand((list) => list.items)
      .singleWhere((item) => item.title == 'Converted notification vibration');

  testWidgets(
    'vibration defaults off and can be enabled and disabled independently',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SettingsAppConfigScreen()),
      );
      await tester.pumpAndSettle();
      expect(vibrationItem(tester).toggleValue, isFalse);
      vibrationItem(tester).onToggle!(true);
      await tester.pumpAndSettle();
      expect(vibrationItem(tester).toggleValue, isTrue);
      vibrationItem(tester).onToggle!(false);
      await tester.pumpAndSettle();
      expect(vibrationItem(tester).toggleValue, isFalse);
      expect(writes, [true, false]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved vibration setting is loaded when reopening settings', (
    tester,
  ) async {
    vibrationEnabled = true;
    await tester.pumpWidget(const MaterialApp(home: SettingsAppConfigScreen()));
    await tester.pumpAndSettle();
    expect(vibrationItem(tester).toggleValue, isTrue);
    expect(writes, isEmpty);
  });
}
