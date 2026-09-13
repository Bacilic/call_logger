// Η οθόνη εκκίνησης δεν σπάει από το περιεχόμενο που η ίδια δείχνει.
//
// Το σφάλμα που γέννησε αυτό το αρχείο: με φθαρμένη βάση τα διαγνωστικά
// φούσκωσαν σε εκατοντάδες γραμμές, η οθόνη ξεχείλισε κατά 831 pixels και η
// εφαρμογή δεν εκκίνησε καθόλου — ο χειριστής έμεινε μπροστά σε πορτοκαλί
// «Σφάλμα διάταξης», χωρίς να μάθει ποτέ ότι το πρόβλημα ήταν η βάση του.
//
//   flutter test test/core/widgets/init_loading_screen_test.dart

import 'package:call_logger/core/database/database_init_progress_provider.dart';
import 'package:call_logger/core/widgets/app_init_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, String? diagnostic) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseInitProgressProvider.overrideWith(
          () => _FixedProgress(
            DatabaseInitProgressState(
              currentStep: 'Διαγνωστικός έλεγχος πρόσβασης',
              diagnosticInfo: diagnostic,
            ),
          ),
        ),
      ],
      child: const MaterialApp(home: InitLoadingScreen()),
    ),
  );
  await tester.pump();
}

class _FixedProgress extends DatabaseInitProgressNotifier {
  _FixedProgress(this._value);

  final DatabaseInitProgressState _value;

  @override
  DatabaseInitProgressState build() => _value;
}

void main() {
  testWidgets('με τεράστιο διαγνωστικό, η οθόνη κυλά αντί να σπάσει', (
    tester,
  ) async {
    final huge = List.generate(
      214,
      (i) => 'Tree 18 page ${2100 + i} cell 3: Rowid 5041 out of order',
    ).join('\n');

    await _pump(tester, huge);

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('χωρίς διαγνωστικά δείχνει το βήμα που τρέχει', (tester) async {
    await _pump(tester, null);

    expect(tester.takeException(), isNull);
    expect(find.text('Διαγνωστικός έλεγχος πρόσβασης'), findsOneWidget);
    expect(find.text('Αντιγραφή διαγνωστικών'), findsNothing);
  });
}
