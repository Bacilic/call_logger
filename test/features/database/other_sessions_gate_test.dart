// Ο φρουρός πριν από επικίνδυνη συντήρηση: ρωτά μόνο όταν υπάρχει κι άλλος.
//
//   flutter test test/features/database/other_sessions_gate_test.dart

import 'package:call_logger/features/database/services/active_sessions.dart';
import 'package:call_logger/features/database/widgets/other_sessions_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

ActiveSession _session({
  required String station,
  required bool isMine,
  String? name,
  String? appVersion,
}) {
  return ActiveSession(
    station: station,
    operatorName: name,
    lastSeenAt: DateTime.now().subtract(const Duration(seconds: 20)),
    appVersion: appVersion,
    isMine: isMine,
  );
}

/// Ανοίγει τον φρουρό με πάτημα κουμπιού και κρατά το αποτέλεσμά του.
Future<void> _pumpGate(
  WidgetTester tester, {
  required List<ActiveSession> sessions,
  required void Function(bool) onResult,
  String actionLabel = 'VACUUM',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final ok = await confirmDespiteOtherSessions(
                context,
                actionLabel: actionLabel,
                loadSessions: () async => sessions,
              );
              onResult(ok);
            },
            child: const Text('Εκτέλεση'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Εκτέλεση'));
  await tester.pumpAndSettle();
}

void main() {
  group('Φρουρός ανοιχτών συνεδριών', () {
    testWidgets('χωρίς άλλους δεν εμφανίζεται τίποτα και η ενέργεια περνά', (
      tester,
    ) async {
      bool? result;
      await _pumpGate(
        tester,
        sessions: [_session(station: 'PICINIO', isMine: true, name: 'Βασίλης')],
        onResult: (ok) => result = ok,
      );

      expect(
        find.text('Η βάση είναι ανοιχτή αλλού'),
        findsNothing,
        reason: greekExpectMsg(
          'Όποιος δουλεύει μόνος δεν πρέπει να μαθαίνει να πατά «Συνέχεια» '
          'χωρίς να διαβάζει',
        ),
      );
      expect(result, isTrue);
    });

    testWidgets('με άλλους εμφανίζεται η λίστα και η ενέργεια σταματά στο '
        '«Ακύρωση»', (tester) async {
      bool? result;
      await _pumpGate(
        tester,
        sessions: [
          _session(station: 'PICINIO', isMine: true, name: 'Βασίλης'),
          _session(station: 'TEP-02', isMine: false, name: 'Βαρβάρα'),
        ],
        onResult: (ok) => result = ok,
      );

      expect(find.text('Η βάση είναι ανοιχτή αλλού'), findsOneWidget);
      expect(find.textContaining('TEP-02'), findsOneWidget);
      expect(
        find.textContaining('PICINIO'),
        findsNothing,
        reason: greekExpectMsg('Η δική μου συνεδρία δεν είναι εμπόδιο'),
      );
      expect(find.textContaining('VACUUM'), findsOneWidget);

      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets(
      'το «Συνέχεια παρ\' όλα αυτά» αφήνει την ενέργεια να προχωρήσει',
      (tester) async {
        bool? result;
        await _pumpGate(
          tester,
          sessions: [
            _session(station: 'PICINIO', isMine: true),
            _session(station: 'TEP-02', isMine: false, name: 'Βαρβάρα'),
          ],
          onResult: (ok) => result = ok,
        );

        await tester.tap(find.text('Συνέχεια παρ\' όλα αυτά'));
        await tester.pumpAndSettle();

        expect(
          result,
          isTrue,
          reason: greekExpectMsg(
            'Ο φρουρός προειδοποιεί — η απόφαση μένει στον άνθρωπο',
          ),
        );
      },
    );
  });
}
