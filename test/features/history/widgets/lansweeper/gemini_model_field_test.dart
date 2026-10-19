// Πεδία κύριου/εφεδρικού μοντέλου Gemini: η ερώτηση «Ίδιο μοντέλο» γίνεται
// όταν τελειώσει το πεδίο, όχι στη μέση της πληκτρολόγησης.
//
//   flutter test test/features/history/widgets/lansweeper/gemini_model_field_test.dart

import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:call_logger/features/history/providers/gemini_settings_provider.dart';
import 'package:call_logger/features/history/widgets/lansweeper/gemini_model_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoCache extends GeminiModelsProbeCacheNotifier {
  @override
  GeminiModelsProbeCache? build() => null;
}

Future<({TextEditingController primary, TextEditingController fallback})> _pump(
  WidgetTester tester,
) async {
  final primary = TextEditingController(text: 'gemini-2.5-flash');
  final fallback = TextEditingController();
  final apiKey = TextEditingController();
  addTearDown(() {
    primary.dispose();
    fallback.dispose();
    apiKey.dispose();
  });
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [geminiModelsProbeCacheProvider.overrideWith(_NoCache.new)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GeminiModelsSection(
              primaryModelController: primary,
              fallbackModelController: fallback,
              apiKeyController: apiKey,
              onChanged: () {},
            ),
          ),
        ),
      ),
    ),
  );
  return (primary: primary, fallback: fallback);
}

Finder get _fallbackField => find.byType(TextFormField).at(1);

Finder get _duplicateDialog => find.widgetWithText(AlertDialog, 'Ίδιο μοντέλο');

void main() {
  testWidgets(
    'το «gemini-2.5-flash-lite» γράφεται γράμμα-γράμμα χωρίς ερώτηση στη μέση',
    (tester) async {
      final c = await _pump(tester);
      const target = 'gemini-2.5-flash-lite';
      for (var i = 1; i <= target.length; i++) {
        await tester.enterText(_fallbackField, target.substring(0, i));
        await tester.pump();
        expect(
          _duplicateDialog,
          findsNothing,
          reason: 'στο «${target.substring(0, i)}»',
        );
      }
      expect(c.fallback.text, target);
    },
  );

  testWidgets('ίδιο μοντέλο και Enter: η ερώτηση εμφανίζεται', (tester) async {
    await _pump(tester);
    await tester.enterText(_fallbackField, 'gemini-2.5-flash');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_duplicateDialog, findsOneWidget);
  });

  testWidgets('ίδιο μοντέλο και Άκυρο: το πεδίο γυρίζει όπως ήταν', (
    tester,
  ) async {
    final c = await _pump(tester);
    await tester.enterText(_fallbackField, 'gemini-2.5-flash');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Άκυρο'));
    await tester.pumpAndSettle();
    expect(c.fallback.text, '');
    expect(c.primary.text, 'gemini-2.5-flash');
  });

  testWidgets('ίδιο μοντέλο και έξοδος από το πεδίο: η ερώτηση εμφανίζεται', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(_fallbackField, 'gemini-2.5-flash');
    await tester.tap(find.byType(TextFormField).at(0));
    await tester.pumpAndSettle();
    expect(_duplicateDialog, findsOneWidget);
  });
}
