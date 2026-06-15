// Δοκιμές διφασικής ροής πράσινο (+) → πορτοκαλί (+) στην οθόνη κλήσεων.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/calls/association_two_step_test.dart
//
// Γνωστές αδυναμίες (αναμένονται αποτυχίες στο πρώτο τρέξιμο):
//   • G3-or-dept-no — πορτοκαλί «δεν κάνει τίποτα» (αναπαραγωγή 2001)
//   • G1-or-dept-no — ίδια συμπεριφορά με dialog Όχι για τμήμα
//   • G4/G5/G6-or-phone — updatePhone καθαρίζει caller → 2ος χρήστης (διπλή εγγραφή)

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/association_two_step_runner.dart';
import '../../helpers/association_two_step_scenarios.dart';
import '../../test_reporter.dart';
import '../../test_setup.dart';

void main() {
  final scenarios = buildAssociationTwoStepScenarios();
  final reporter = GreekTestReportCollector();
  final scenarioResults = <AssociationTwoStepResult>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await bindCallLoggerIsolatedTestDatabase();
  });

  tearDownAll(() async {
    final knownBugFails = scenarioResults
        .where((r) => !r.passed && r.scenario.knownBugHint != null)
        .toList();
    if (knownBugFails.isNotEmpty) {
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print('══ Γνωστές αδυναμίες που επιβεβαιώθηκαν ══');
      for (final r in knownBugFails) {
        // ignore: avoid_print
        print('  • ${r.scenario.id}: ${r.failures.join('; ')}');
      }
    }
    reporter.printFinalSummary(
      title: 'Πράσινο → Πορτοκαλί — συγκεντρωτική αναφορά',
    );
    await releaseCallLoggerTestDatabase();
  });

  group('Association two-step — πράσινο (+) → πορτοκαλί (+)', () {
    for (final scenario in scenarios) {
      test(scenario.title, () async {
        await AssociationTwoStepRunner.resetCatalog(
          preseedDepartmentName: scenario.preseedDepartmentName,
        );

        late ProviderContainer container;
        try {
          container = await AssociationTwoStepRunner.createContainer();
          final result = await AssociationTwoStepRunner.run(container, scenario);
          scenarioResults.add(result);

          if (result.passed) {
            reporter.recordPass('${scenario.id}: ${scenario.title}');
          } else {
            final hint =
                scenario.knownBugHint ?? result.failures.join(' | ');
            reporter.recordFail(
              '${scenario.id}: ${scenario.title}',
              hint: hint,
            );
          }

          expect(
            result.failures,
            isEmpty,
            reason: result.failures.isEmpty
                ? null
                : '${scenario.id}:\n${result.failures.join('\n')}'
                    '${scenario.knownBugHint != null ? '\n[Γνωστό] ${scenario.knownBugHint}' : ''}',
          );
        } finally {
          container.dispose();
        }
      });
    }
  });
}
