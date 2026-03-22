// Unit tests: EquipmentDirectoryNotifier — αρχική κατάσταση, στήλες, reorder, toggle, load + join users.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/providers/equipment_directory_provider_test.dart
// Ομάδα:
//   flutter test test/features/directory/providers/equipment_directory_provider_test.dart --plain-name "EquipmentDirectoryNotifier"

import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/equipment_column.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _FakeEquipmentDirectoryNotifier extends EquipmentDirectoryNotifier {
  _FakeEquipmentDirectoryNotifier({
    required this.initialState,
    this.equipmentRows = const [],
    this.userRows = const [],
    this.linkRows = const [],
  });

  @override
  bool get shouldPersistEquipmentLayout => false;

  final EquipmentDirectoryState initialState;
  final List<Map<String, dynamic>> equipmentRows;
  final List<Map<String, dynamic>> userRows;
  final List<Map<String, dynamic>> linkRows;

  @override
  EquipmentDirectoryState build() => initialState;

  @override
  Future<List<Map<String, dynamic>>> getEquipmentRows() async => equipmentRows;

  @override
  Future<List<Map<String, dynamic>>> getUserRows() async => userRows;

  @override
  Future<void> load() async {
    final usersMap = <int, UserModel>{};
    for (final map in userRows) {
      final u = UserModel.fromMap(map);
      if (u.id != null) usersMap[u.id!] = u;
    }

    final equipmentIdToUserIds = <int, List<int>>{};
    for (final row in linkRows) {
      final uid = row['user_id'] as int?;
      final eid = row['equipment_id'] as int?;
      if (uid == null || eid == null) continue;
      equipmentIdToUserIds.putIfAbsent(eid, () => []).add(uid);
    }
    for (final list in equipmentIdToUserIds.values) {
      list.sort();
    }

    final items = <(EquipmentModel, UserModel?)>[];
    for (final eq in equipmentRows) {
      final equipment = EquipmentModel.fromMap(eq);
      final eid = equipment.id;
      UserModel? owner;
      if (eid != null) {
        final uids = equipmentIdToUserIds[eid];
        if (uids != null && uids.isNotEmpty) {
          owner = usersMap[uids.first];
        }
      }
      items.add((equipment, owner));
    }

    state = state.copyWith(allItems: items);
    filterAndSort();
  }
}

void main() {
  group('EquipmentDirectoryNotifier', () {
    // Κενά filteredItems, defaults στήλες, κενό query, null sort.
    //   flutter test test/features/directory/providers/equipment_directory_provider_test.dart --plain-name "αρχικοποιείται με τις προεπιλεγμένες τιμές state"
    test('αρχικοποιείται με τις προεπιλεγμένες τιμές state', () {
      final container = ProviderContainer(
        overrides: [
          equipmentDirectoryProvider.overrideWith(
            () => _FakeEquipmentDirectoryNotifier(
              initialState: EquipmentDirectoryState(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(equipmentDirectoryProvider);
      expect(state.filteredItems, isEmpty);
      expect(
        state.orderedVisibleColumns,
        orderedEquals(EquipmentColumn.defaults),
      );
      expect(state.columnOrder, orderedEquals(EquipmentColumn.all));
      expect(state.searchQuery, '');
      expect(state.sortColumn, isNull);
      expect(state.sortAscending, isTrue);
    });

    // Αντικατάσταση λίστας ορατών στηλών με νέα σειρά.
    //   flutter test test/features/directory/providers/equipment_directory_provider_test.dart --plain-name "updateVisibleColumns ενημερώνει πλήρως τη σειρά των στηλών"
    test('updateVisibleColumns ενημερώνει πλήρως τη σειρά των στηλών', () {
      final container = ProviderContainer(
        overrides: [
          equipmentDirectoryProvider.overrideWith(
            () => _FakeEquipmentDirectoryNotifier(
              initialState: EquipmentDirectoryState(),
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
        state.orderedVisibleColumns,
        orderedEquals([
          EquipmentColumn.owner,
          EquipmentColumn.phone,
          EquipmentColumn.notes,
        ]),
      );
    });

    // reorderColumn(0, 3) — συμβατό με ReorderableListView indices.
    //   flutter test test/features/directory/providers/equipment_directory_provider_test.dart --plain-name "reorderColumn μετακινεί σωστά στήλη με Flutter index semantics"
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
                visibleColumnKeys: {
                  for (final c in initialVisible) c.key,
                },
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
        state.orderedVisibleColumns,
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
                visibleColumnKeys: {EquipmentColumn.code.key},
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(equipmentDirectoryProvider.notifier);

      notifier.toggleColumn(EquipmentColumn.phone);
      expect(
        container.read(equipmentDirectoryProvider).orderedVisibleColumns,
        orderedEquals([EquipmentColumn.code, EquipmentColumn.phone]),
      );

      notifier.toggleColumn(EquipmentColumn.phone);
      expect(
        container.read(equipmentDirectoryProvider).orderedVisibleColumns,
        orderedEquals([EquipmentColumn.code]),
      );

      notifier.toggleColumn(EquipmentColumn.code);
      expect(
        container.read(equipmentDirectoryProvider).orderedVisibleColumns,
        orderedEquals(EquipmentColumn.defaults),
      );
    });

    // load(): join εξοπλισμού με χρήστες από `user_equipment` + userRows· null owner χωρίς σύνδεση.
    //   flutter test test/features/directory/providers/equipment_directory_provider_test.dart --plain-name "load συσχετίζει σωστά owner μέσω user_equipment και διατηρεί null όταν λείπει"
    test('load συσχετίζει σωστά owner μέσω user_equipment και διατηρεί null όταν λείπει', () async {
      final container = ProviderContainer(
        overrides: [
          equipmentDirectoryProvider.overrideWith(
            () => _FakeEquipmentDirectoryNotifier(
              initialState: EquipmentDirectoryState(),
              equipmentRows: [
                {
                  'id': 1,
                  'code_equipment': 'PC-01',
                  'type': 'Desktop',
                  'notes': 'Γραφείο',
                  'custom_ip': '10.0.0.10',
                  'anydesk_id': 'AD-001',
                  'default_remote_tool': 'AnyDesk',
                },
                {
                  'id': 2,
                  'code_equipment': 'PC-02',
                  'type': 'Laptop',
                },
              ],
              linkRows: [
                {'user_id': 10, 'equipment_id': 1},
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
