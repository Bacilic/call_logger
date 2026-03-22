// Widget tests: EquipmentTab — chips ορατών στηλών, αφαίρεση/προσθήκη, reorder.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/equipment_tab_test.dart

import 'package:call_logger/features/directory/models/equipment_column.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/equipment_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEquipmentDirectoryNotifier extends EquipmentDirectoryNotifier {
  _FakeEquipmentDirectoryNotifier(this._initialState);

  final EquipmentDirectoryState _initialState;

  @override
  EquipmentDirectoryState build() => _initialState;

  @override
  Future<void> load() async {}
}

void main() {
  // Fake provider state: εμφάνιση Chip ανά στήλη + ReorderableListView.
  //   flutter test test/features/directory/screens/widgets/equipment_tab_test.dart --plain-name "EquipmentTab εμφανίζει chips για τις ορατές στήλες"
  testWidgets('EquipmentTab εμφανίζει chips για τις ορατές στήλες', (tester) async {
    final state = EquipmentDirectoryState(
      visibleColumnKeys: {
        EquipmentColumn.code.key,
        EquipmentColumn.type.key,
        EquipmentColumn.owner.key,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equipmentDirectoryProvider.overrideWith(
            () => _FakeEquipmentDirectoryNotifier(state),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: EquipmentTab())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'Κωδικός'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Τύπος'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Κάτοχος'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
  });

  // Διαγραφή chip «Τύπος», προσθήκη «Τοποθεσία» από μενού στηλών (κοντά στην κορυφή της λίστας).
  //   flutter test test/features/directory/screens/widgets/equipment_tab_test.dart --plain-name "EquipmentTab αφαιρεί στήλη με delete και προσθέτει από popup"
  testWidgets('EquipmentTab αφαιρεί στήλη με delete και προσθέτει από popup', (tester) async {
    final state = EquipmentDirectoryState(
      visibleColumnKeys: {
        EquipmentColumn.code.key,
        EquipmentColumn.type.key,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equipmentDirectoryProvider.overrideWith(
            () => _FakeEquipmentDirectoryNotifier(state),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: EquipmentTab())),
      ),
    );
    await tester.pumpAndSettle();

    // Αφαίρεση της στήλης "Τύπος" από το chip delete.
    final typeChip = find.widgetWithText(Chip, 'Τύπος');
    expect(typeChip, findsOneWidget);
    final typeDeleteIcon = find.descendant(
      of: typeChip,
      matching: find.byIcon(Icons.close),
    );
    expect(typeDeleteIcon, findsOneWidget);
    await tester.tap(typeDeleteIcon);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, 'Τύπος'), findsNothing);

    // Προσθήκη "Σημειώσεις" από popup στηλών (όχι το FilledButton «Προσθήκη»).
    await tester.tap(
      find.byTooltip('Προσθήκη / αφαίρεση στηλών'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Τοποθεσία'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'Τοποθεσία'), findsOneWidget);
  });

  // Άμεση κλήση onReorder(0,2) — ενημέρωση σειράς ορατών στη columnOrder.
  //   flutter test test/features/directory/screens/widgets/equipment_tab_test.dart --plain-name "EquipmentTab καλεί reorder και αλλάζει σειρά chips"
  testWidgets('EquipmentTab καλεί reorder και αλλάζει σειρά chips', (tester) async {
    final state = EquipmentDirectoryState(
      visibleColumnKeys: {
        EquipmentColumn.code.key,
        EquipmentColumn.type.key,
        EquipmentColumn.owner.key,
      },
    );

    final container = ProviderContainer(
      overrides: [
        equipmentDirectoryProvider.overrideWith(
          () => _FakeEquipmentDirectoryNotifier(state),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EquipmentTab())),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    list.onReorder(0, 2);
    await tester.pumpAndSettle();

    final newOrder =
        container.read(equipmentDirectoryProvider).orderedVisibleColumns;
    expect(
      newOrder,
      orderedEquals([
        EquipmentColumn.type,
        EquipmentColumn.code,
        EquipmentColumn.owner,
      ]),
    );
  });
}
