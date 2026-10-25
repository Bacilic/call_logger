// Πίνακας Ιστορικού κλήσεων: γραμμές, ταξινόμηση από την κεφαλίδα, επιλογή.
//
//   flutter test test/features/history/history_data_table_test.dart

import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:call_logger/features/history/widgets/history_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _rows = <Map<String, dynamic>>[
  {
    'id': 1,
    'user_first_name': 'Βασίλης',
    'user_last_name': 'Α.',
    'date': '2026-10-11',
    'time': '09:05',
    'issue': 'Δεν τυπώνει',
    'duration': 65,
  },
  {
    'id': 2,
    'user_first_name': 'Γιώργος',
    'user_last_name': 'Β.',
    'date': '2026-10-10',
    'time': '08:00',
    'issue': 'Κολλημένο ποντίκι',
    'duration': 120,
  },
  {
    'id': 3,
    'user_first_name': 'Άλφα',
    'user_last_name': 'Γ.',
    'date': '2026-10-12',
    'time': '10:30',
    'issue': 'Χωρίς δίκτυο',
    'duration': 30,
  },
];

Future<ProviderContainer> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1800, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: HistoryDataTable(rows: _rows)),
      ),
    ),
  );
  await tester.pump();
  return container;
}

List<String> _callerOrder(WidgetTester tester) {
  final names = ['Βασίλης Α.', 'Γιώργος Β.', 'Άλφα Γ.'];
  final positions = {
    for (final n in names) n: tester.getTopLeft(find.text(n)).dy,
  };
  return names..sort((a, b) => positions[a]!.compareTo(positions[b]!));
}

void main() {
  testWidgets('χωρίς ταξινόμηση οι γραμμές μένουν στη σειρά της βάσης', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('11-10-2026 09:05'), findsOneWidget);
    expect(find.text('Κολλημένο ποντίκι'), findsOneWidget);
    expect(_callerOrder(tester), ['Βασίλης Α.', 'Γιώργος Β.', 'Άλφα Γ.']);
  });

  testWidgets('κλικ στην κεφαλίδα ταξινομεί, δεύτερο κλικ αντιστρέφει', (
    tester,
  ) async {
    final container = await _pump(tester);

    await tester.tap(find.text('Διάρκεια'));
    await tester.pump();
    expect(
      container.read(historySortProvider).column,
      HistorySortColumn.duration,
    );
    expect(_callerOrder(tester), ['Άλφα Γ.', 'Βασίλης Α.', 'Γιώργος Β.']);

    await tester.tap(find.text('Διάρκεια'));
    await tester.pump();
    expect(_callerOrder(tester), ['Γιώργος Β.', 'Βασίλης Α.', 'Άλφα Γ.']);
  });

  testWidgets('κουτάκι γραμμής επιλέγει την κλήση· της κεφαλίδας όλες', (
    tester,
  ) async {
    final container = await _pump(tester);
    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(4));

    await tester.tap(boxes.at(2));
    await tester.pump();
    expect(container.read(historySelectedCallIdsProvider), {2});

    await tester.tap(boxes.first);
    await tester.pump();
    expect(container.read(historySelectedCallIdsProvider), {1, 2, 3});

    await tester.tap(boxes.first);
    await tester.pump();
    expect(container.read(historySelectedCallIdsProvider), isEmpty);
  });

  testWidgets(
    'κλικ σε γραμμή δίνει τα πλήκτρα· ↓ πάει στην επόμενη και Space βάζει τικ',
    (tester) async {
      final container = await _pump(tester);

      await tester.tap(find.text('Δεν τυπώνει'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(
        container.read(historySelectedCallIdsProvider),
        {2},
        reason: 'Το ↓ από την κλήση 1 πάει στην 2, και το Space την τσεκάρει.',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(container.read(historySelectedCallIdsProvider), isEmpty);
    },
  );
}
