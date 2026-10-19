// Unit tests: τα βήματα ενός κλεισίματος, όπως τα διαβάζει ο άνθρωπος.
//
//   flutter test test/core/services/shutdown_trace_steps_test.dart

import 'package:call_logger/core/services/shutdown_trace_steps.dart';
import 'package:flutter_test/flutter_test.dart';

// Το πραγματικό ίχνος του κλεισίματος της 17/10, με σβηστό POPINIO.
const _popinioOff = '''
[2026-10-17 13:19:19] === shutdown trace start ===
[2026-10-17 13:19:19] step=0 "Αποθήκευση θέσης παραθύρου" START
[2026-10-17 13:19:19] step=0 "Αποθήκευση θέσης παραθύρου" OK durationMs=2
[2026-10-17 13:19:19] step=1 "Παράδοση συνεδρίας" START
[2026-10-17 13:19:37] step=1 "Παράδοση συνεδρίας" OK durationMs=18002
[2026-10-17 13:19:37] step=2 "Συγχώνευση αρχείων βάσης" START
[2026-10-17 13:19:39] step=2 "Συγχώνευση αρχείων βάσης" INTERRUPTED''';

void main() {
  test('κάθε βήμα μία φορά, με τη σειρά και την έκβασή του', () {
    final steps = parseShutdownTraceSteps(_popinioOff);

    expect(steps.map((s) => s.label), [
      'Αποθήκευση θέσης παραθύρου',
      'Παράδοση συνεδρίας',
      'Συγχώνευση αρχείων βάσης',
    ]);
    expect(steps.map((s) => s.outcome), [
      ShutdownTraceStepOutcome.completed,
      ShutdownTraceStepOutcome.completed,
      ShutdownTraceStepOutcome.interrupted,
    ]);
    expect(steps[1].durationMs, 18002);
    expect(steps[2].durationMs, isNull);
  });

  test('αποτυχία κρατά το σφάλμα· βήμα χωρίς τέλος = δεν ολοκληρώθηκε', () {
    final steps = parseShutdownTraceSteps('''
[2026-10-17 13:00:00] step=0 "Κλείσιμο σύνδεσης βάσης" START
[2026-10-17 13:00:00] step=0 "Κλείσιμο σύνδεσης βάσης" FAIL durationMs=12 error=database is locked
[2026-10-17 13:00:00] step=1 "Αντίγραφο ασφαλείας εξόδου" START''');

    expect(steps[0].outcome, ShutdownTraceStepOutcome.failed);
    expect(steps[0].durationMs, 12);
    expect(steps[0].error, 'database is locked');
    expect(steps[1].outcome, ShutdownTraceStepOutcome.unfinished);
  });

  test('άγνωστες ή αλλοιωμένες γραμμές αγνοούνται', () {
    expect(parseShutdownTraceSteps('σκουπίδια\nINCIDENT={}'), isEmpty);
    expect(parseShutdownTraceSteps(''), isEmpty);
  });
}
