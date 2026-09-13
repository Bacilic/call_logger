// Οι κάρτες των κανόνων επικύρωσης: κάθε διακόπτης της οθόνης γράφει τον
// ΔΙΚΟ ΤΟΥ κανόνα, και κανένας αποθηκευμένος κανόνας δεν έμεινε χωρίς γραμμή.
//
//   flutter test test/features/directory/validation_rule_cards_test.dart

import 'package:call_logger/features/directory/models/catalog_validation_rules.dart';
import 'package:call_logger/features/directory/screens/widgets/validation_rules/validation_rule_cards.dart';
import 'package:call_logger/features/directory/screens/widgets/validation_rules/validation_rule_field_controllers.dart';
import 'package:call_logger/features/directory/screens/widgets/validation_rules/validation_rule_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ποιο κλειδί άλλαξε η [change] όταν εφαρμοστεί στους [before].
///
/// Δουλεύει πάνω στο αποθηκευμένο σχήμα, όχι σε λίστα ονομάτων: έτσι ένας
/// κανόνας που προστέθηκε χωρίς να ενημερωθεί κανείς πιάνεται κι αυτός.
Set<String> _changedKeys(
  CatalogValidationRules before,
  ValidationRuleChange change,
) {
  final a = before.toJson();
  final b = change(before).toJson();
  return {
    for (final key in b.keys)
      if (a[key] != b[key]) key,
  };
}

void main() {
  const rules = CatalogValidationRules();

  late ValidationRuleFieldControllers fields;
  late List<ValidationRuleChange> captured;

  setUp(() {
    fields = ValidationRuleFieldControllers()..fillFrom(rules);
    captured = <ValidationRuleChange>[];
  });

  tearDown(() => fields.dispose());

  Future<List<Switch>> pumpCards(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValidationRuleCards(
              rules: rules,
              fields: fields,
              onApply: captured.add,
            ),
          ),
        ),
      ),
    );
    return tester.widgetList<Switch>(find.byType(Switch)).toList();
  }

  testWidgets('κάθε διακόπτης γράφει δικό του κανόνα, κανέναν δύο φορές', (
    tester,
  ) async {
    final switches = await pumpCards(tester);
    expect(switches, isNotEmpty);

    final touched = <String>[];
    for (final box in switches) {
      box.onChanged!(!box.value);
    }
    expect(captured, hasLength(switches.length));

    for (final change in captured) {
      final keys = _changedKeys(rules, change);
      // Ένας διακόπτης αγγίζει ακριβώς έναν κανόνα — ποτέ δύο μαζί.
      expect(keys, hasLength(1), reason: 'άλλαξαν $keys');
      touched.add(keys.single);
    }

    // Καμία επανάληψη: δύο γραμμές που γράφουν τον ίδιο κανόνα θα σήμαινε
    // ότι ένας άλλος έμεινε χωρίς διακόπτη.
    expect(touched.toSet(), hasLength(touched.length));
  });

  testWidgets('κανένας αποθηκευμένος κανόνας δεν έμεινε χωρίς γραμμή', (
    tester,
  ) async {
    final switches = await pumpCards(tester);
    for (final box in switches) {
      box.onChanged!(!box.value);
    }
    final touched = {
      for (final change in captured) _changedKeys(rules, change).single,
    };

    final stored = rules.toJson().keys.where((k) => k.endsWith('_enabled'));
    expect(touched, containsAll(stored));
  });

  testWidgets('το πεδίο των εξαιρούμενων συμβόλων γράφει τη νέα τιμή', (
    tester,
  ) async {
    await pumpCards(tester);
    // Το πότε αποθηκεύεται το φυλάει το τεστ του ίδιου του πεδίου· εδώ
    // ελέγχεται μόνο ότι η κάρτα το έδεσε στον σωστό κανόνα.
    final field = tester.widget<CommitTextField>(
      find.byType(CommitTextField),
    );
    field.onCommitted('(, -, .');

    expect(captured, hasLength(1));
    expect(captured.single(rules).personNameAllowedSymbols, '(, -, .');
  });
}
