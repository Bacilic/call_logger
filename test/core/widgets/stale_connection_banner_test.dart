// Η λωρίδα της νεκρής σύνδεσης: η λέξη «Επανεκκινήστε» κάνει την επανεκκίνηση.
//
//   flutter test test/core/widgets/stale_connection_banner_test.dart

import 'package:call_logger/core/widgets/stale_connection_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Future<void> Function() onRestart) => MaterialApp(
  home: Scaffold(body: StaleConnectionBanner(onRestart: onRestart)),
);

void main() {
  testWidgets('το κλικ στο «Επανεκκινήστε» επανεκκινεί την εφαρμογή', (
    tester,
  ) async {
    var restarts = 0;
    await tester.pumpWidget(_host(() async => restarts++));

    await tester.tapOnText(find.textRange.ofSubstring('Επανεκκινήστε'));
    await tester.pump();

    expect(restarts, 1);
  });

  testWidgets('το κλικ αλλού στη λωρίδα δεν επανεκκινεί', (tester) async {
    var restarts = 0;
    await tester.pumpWidget(_host(() async => restarts++));

    await tester.tapOnText(find.textRange.ofSubstring('φταίει η σύνδεση'));
    await tester.pump();

    expect(restarts, 0);
  });

  testWidgets('αποτυχημένη επανεκκίνηση λέει τι να κάνει ο χειριστής', (
    tester,
  ) async {
    // Αν η νέα εφαρμογή δεν ξεκινήσει, η τρέχουσα δεν κλείνει — και ο
    // χειριστής πρέπει να μάθει ότι το κλικ δεν έπιασε.
    await tester.pumpWidget(
      _host(() async => throw StateError('δεν ξεκίνησε')),
    );

    await tester.tapOnText(find.textRange.ofSubstring('Επανεκκινήστε'));
    await tester.pump();

    expect(
      find.textContaining('Η αυτόματη επανεκκίνηση δεν ήταν δυνατή'),
      findsOneWidget,
    );
  });
}
