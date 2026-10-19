// Widget tests: η οθόνη σφάλματος βάσης όταν ΑΛΛΑΖΕΙ το αποτέλεσμα.
//
// Σενάριο πεδίου (27/09/2026): κλειστό δίκτυο → η οθόνη γεννιέται με «το
// δίκτυο δεν απαντά» → ο χρήστης διαλέγει την τοπική βάση → η επαναδοκιμή
// φέρνει «η βάση θέλει αναβάθμιση σχήματος». Η οθόνη είναι η ΙΔΙΑ, οπότε η
// λογική που προσφέρει τη διέξοδο δεν ξανάτρεχε και ο χρήστης έμενε με ένα
// κόκκινο «Σφάλμα» χωρίς κανένα κουμπί που να τον βγάζει.
//
// Τα τεστ παρακολουθούν **αν ξεκίνησε η διέξοδος**, όχι τι διάλογο δείχνει:
// οι πραγματικές διέξοδοι ρωτούν τη βάση και τα ίχνη των σταθμών, που σε
// σουίτα εξαρτώνται από τη σειρά εκτέλεσης.
//
//   flutter test test/core/widgets/database_error_screen_result_change_test.dart

import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/widgets/database_error_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DatabaseInitResult _networkUnreachable() => DatabaseInitResult(
  status: DatabaseStatus.accessDenied,
  message: 'Η διαδρομή του δικτύου δεν εντοπίστηκε.',
  details: 'Διαδρομή: \\\\popinio\\CallLogger\\Data Base\\Hospital.db',
  path: '\\\\popinio\\CallLogger\\Data Base\\Hospital.db',
  recoveryKind: DatabaseInitRecoveryKind.networkUnreachable,
);

DatabaseInitResult _needsSchemaUpgrade() => DatabaseInitResult(
  status: DatabaseStatus.corruptedOrInvalid,
  message:
      'Το αρχείο «Hospital.db» έχει σχήμα έκδοσης 66. Η εφαρμογή '
      'χρησιμοποιεί την έκδοση 67.',
  details: 'Έκδοση αρχείου: 66\nΈκδοση εφαρμογής: 67',
  path: r'C:\profiles\dev\Hospital.db',
  recoveryKind: DatabaseInitRecoveryKind.schemaUpgradeConsent,
  technicalCode: '66→67',
);

DatabaseInitResult _databaseNewer() => DatabaseInitResult(
  status: DatabaseStatus.corruptedOrInvalid,
  message:
      'Το αρχείο «Hospital.db» είναι στην έκδοση 68. Αυτή η εφαρμογή '
      'διαβάζει έως την έκδοση 67.',
  details: 'Έκδοση αρχείου: 68\nΈκδοση εφαρμογής: 67',
  path: r'\\popinio\CallLogger\Data Base\Hospital.db',
  recoveryKind: DatabaseInitRecoveryKind.databaseNewerThanApp,
  technicalCode: '68→67',
);

class _Host extends StatefulWidget {
  const _Host({super.key, required this.initial, required this.onRecovery});

  final DatabaseInitResult initial;
  final void Function(DatabaseInitRecoveryKind kind) onRecovery;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late DatabaseInitResult _result = widget.initial;

  void swapTo(DatabaseInitResult next) => setState(() => _result = next);

  @override
  Widget build(BuildContext context) {
    return DatabaseErrorScreen(
      result: _result,
      dbPath: _result.path,
      onRetry: () async {},
      startRecoveryForTest: widget.onRecovery,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<DatabaseInitRecoveryKind> started;

  setUp(() => started = <DatabaseInitRecoveryKind>[]);

  Future<_HostState> pumpHost(
    WidgetTester tester,
    DatabaseInitResult initial,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _Host(key: key, initial: initial, onRecovery: started.add),
        ),
      ),
    );
    await tester.pump();
    return key.currentState!;
  }

  testWidgets('αλλάζοντας σε «θέλει αναβάθμιση», η διέξοδος ξεκινά', (
    tester,
  ) async {
    final host = await pumpHost(tester, _networkUnreachable());
    expect(started, isEmpty, reason: 'το δίκτυο δεν έχει αυτόματη διέξοδο');

    host.swapTo(_needsSchemaUpgrade());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(started, [
      DatabaseInitRecoveryKind.schemaUpgradeConsent,
    ], reason: 'χωρίς αυτό ο χρήστης μένει με σφάλμα και κανένα κουμπί');
  });

  testWidgets('η ίδια διέξοδος δεν ξεκινά δύο φορές για το ίδιο σφάλμα', (
    tester,
  ) async {
    final host = await pumpHost(tester, _needsSchemaUpgrade());
    await tester.pump(const Duration(milliseconds: 50));
    expect(started, hasLength(1));

    // Ξαναχτίσιμο με ΤΟ ΙΔΙΟ αποτέλεσμα (π.χ. από ανανέωση γονέα).
    host.swapTo(host.widget.initial);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(started, hasLength(1));
  });

  testWidgets('βάση νεότερης έκδοσης: η «Επαναδοκιμή» ξαναρωτά για '
      'ενημέρωση, ακόμη κι όταν το σφάλμα μένει ίδιο', (tester) async {
    // Σενάριο πεδίου 17/10/2026: POPINIO με 0.61.0, βάση 68 → «Κλείσιμο» του
    // διαλόγου → δημοσίευση 0.63.0 από άλλον σταθμό → «Επαναδοκιμή» στο
    // POPINIO δεν έκανε τίποτα· η αναβάθμιση φάνηκε μόνο με επανεκκίνηση.
    await pumpHost(tester, _databaseNewer());
    await tester.pump(const Duration(milliseconds: 50));
    expect(started, [DatabaseInitRecoveryKind.databaseNewerThanApp]);

    await tester.tap(find.text('Επαναδοκιμή'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(started, [
      DatabaseInitRecoveryKind.databaseNewerThanApp,
      DatabaseInitRecoveryKind.databaseNewerThanApp,
    ], reason: 'ο διάλογος ξαναρωτά τον φάκελο ενημερώσεων');
  });

  testWidgets('η αναμονή συγκατάθεσης ΔΕΝ παρουσιάζεται ως βλάβη', (
    tester,
  ) async {
    await pumpHost(tester, _needsSchemaUpgrade());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Η βάση θέλει αναβάθμιση'), findsOneWidget);
    expect(
      find.text('Σφάλμα'),
      findsNothing,
      reason: 'η βάση είναι σωστή· μόνο η απόφαση του χρήστη λείπει',
    );
  });
}
