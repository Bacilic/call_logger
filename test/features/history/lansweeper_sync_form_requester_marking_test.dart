// Η γραμμή «Στο ticket — Αιτών:» της φόρμας Lansweeper δεν παρουσιάζει πια
// προβληματικό αιτούντα «σαν να ήταν μια χαρά»: κόκκινο = λάθος μορφή με το
// στοχευμένο λάθος και τη συνέπεια στο tooltip, πορτοκαλί = ύποπτος τομέας.
// Ποτέ φραγμός — τον τελικό λόγο τον έχει το SearchUsers στην καταχώρηση.
//
//   flutter test test/features/history/lansweeper_sync_form_requester_marking_test.dart

import 'package:call_logger/core/widgets/spell_check_controller.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_sync_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SpellCheckController titleController;
  late SpellCheckController notesController;
  late SpellCheckController solutionController;

  setUp(() {
    titleController = SpellCheckController();
    notesController = SpellCheckController();
    solutionController = SpellCheckController();
  });

  tearDown(() {
    titleController.dispose();
    notesController.dispose();
    solutionController.dispose();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    required String? requester,
    String? referenceDomain,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LansweeperSyncForm(
              titleController: titleController,
              notesController: notesController,
              solutionController: solutionController,
              autoParties: (requester: requester, asset: 'PC3879'),
              referenceDomain: referenceDomain,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Tooltip lineTooltip(WidgetTester tester) {
    return tester.widget<Tooltip>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('lansweeper_auto_parties_line')),
            matching: find.byType(Tooltip),
          )
          .first,
    );
  }

  testWidgets(
    'άκυρος αιτών → το στοχευμένο λάθος και η συνέπεια στο tooltip',
    (tester) async {
      await pumpForm(
        tester,
        requester: r'Γραφείο Λοιμώξεων gnk\loimokseis1',
      );

      final tooltip = lineTooltip(tester);
      expect(tooltip.message, contains('λείπει το «=»'));
      expect(
        tooltip.message,
        contains('θα καταχωρηθεί χωρίς αιτούντα'),
      );
    },
  );

  testWidgets(
    'έγκυρος αιτών με ύποπτο τομέα → η υποψία στο tooltip',
    (tester) async {
      await pumpForm(
        tester,
        requester: r'3gnk\TepPath1',
        referenceDomain: 'gnk',
      );

      final tooltip = lineTooltip(tester);
      expect(tooltip.message, contains('«3gnk»'));
      expect(tooltip.message, contains('πιθανό τυπογραφικό'));
    },
  );

  testWidgets('καθαρός αιτών → κανένα σήμα κινδύνου στο tooltip',
      (tester) async {
    await pumpForm(
      tester,
      requester: r'gnk\loimokseis1',
      referenceDomain: 'gnk',
    );

    final tooltip = lineTooltip(tester);
    expect(tooltip.message, isNot(contains('⚠')));
    expect(tooltip.message, contains('Συμπληρώνονται αυτόματα'));
  });

  testWidgets('χωρίς αιτούντα («—») → καμία διάγνωση, καμία σήμανση',
      (tester) async {
    await pumpForm(tester, requester: null);

    final tooltip = lineTooltip(tester);
    expect(tooltip.message, isNot(contains('⚠')));
    expect(
      find.text('Στο ticket — Αιτών: — · Εξοπλισμός: PC3879', findRichText: true),
      findsOneWidget,
    );
  });
}
