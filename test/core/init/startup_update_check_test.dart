import 'package:call_logger/core/init/startup_journal.dart';
import 'package:call_logger/core/init/startup_update_check.dart';
import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ο έλεγχος έκδοσης διαβάζει δικτυακό φάκελο. Το συμβόλαιο είναι απλό: ό,τι
/// κι αν κάνει το δίκτυο, η εκκίνηση προχωρά και ο χρήστης μαθαίνει τι έγινε.
void main() {
  late StartupJournal journal;

  setUp(() => journal = StartupJournal.instance..reset());

  StartupStep singleStep() => journal.steps.value.single;

  test('ενημερωμένος: μία γραμμή που το λέει', () async {
    await runStartupUpdateCheck(
      () async => UpdateCheckResult(
        updateAvailable: false,
        checkedAt: DateTime(2026, 8, 12),
      ),
      journal: journal,
    );

    expect(singleStep().status, StartupStepStatus.ok);
    expect(singleStep().label, contains('είστε ενημερωμένοι'));
  });

  test('νέα έκδοση: η γραμμή ονομάζει την έκδοση', () async {
    await runStartupUpdateCheck(
      () async => UpdateCheckResult(
        updateAvailable: true,
        latestVersion: '0.37.0',
        checkedAt: DateTime(2026, 8, 12),
      ),
      journal: journal,
    );

    expect(singleStep().status, StartupStepStatus.ok);
    expect(singleStep().label, contains('0.37.0'));
  });

  test('έλεγχος που δεν έγινε καν δεν γεμίζει την οθόνη', () async {
    await runStartupUpdateCheck(
      () async => const UpdateCheckResult.none(),
      journal: journal,
    );

    expect(singleStep().status, StartupStepStatus.skipped);
    expect(journal.visibleSteps, isEmpty);
  });

  test('άφταστος φάκελος: κόβεται στο όριο, η εκκίνηση συνεχίζει', () async {
    final result = await runStartupUpdateCheck(
      () => Future.delayed(
        const Duration(seconds: 30),
        () => const UpdateCheckResult.none(),
      ),
      timeout: const Duration(milliseconds: 40),
      journal: journal,
    );

    expect(result, isNull);
    expect(singleStep().status, StartupStepStatus.warning);
    expect(singleStep().label, 'Ο φάκελος ενημερώσεων δεν ήταν διαθέσιμος');
    expect(singleStep().detail, contains('40 ms'));
  });

  test('σφάλμα δικτύου: προειδοποίηση, όχι κατάρρευση', () async {
    final result = await runStartupUpdateCheck(
      () async => throw const FakeNetworkException('δεν βρέθηκε η διαδρομή'),
      journal: journal,
    );

    expect(result, isNull);
    expect(singleStep().status, StartupStepStatus.warning);
    expect(singleStep().detail, contains('δεν βρέθηκε η διαδρομή'));
  });

  test('το προεπιλεγμένο όριο είναι 1,5 δευτερόλεπτο', () {
    expect(kStartupUpdateCheckTimeout, const Duration(milliseconds: 1500));
  });
}

/// Ελαφρύ υποκατάστατο σφάλματος δικτύου, ώστε το τεστ να μη χρειάζεται dart:io.
class FakeNetworkException implements Exception {
  const FakeNetworkException(this.message);
  final String message;
  @override
  String toString() => message;
}
