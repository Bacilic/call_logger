// Περιοδικός έλεγχος νέας έκδοσης — συμβόλαιο: εφαρμογή που μένει ανοιχτή
// μέρες ξαναρωτά μόνη της τον φάκελο ενημερώσεων κάθε μία ώρα· ως τώρα ο
// έλεγχος γινόταν ΜΙΑ φορά στην εκκίνηση και ποτέ ξανά.
//
//   flutter test test/core/updates/update_periodic_check_test.dart

import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_periodic_check.dart';
import 'package:call_logger/core/updates/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

/// Κρατά ζωντανούς τον παλμό και τον έλεγχο, όπως το κέλυφος της εφαρμογής.
class _PulseHost extends ConsumerWidget {
  const _PulseHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(updatePeriodicCheckProvider);
    ref.watch(updateCheckProvider);
    return const SizedBox.shrink();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ο έλεγχος ξανατρέχει κάθε μία ώρα όσο ζει το κέλυφος', (
    tester,
  ) async {
    var checks = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateCheckProvider.overrideWith((ref) async {
            checks++;
            return const UpdateCheckResult.none();
          }),
        ],
        child: const _PulseHost(),
      ),
    );
    await tester.pump();
    expect(checks, 1, reason: greekExpectMsg('Ο πρώτος έλεγχος: στην εκκίνηση'));

    // Λίγο πριν συμπληρωθεί η ώρα: τίποτα ακόμη.
    await tester.pump(const Duration(minutes: 59));
    expect(checks, 1);

    // Η ώρα συμπληρώθηκε.
    await tester.pump(const Duration(minutes: 2));
    expect(
      checks,
      2,
      reason: greekExpectMsg(
        'Χωρίς τον παλμό, μηχάνημα που μένει ανοιχτό δεν μαθαίνει ποτέ '
        'για νέα έκδοση',
      ),
    );

    // Και συνεχίζει, δεν ήταν εφάπαξ.
    await tester.pump(const Duration(hours: 1));
    expect(checks, 3);
  });
}
