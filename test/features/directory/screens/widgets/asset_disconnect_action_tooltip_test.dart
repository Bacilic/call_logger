// Οι ενέργειες των οδηγών περνούν τις υποδείξεις τους από το κοινό πρότυπο
// CompactTooltip — σκέτο Tooltip θα άπλωνε την πρόταση σε όλο το πλάτος.
//
//   flutter test test/features/directory/screens/widgets/asset_disconnect_action_tooltip_test.dart

import 'package:call_logger/core/widgets/compact_tooltip.dart';
import 'package:call_logger/features/directory/screens/widgets/asset_disconnect_action_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpSection(
  WidgetTester tester,
  List<AssetDisconnectActionEntry> actions,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AssetDisconnectActionSection(
          header: 'Δοκιμή',
          tinted: false,
          actions: actions,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ενέργεια με υπόδειξη τυλίγεται στο κοινό πρότυπο', (
    tester,
  ) async {
    await _pumpSection(tester, [
      AssetDisconnectActionEntry(
        icon: Icons.delete_outline,
        label: 'Διαγραφή όλων',
        tooltip: 'Καταργούνται 5 στοιχεία. Θα δείτε πρώτα αναλυτική λίστα.',
        onTap: () {},
      ),
    ]);

    final compact = find.byType(CompactTooltip);
    expect(compact, findsOneWidget);
    expect(
      tester.widget<CompactTooltip>(compact).message,
      contains('5 στοιχεία'),
    );
  });

  testWidgets('ενέργεια χωρίς υπόδειξη δεν τυλίγεται καθόλου', (tester) async {
    await _pumpSection(tester, [
      AssetDisconnectActionEntry(
        icon: Icons.check_circle_outline,
        label: 'Παραμονή',
        onTap: () {},
      ),
    ]);

    expect(
      find.byType(CompactTooltip),
      findsNothing,
      reason: 'Κενή υπόδειξη θα άφηνε αόρατο πλαίσιο να κλέβει το hover.',
    );
  });

  testWidgets('κενή συμβολοσειρά υπόδειξης μετράει ως απούσα', (tester) async {
    await _pumpSection(tester, [
      AssetDisconnectActionEntry(
        icon: Icons.check_circle_outline,
        label: 'Παραμονή',
        tooltip: '   ',
        onTap: () {},
      ),
    ]);

    expect(find.byType(CompactTooltip), findsNothing);
  });

  testWidgets('κάθε ενέργεια παίρνει τη δική της υπόδειξη', (tester) async {
    await _pumpSection(tester, [
      AssetDisconnectActionEntry(
        icon: Icons.delete_outline,
        label: 'Διαγραφή',
        tooltip: 'Πρώτη υπόδειξη',
        onTap: () {},
      ),
      AssetDisconnectActionEntry(
        icon: Icons.drive_file_move_outlined,
        label: 'Μεταφορά',
        tooltip: 'Δεύτερη υπόδειξη',
        onTap: () {},
      ),
    ]);

    final messages = tester
        .widgetList<CompactTooltip>(find.byType(CompactTooltip))
        .map((t) => t.message)
        .toList();
    expect(messages, ['Πρώτη υπόδειξη', 'Δεύτερη υπόδειξη']);
  });

  testWidgets('η υπόδειξη δεν εμποδίζει το πάτημα της ενέργειας', (
    tester,
  ) async {
    var taps = 0;
    await _pumpSection(tester, [
      AssetDisconnectActionEntry(
        icon: Icons.delete_outline,
        label: 'Διαγραφή',
        tooltip: 'Μεγάλη υπόδειξη με ολόκληρη πρόταση μέσα.',
        onTap: () => taps++,
      ),
    ]);

    await tester.tap(find.text('Διαγραφή'));
    await tester.pump();

    expect(taps, 1);
  });
}
