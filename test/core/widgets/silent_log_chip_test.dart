// Widget tests: η ένδειξη «χωρίς καταγραφή» στην πλαϊνή μπάρα.
//
//   flutter test test/core/widgets/silent_log_chip_test.dart

import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/core/widgets/silent_log_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required CrashLogService? service,
  bool extended = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SilentLogChip(extended: extended, serviceForTest: service),
      ),
    ),
  );
  await tester.pump();
}

CrashLogService _service() =>
    CrashLogService(logsDirectory: r'\\popinio\CallLogger\Data Base\logs');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('με ζωντανό ημερολόγιο δεν φαίνεται τίποτα', (tester) async {
    await _pump(tester, service: _service());

    expect(find.text('Χωρίς καταγραφή'), findsNothing);
  });

  testWidgets('όταν σιγήσει, η ένδειξη εμφανίζεται', (tester) async {
    final service = _service();
    service.disableDiskForTest('Η διαδρομή του δικτύου δεν εντοπίστηκε');

    await _pump(tester, service: service);

    expect(find.text('Χωρίς καταγραφή'), findsOneWidget);
  });

  testWidgets('στη στενή μπάρα μένει μόνο το εικονίδιο', (tester) async {
    final service = _service();
    service.disableDiskForTest('δίκτυο');

    await _pump(tester, service: service, extended: false);

    expect(find.text('Χωρίς καταγραφή'), findsNothing);
    expect(find.byIcon(Icons.history_toggle_off_rounded), findsOneWidget);
  });

  testWidgets('χωρίς υπηρεσία δεν σκάει και δεν δείχνει τίποτα', (
    tester,
  ) async {
    await _pump(tester, service: null);

    expect(find.text('Χωρίς καταγραφή'), findsNothing);
  });
}
