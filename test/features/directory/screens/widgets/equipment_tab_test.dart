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
  testWidgets('EquipmentTab εμφανίζει chips για τις ορατές στήλες', (tester) async {
    final state = EquipmentDirectoryState(
      visibleColumns: [
        EquipmentColumn.code,
        EquipmentColumn.type,
        EquipmentColumn.owner,
      ],
      allColumns: EquipmentColumn.all,
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

  testWidgets('EquipmentTab αφαιρεί στήλη με delete και προσθέτει από popup', (tester) async {
    final state = EquipmentDirectoryState(
      visibleColumns: [
        EquipmentColumn.code,
        EquipmentColumn.type,
      ],
      allColumns: EquipmentColumn.all,
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

    // Προσθήκη "Σημειώσεις" από popup (δεύτερο Icons.add = μενού στήλων).
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Σημειώσεις').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'Σημειώσεις'), findsOneWidget);
  });

  testWidgets('EquipmentTab καλεί reorder και αλλάζει σειρά chips', (tester) async {
    final state = EquipmentDirectoryState(
      visibleColumns: [
        EquipmentColumn.code,
        EquipmentColumn.type,
        EquipmentColumn.owner,
      ],
      allColumns: EquipmentColumn.all,
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

    final newOrder = container.read(equipmentDirectoryProvider).visibleColumns;
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
