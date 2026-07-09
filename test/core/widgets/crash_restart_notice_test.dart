// Widget test: ενημερωτικός διάλογος μετά από αυτόματη επανεκκίνηση.
//
//   flutter test test/core/widgets/crash_restart_notice_test.dart

import 'package:call_logger/core/widgets/crash_restart_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrashRestartNotice', () {
    testWidgets('με flag true εμφανίζει διάλογο μία φορά και κλείνει με ΟΚ', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CrashRestartNotice(
            showNotice: true,
            child: const Text('παιδί'),
          ),
        ),
      );
      expect(find.text('παιδί'), findsOneWidget);
      expect(find.text('Αυτόματη επανεκκίνηση'), findsNothing);

      await tester.pump();
      expect(find.text('Αυτόματη επανεκκίνηση'), findsOneWidget);
      expect(
        find.textContaining('Τα δεδομένα σας είναι ασφαλή'),
        findsOneWidget,
      );

      await tester.tap(find.text('ΟΚ'));
      await tester.pumpAndSettle();
      expect(find.text('Αυτόματη επανεκκίνηση'), findsNothing);
      expect(find.text('παιδί'), findsOneWidget);
    });

    testWidgets('με flag false δεν εμφανίζει διάλογο', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CrashRestartNotice(
            showNotice: false,
            child: const Text('παιδί'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Αυτόματη επανεκκίνηση'), findsNothing);
      expect(find.text('παιδί'), findsOneWidget);
    });

    testWidgets('το παιδί child αποδίδεται κανονικά και στις δύο περιπτώσεις', (
      tester,
    ) async {
      for (final showNotice in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: CrashRestartNotice(
              showNotice: showNotice,
              child: Text('περιεχόμενο-$showNotice'),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('περιεχόμενο-$showNotice'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}
