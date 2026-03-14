import 'package:call_logger/features/directory/models/equipment_column.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _FakeEquipmentDirectoryNotifier extends EquipmentDirectoryNotifier {
  _FakeEquipmentDirectoryNotifier({
    required this.initialState,
    this.equipmentRows = const [],
    this.userRows = const [],
  });

  final EquipmentDirectoryState initialState;
  final List<Map<String, dynamic>> equipmentRows;
  final List<Map<String, dynamic>> userRows;

  @override
  EquipmentDirectoryState build() => initialState;

  @override
  Future<List<Map<String, dynamic>>> getEquipmentRows() async => equipmentRows;

  @override
  Future<List<Map<String, dynamic>>> getUserRows() async => userRows;
}

void main() {
  group('EquipmentDirectoryNotifier', () {
    test('αρχικοποιείται με τις προεπιλεγμένες τιμές state', () {
      final container = ProviderContainer(
        overrides: [
          equipmentDirectoryProvider.overrideWith(
            () => _FakeEquipmentDirectoryNotifier(
              initialState: EquipmentDirectoryState(
                visibleColumns: List<EquipmentColumn>.from(EquipmentColumn.defaults),
                allColumns: EquipmentColumn.all,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(equipmentDirectoryProvider);
      expect(state.filteredItems, isEmpty);
      expect(state.visibleColumns, orderedEquals(EquipmentColumn.defaults));
      expect(state.allColumns, orderedEquals(EquipmentColumn.all));
      expect(state.searchQuery, '');
      expect(state.sortColumn, isNull);
      expect(state.sortAscending, isTrue);
    });

    test('updateVisibleColumns ενημερώνει πλήρως τη σειρά των στηλών', () {
      final container = ProviderContainer(
        overrides: [
          equipmentDirectoryProvider.overrideWith(
            () => _FakeEquipmentDirectoryNotifier(
              initialState: EquipmentDirectoryState(
                visibleColumns: List<EquipmentColumn>.from(EquipmentColumn.defaults),
                allColumns: EquipmentColumn.all,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(equipmentDirectoryProvider.notifier);
      notifier.updateVisibleColumns([
        EquipmentColumn.owner,
        EquipmentColumn.phone,
        EquipmentColumn.notes,
      ]);

      final state = container.read(equipmentDirectoryProvider);
      expect(
        state.visibleColumns,
        orderedEquals([
          EquipmentColumn.owner,
          EquipmentColumn.phone,
          EquipmentColumn.notes,
        ]),
      );
    });

    test('reorderColumn μετακινεί σωστά στήλη με Flutter index semantics', () {
      final initialVisible = [
        EquipmentColumn.code,
        EquipmentColumn.type,
        EquipmentColumn.owner,
        EquipmentColumn.customIp,
      ];
      final container = ProviderContainer(
        overrides: [
          equipmentDirectoryProvider.overrideWith(
            () => _FakeEquipmentDirectoryNotifier(
              initialState: EquipmentDirectoryState(
                visibleColumns: initialVisible,
                allColumns: EquipmentColumn.all,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(equipmentDirectoryProvider.notifier);
      notifier.reorderColumn(0, 3);

      final state = container.read(equipmentDirectoryProvider);
      expect(
        state.visibleColumns,
        orderedEquals([
          EquipmentColumn.type,
          EquipmentColumn.owner,
          EquipmentColumn.code,
          EquipmentColumn.customIp,
        ]),
      );
    });

    test('toggleColumn προσθέτει, αφαιρεί και επαναφέρει defaults όταν αδειάζει', () {
      final container = ProviderContainer(
        overrides: [
          equipmentDirectoryProvider.overrideWith(
            () => _FakeEquipmentDirectoryNotifier(
              initialState: EquipmentDirectoryState(
                visibleColumns: [EquipmentColumn.code],
                allColumns: EquipmentColumn.all,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(equipmentDirectoryProvider.notifier);

      notifier.toggleColumn(EquipmentColumn.phone);
      expect(
        container.read(equipmentDirectoryProvider).visibleColumns,
        orderedEquals([EquipmentColumn.code, EquipmentColumn.phone]),
      );

      notifier.toggleColumn(EquipmentColumn.phone);
      expect(
        container.read(equipmentDirectoryProvider).visibleColumns,
        orderedEquals([EquipmentColumn.code]),
      );

      notifier.toggleColumn(EquipmentColumn.code);
      expect(
        container.read(equipmentDirectoryProvider).visibleColumns,
        orderedEquals(EquipmentColumn.defaults),
      );
    });

    test('load συσχετίζει σωστά owner με user_id και διατηρεί null όταν λείπει', () async {
      final container = ProviderContainer(
        overrides: [
          equipmentDirectoryProvider.overrideWith(
            () => _FakeEquipmentDirectoryNotifier(
              initialState: EquipmentDirectoryState(
                visibleColumns: List<EquipmentColumn>.from(EquipmentColumn.defaults),
                allColumns: EquipmentColumn.all,
              ),
              equipmentRows: [
                {
                  'id': 1,
                  'code_equipment': 'PC-01',
                  'type': 'Desktop',
                  'user_id': 10,
                  'notes': 'Γραφείο',
                  'custom_ip': '10.0.0.10',
                  'anydesk_id': 'AD-001',
                  'default_remote_tool': 'AnyDesk',
                },
                {
                  'id': 2,
                  'code_equipment': 'PC-02',
                  'type': 'Laptop',
                  'user_id': null,
                },
              ],
              userRows: [
                {
                  'id': 10,
                  'first_name': 'Μαρία',
                  'last_name': 'Παπαδοπούλου',
                  'phone': '2100000000',
                  'location': '2ος',
                },
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(equipmentDirectoryProvider.notifier);
      await notifier.load();

      final state = container.read(equipmentDirectoryProvider);
      expect(state.filteredItems.length, 2);
      expect(state.filteredItems.first.$1.code, 'PC-01');
      expect(state.filteredItems.first.$2?.name, 'Μαρία Παπαδοπούλου');
      expect(state.filteredItems[1].$1.code, 'PC-02');
      expect(state.filteredItems[1].$2, isNull);
    });
  });
}
