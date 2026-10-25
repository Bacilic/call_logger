import 'package:call_logger/features/directory/services/mass_deletion_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Γράφει τη λέξη της ολικής διαγραφής στον διάλογο, όπως ο χρήστης.
///
/// Τα τεστ που στήνουν μικρό κατάλογο και τον σβήνουν ολόκληρο περνούν πια
/// από την αυστηρή προειδοποίηση: χωρίς τη λέξη, το κουμπί μένει ανενεργό.
///
/// Περιμένει πρώτα τον διάλογο: πριν ανοίξει, η καρτέλα διαβάζει από τη βάση
/// το ποσοστό της προειδοποίησης — πραγματική ανάγνωση, που δεν τελειώνει
/// μέσα σε ένα `pumpAndSettle`.
Future<void> typeWholeCatalogConfirmWord(WidgetTester tester) async {
  final field = find.byKey(const ValueKey('mass-deletion-confirm-word'));
  for (var i = 0; i < 60 && field.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(
    field,
    findsOneWidget,
    reason: 'Ο διάλογος σβήνει ολόκληρο τον κατάλογο και ζητά τη λέξη.',
  );
  await tester.enterText(field, kWholeCatalogConfirmWord);
  await tester.pump();
}
