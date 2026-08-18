// Ο διάλογος «Η βάση δεν είναι έγκυρη» οφείλει να δείχνει το ωμό μήνυμα.
//
// Το περιστατικό: ο χρήστης είδε οκτώ «[OK]» και μία γενική φράση, ενώ η
// πρόταση που εξηγούσε τα πάντα —«invalid rootpage»— είχε ήδη πεταχτεί από
// την ταξινόμηση. Η οθόνη σφάλματος εκκίνησης την έδειχνε ήδη· ο διάλογος όχι.
//
//   flutter test test/features/database/database_check_failed_raw_message_test.dart

import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/features/database/widgets/database_check_failed_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _rawSqliteError =
    'DatabaseException(malformed database schema '
    '(call_external_links) - invalid rootpage)';

Future<void> _pump(WidgetTester tester, DatabaseInitResult result) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DatabaseCheckFailedContent(result: result),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('το ωμό μήνυμα του SQLite είναι προσβάσιμο από τον διάλογο', (
    tester,
  ) async {
    final result = DatabaseInitResult.fromException(
      _rawSqliteError,
      r'C:\vaseis\call_logger.db',
    );
    await _pump(tester, result);

    // Κλειστό: υπάρχει η πόρτα, όχι το κείμενο.
    expect(
      find.text(DatabaseCheckFailedContent.technicalSectionLabel),
      findsOneWidget,
    );
    expect(find.textContaining('invalid rootpage'), findsNothing);

    await tester.tap(
      find.text(DatabaseCheckFailedContent.technicalSectionLabel),
    );
    await tester.pumpAndSettle();

    // Ανοιχτό: το ωμό κείμενο, αυτούσιο.
    expect(find.textContaining('invalid rootpage'), findsOneWidget);
  });

  testWidgets('το κύριο μήνυμα ονομάζει την αιτία, δεν λέει μόνο «κατεστραμμένο»', (
    tester,
  ) async {
    final result = DatabaseInitResult.fromException(
      _rawSqliteError,
      r'C:\vaseis\call_logger.db',
    );
    await _pump(tester, result);

    expect(find.textContaining('ανοιχτή'), findsOneWidget);
  });

  testWidgets('χωρίς τεχνικό υλικό δεν εμφανίζεται καθόλου το τμήμα', (
    tester,
  ) async {
    const result = DatabaseInitResult(
      status: DatabaseStatus.corruptedOrInvalid,
      message: 'Η βάση δεν πέρασε τον έλεγχο.',
    );
    await _pump(tester, result);

    expect(find.text('Η βάση δεν πέρασε τον έλεγχο.'), findsOneWidget);
    expect(
      find.text(DatabaseCheckFailedContent.technicalSectionLabel),
      findsNothing,
    );
  });

  testWidgets('η συμβουλή μένει ορατή, τα διαγνωστικά μπαίνουν μέσα', (
    tester,
  ) async {
    final result = DatabaseInitResult(
      status: DatabaseStatus.corruptedOrInvalid,
      message: 'Το αρχείο της βάσης είναι ασυνεπές.',
      details:
          """Χρειάζεται νέο αντίγραφο με κλειστή την εφαρμογή.

$kDiagnosticsSectionMarker
Διαγνωστικά πρόσβασης βάσης:
[OK] Έγκυρη κεφαλίδα SQLite.""",
    );
    await _pump(tester, result);

    // Η συμβουλή: αμέσως ορατή, χωρίς κλικ.
    expect(find.textContaining('νέο αντίγραφο με κλειστή'), findsOneWidget);
    // Ο τοίχος των διαγνωστικών: όχι στα μούτρα του χρήστη.
    expect(find.textContaining('Έγκυρη κεφαλίδα SQLite'), findsNothing);

    await tester.tap(
      find.text(DatabaseCheckFailedContent.technicalSectionLabel),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Έγκυρη κεφαλίδα SQLite'), findsOneWidget);
  });
}
