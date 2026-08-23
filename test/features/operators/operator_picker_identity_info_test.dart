// Όποιος διαλέγει ποιος θα υπογράφει τις ενέργειές του πρέπει να βλέπει τα ίδια
// στοιχεία με όποιον τα διαχειρίζεται — αλλιώς διαλέγει ανάμεσα σε σκέτα ονόματα.
//
//   flutter test test/features/operators/operator_picker_identity_info_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/operators/screens/operator_picker_screen.dart';
import 'package:call_logger/features/operators/services/operator_presence_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Operator _profile(
  int id,
  String name, {
  String? windowsAccount,
  bool isAdmin = false,
}) => Operator(
  id: id,
  displayName: name,
  windowsAccount: windowsAccount,
  isAdmin: isAdmin,
  createdAt: DateTime(2026, 8, 20),
);

void main() {
  group('Επιλογή χρήστη — τι ξέρει κανείς πριν διαλέξει', () {
    Future<void> pump(
      WidgetTester tester, {
      required List<Operator> profiles,
      Map<int, List<OperatorPresenceLine>> presence = const {},
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorPickerScreen(
            profiles: profiles,
            presence: presence,
            onPick: (_) {},
            onCreate: (name, bind) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('ο ρόλος γράφεται για κάθε προφίλ, και για τους δύο', (
      tester,
    ) async {
      await pump(
        tester,
        profiles: [
          _profile(1, 'Βασίλης', windowsAccount: 'v.drosos', isAdmin: true),
          _profile(2, 'Μαρία', windowsAccount: 'm.papa'),
        ],
      );

      expect(find.text('Διαχειριστής'), findsOneWidget);
      expect(find.text('Χρήστης'), findsOneWidget);
    });

    testWidgets('φαίνεται ο λογαριασμός Windows κάθε προφίλ', (tester) async {
      await pump(
        tester,
        profiles: [_profile(1, 'Βασίλης', windowsAccount: 'v.drosos')],
      );

      expect(find.text('v.drosos'), findsOneWidget);
    });

    testWidgets('προφίλ χωρίς λογαριασμό Windows το δηλώνει', (tester) async {
      await pump(tester, profiles: [_profile(3, 'Δοκιμαστικός')]);

      expect(find.text('Αυτόνομο'), findsOneWidget);
      expect(
        find.text('Χωρίς λογαριασμό Windows — επιλέγεται χειροκίνητα'),
        findsOneWidget,
      );
    });

    testWidgets('φαίνεται πότε συνδέθηκε τελευταία φορά ο καθένας', (
      tester,
    ) async {
      await pump(
        tester,
        profiles: [
          _profile(1, 'Βασίλης', windowsAccount: 'v.drosos'),
          _profile(2, 'Μαρία', windowsAccount: 'm.papa'),
        ],
        presence: const {
          1: [
            OperatorPresenceLine(
              online: true,
              text: 'Συνδεδεμένος τώρα — PICINIO',
            ),
          ],
          2: [
            OperatorPresenceLine(
              online: false,
              text: 'Τελευταία σύνδεση 20/08/2026 09:12 — RADIOLOGY',
            ),
          ],
        },
      );

      expect(find.text('Συνδεδεμένος τώρα — PICINIO'), findsOneWidget);
      expect(
        find.text('Τελευταία σύνδεση 20/08/2026 09:12 — RADIOLOGY'),
        findsOneWidget,
      );
    });

    testWidgets('χωρίς βελάκι ανάπτυξης δίπλα στο προφίλ', (tester) async {
      await pump(
        tester,
        profiles: [_profile(1, 'Βασίλης', windowsAccount: 'v.drosos')],
      );

      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('η επιλογή εξακολουθεί να δουλεύει με πάτημα στην κάρτα', (
      tester,
    ) async {
      final picked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorPickerScreen(
            profiles: [_profile(1, 'Βασίλης', windowsAccount: 'v.drosos')],
            onPick: (operator) => picked.add(operator.displayName),
            onCreate: (name, bind) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Βασίλης'));
      await tester.pumpAndSettle();

      expect(picked, ['Βασίλης']);
    });
  });
}
