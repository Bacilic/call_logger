// Unit widget tests: κοινή «Κάρτα Ενότητας» (SectionCard).
//
//   flutter test test/core/widgets/section_card_test.dart

import 'package:call_logger/core/widgets/section_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  group('SectionCard', () {
    testWidgets('αποδίδει εικονίδιο, τίτλο, trailing και περιεχόμενο', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SectionCard(
            icon: Icons.edit_note,
            title: 'Στοιχεία κλήσης',
            trailing: Icon(Icons.more_vert),
            child: Text('περιεχόμενο κάρτας'),
          ),
        ),
      );

      expect(
        find.text('Στοιχεία κλήσης'),
        findsOneWidget,
        reason: greekExpectMsg('Ο τίτλος της κάρτας πρέπει να εμφανίζεται'),
      );
      expect(
        find.byIcon(Icons.edit_note),
        findsOneWidget,
        reason: greekExpectMsg('Το εικονίδιο κεφαλίδας πρέπει να εμφανίζεται'),
      );
      expect(
        find.byIcon(Icons.more_vert),
        findsOneWidget,
        reason: greekExpectMsg('Το trailing στοιχείο πρέπει να εμφανίζεται'),
      );
      expect(
        find.text('περιεχόμενο κάρτας'),
        findsOneWidget,
        reason: greekExpectMsg('Το περιεχόμενο πρέπει να εμφανίζεται'),
      );
    });

    testWidgets('χωρίς τίτλο: αποδίδει μόνο το περιεχόμενο', (tester) async {
      await tester.pumpWidget(
        _host(
          const SectionCard(
            child: Text('σκέτο περιεχόμενο'),
          ),
        ),
      );

      expect(find.text('σκέτο περιεχόμενο'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SectionCard),
          matching: find.byType(Row),
        ),
        findsNothing,
        reason: greekExpectMsg('Χωρίς τίτλο δεν πρέπει να υπάρχει κεφαλίδα'),
      );
    });

    testWidgets('hugContent: η κάρτα αγκαλιάζει το περιεχόμενό της', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Align(
            alignment: Alignment.topLeft,
            child: SectionCard(
              icon: Icons.desktop_windows_outlined,
              title: 'Τίτλος',
              hugContent: true,
              child: SizedBox(width: 120, height: 20),
            ),
          ),
        ),
      );

      final cardWidth = tester.getSize(find.byType(SectionCard)).width;
      expect(
        cardWidth,
        lessThan(320),
        reason: greekExpectMsg(
          'Με hugContent η κάρτα δεν πρέπει να απλώνεται σε όλο το πλάτος '
          '(βρέθηκε ${cardWidth.toStringAsFixed(1)}px)',
        ),
      );
    });
  });
}
