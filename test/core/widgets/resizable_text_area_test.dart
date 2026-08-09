// Widget test: το πολύγραμμο πεδίο που μεγαλώνει μόνο του και σέρνεται.
//
//   flutter test test/core/widgets/resizable_text_area_test.dart

import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/core/widgets/lexicon_spell_text_form_field.dart';
import 'package:call_logger/core/widgets/resizable_text_area.dart';
import 'package:call_logger/core/widgets/spell_check_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ο ορθογραφικός έλεγχος αναβάλλει τον υπολογισμό του κατά 500ms.
///
/// Το instance της υπηρεσίας πρέπει να είναι **σταθερό** σε όλο το τεστ: κάθε
/// νέο instance πείθει τον controller ότι άλλαξε υπηρεσία και ξαναπρογραμματίζει
/// τον χρονοδιακόπτη — που έτσι δεν τελειώνει ποτέ.
final _sharedSpellService = LexiconSpellCheckService();

Future<void> flushSpellDebounce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpellCheckController controller;

  setUp(() {
    controller = SpellCheckController();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpField(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          enableSpellCheckProvider.overrideWith((ref) async => false),
          spellCheckServiceProvider.overrideWith(
            (ref) async => _sharedSpellService,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: ResizableTextArea(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Περιγραφή',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await flushSpellDebounce(tester);
  }

  LexiconSpellTextFormField innerField(WidgetTester tester) =>
      tester.widget<LexiconSpellTextFormField>(
        find.byType(LexiconSpellTextFormField),
      );

  double fieldHeight(WidgetTester tester) =>
      tester.getSize(find.byType(LexiconSpellTextFormField)).height;

  testWidgets('ξεκινά σε αυτόματο ύψος — το κείμενο ορίζει πόσο ανοίγει', (
    tester,
  ) async {
    await pumpField(tester);

    final field = innerField(tester);
    expect(field.expands, isFalse);
    expect(field.minLines, 3);
    expect(field.maxLines, 10);
    await flushSpellDebounce(tester);
  });

  testWidgets('το σύρσιμο της λαβής μεγαλώνει το πεδίο', (tester) async {
    await pumpField(tester);
    final before = fieldHeight(tester);

    await tester.drag(find.byKey(resizeGripKey), const Offset(0, 120));
    await tester.pumpAndSettle();
    await flushSpellDebounce(tester);

    expect(fieldHeight(tester), greaterThan(before));
    expect(
      innerField(tester).expands,
      isTrue,
      reason: 'Χειροκίνητο ύψος: το πεδίο γεμίζει ό,τι του δώσει ο γονέας',
    );
    await flushSpellDebounce(tester);
  });

  testWidgets('το κείμενο επιβιώνει της αλλαγής ύψους', (tester) async {
    await pumpField(tester);
    await tester.enterText(
      find.byType(LexiconSpellTextFormField),
      'Ο εκτυπωτής βγάζει κενές σελίδες.',
    );
    await tester.pumpAndSettle();
    await flushSpellDebounce(tester);

    await tester.drag(find.byKey(resizeGripKey), const Offset(0, 100));
    await tester.pumpAndSettle();
    await flushSpellDebounce(tester);

    expect(controller.text, 'Ο εκτυπωτής βγάζει κενές σελίδες.');
    expect(find.text('Ο εκτυπωτής βγάζει κενές σελίδες.'), findsOneWidget);
    await flushSpellDebounce(tester);
  });

  testWidgets('το διπλό κλικ στη λαβή επαναφέρει το αυτόματο ύψος', (
    tester,
  ) async {
    await pumpField(tester);
    final auto = fieldHeight(tester);

    await tester.drag(find.byKey(resizeGripKey), const Offset(0, 140));
    await tester.pumpAndSettle();
    await flushSpellDebounce(tester);
    expect(fieldHeight(tester), greaterThan(auto));

    // Δύο γρήγορα χτυπήματα: το πρώτο δεν πρέπει να αφήνει το πεδίο μισό-δρόμο.
    await tester.tap(find.byKey(resizeGripKey));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(resizeGripKey));
    await tester.pumpAndSettle();
    await flushSpellDebounce(tester);

    expect(fieldHeight(tester), auto);
    expect(innerField(tester).expands, isFalse);
    await flushSpellDebounce(tester);
  });

  testWidgets('το σύρσιμο προς τα πάνω δεν κατεβάζει το πεδίο κάτω από το '
      'ελάχιστο', (tester) async {
    await pumpField(tester);
    final auto = fieldHeight(tester);

    await tester.drag(find.byKey(resizeGripKey), const Offset(0, -400));
    await tester.pumpAndSettle();
    await flushSpellDebounce(tester);

    expect(
      fieldHeight(tester),
      greaterThan(0),
      reason: 'Το πεδίο δεν επιτρέπεται να εξαφανιστεί',
    );
    expect(fieldHeight(tester), lessThanOrEqualTo(auto + 1));
    await flushSpellDebounce(tester);
  });
}
