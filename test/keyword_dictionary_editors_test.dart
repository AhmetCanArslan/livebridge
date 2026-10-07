import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/screens/redesign/dictionary_word_editor_screen.dart';
import 'package:livebridge/screens/redesign/editor_word_lists.dart';
import 'package:livebridge/screens/redesign/settings_text_filters_screen.dart';

void main() {
  const channel = MethodChannel('livebridge/platform');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> filters;
  late Map<String, dynamic> additions;
  bool failSave = false;
  int wordWrites = 0;

  setUp(() {
    filters = {
      '*': {
        'allow': [],
        'deny': ['ads'],
        'all': false,
      },
      'app.one': {
        'allow': ['Order'],
        'deny': [],
        'all': false,
      },
    };
    additions = {
      'otp_strong_triggers': ['secret code'],
      'food_words': ['meal'],
    };
    failSave = false;
    wordWrites = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'getNotificationTextFilters':
          return jsonEncode(filters);
        case 'getSourceChannels':
          return '[]';
        case 'getInstalledApps':
          return [
            {'packageName': 'app.one', 'label': 'First'},
          ];
        case 'setNotificationTextFilters':
          if (failSave) return false;
          filters = Map<String, dynamic>.from(
            jsonDecode((call.arguments as Map)['value'] as String) as Map,
          );
          return true;
        case 'getDictionaryWordAdditions':
          return jsonEncode(additions);
        case 'setDictionaryWordAdditions':
          wordWrites++;
          if (failSave) return false;
          additions = Map<String, dynamic>.from(
            jsonDecode((call.arguments as Map)['value'] as String) as Map,
          );
          return true;
        default:
          return false;
      }
    });
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  test(
    'word lists trim, ignore blank lines, deduplicate and enforce limits',
    () {
      expect(editorWords(' order\n\nready\norder '), ['order', 'ready']);
      expect(validEditorWords(List.generate(101, (i) => '$i')), isFalse);
      expect(validEditorWords(['x' * 201]), isFalse);
    },
  );

  testWidgets('global draft survives switching to per-app filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsTextFiltersScreen()),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('denyWords')),
      'ads\npromo',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('allowWords')))
          .controller!
          .text,
      'Order',
    );
    await tester.enterText(
      find.byKey(const ValueKey('allowWords')),
      'order\nready',
    );
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(filters['*']['deny'], ['ads', 'promo']);
    expect(filters['app.one']['allow'], ['order', 'ready']);
    expect(filters['app.one']['all'], true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'word editor saves personal words without a JSON editor or touching other settings',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DictionaryWordEditorScreen()),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('otp_strong_triggers')),
            )
            .controller!
            .text,
        'secret code',
      );
      await tester.enterText(
        find.byKey(const ValueKey('otp_strong_triggers')),
        'secret code\nlogin token',
      );
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(additions['otp_strong_triggers'], ['secret code', 'login token']);
      expect(additions['food_words'], ['meal']);
      expect(filters['app.one']['allow'], ['Order']);
      expect(wordWrites, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed dictionary save reports an error and preserves stored additions',
    (tester) async {
      failSave = true;
      await tester.pumpWidget(
        const MaterialApp(home: DictionaryWordEditorScreen()),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('otp_strong_triggers')),
        'new term',
      );
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(additions['otp_strong_triggers'], ['secret code']);
      expect(
        find.text('Could not save the setting. Please try again.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('custom island template is saved without adding filter words', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsTextFiltersScreen()),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('textTemplate')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('textTemplate')),
      '{app}: {title}',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(filters['*']['template'], '{app}: {title}');
    expect(filters['*']['deny'], ['ads']);
    expect(filters['app.one']['allow'], ['Order']);
    expect(tester.takeException(), isNull);
  });
}
