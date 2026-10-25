// Πλήκτρα στους πίνακες καταλόγου (Υπάλληλοι, Τμήματα, Εξοπλισμός).
//
// Συμπεριφορά που φυλάγεται: ένα κλικ σε γραμμή δίνει στον πίνακα τα πλήκτρα
// (ακόμη κι αν το πληκτρολόγιο ήταν στην Αναζήτηση), τα βέλη μετακινούν τη
// γραμμή με εστίαση, η σελίδα/κύλιση την ακολουθεί, και Space/Enter/Delete
// δουλεύουν πάνω στη γραμμή με εστίαση.
//
//   flutter test test/features/directory/screens/widgets/catalog_tables_keyboard_test.dart

import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/category_directory_column.dart';
import 'package:call_logger/features/directory/models/category_model.dart';
import 'package:call_logger/features/directory/models/department_directory_column.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/models/equipment_column.dart';
import 'package:call_logger/features/directory/models/user_directory_column.dart';
import 'package:call_logger/features/directory/screens/widgets/catalog_table_chrome.dart';
import 'package:call_logger/features/directory/screens/widgets/categories_data_table.dart';
import 'package:call_logger/features/directory/screens/widgets/departments_data_table.dart';
import 'package:call_logger/features/directory/screens/widgets/equipment_data_table.dart';
import 'package:call_logger/features/directory/screens/widgets/users_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _rows = 40;

class _Host extends StatefulWidget {
  const _Host({required this.builder});

  final Widget Function(_HostState host) builder;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int? focused;
  final Set<int> selected = {};
  final List<String> log = [];

  void setFocus(int? i) => setState(() => focused = i);

  void toggle(int id) => setState(() {
    if (!selected.remove(id)) selected.add(id);
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const TextField(key: Key('search')),
            Expanded(child: widget.builder(this)),
          ],
        ),
      ),
    );
  }
}

class _Kind {
  const _Kind(
    this.name,
    this.tableType,
    this.table,
    this.rowText,
    this.editLog, {
    this.hasPages = true,
  });

  final String name;
  final Type tableType;
  final Widget Function(_HostState h, {required bool continuous}) table;
  final String Function(int id) rowText;
  final String Function(int id) editLog;

  /// Οι κατηγορίες δεν έχουν σελίδες, μόνο κύλιση.
  final bool hasPages;
}

final _kinds = <_Kind>[
  _Kind(
    'Υπάλληλοι',
    UsersDataTable,
    (h, {required continuous}) => UsersDataTable(
      users: [
        for (var i = 1; i <= _rows; i++)
          UserModel(id: i, firstName: 'Όνομα', lastName: 'Επώνυμο$i'),
      ],
      selectedIds: h.selected,
      sortColumn: null,
      sortAscending: true,
      visibleColumns: const [
        UserDirectoryColumn.selection,
        UserDirectoryColumn.id,
        UserDirectoryColumn.lastName,
      ],
      onToggleSelection: h.toggle,
      onSetSort: (_, _) {},
      onEditUser: (u, {focusedField}) => h.log.add('edit ${u.id}'),
      focusedRowIndex: h.focused,
      onSetFocusedRowIndex: h.setFocus,
      onRequestDelete: () => h.log.add('delete'),
      onRequestBulkEdit: () => h.log.add('bulk'),
      continuousScroll: continuous,
    ),
    (id) => 'Επώνυμο$id',
    (id) => 'edit $id',
  ),
  _Kind(
    'Τμήματα',
    DepartmentsDataTable,
    (h, {required continuous}) => DepartmentsDataTable(
      departments: [
        for (var i = 1; i <= _rows; i++)
          DepartmentModel(id: i, name: 'Τμήμα $i'),
      ],
      selectedIds: h.selected,
      sortColumn: null,
      sortAscending: true,
      visibleColumns: const [
        DepartmentDirectoryColumn.selection,
        DepartmentDirectoryColumn.id,
        DepartmentDirectoryColumn.name,
      ],
      onToggleSelection: h.toggle,
      onSetSort: (_, _) {},
      onEditDepartment: (d, {focusedField}) => h.log.add('edit ${d.id}'),
      focusedRowIndex: h.focused,
      onSetFocusedRowIndex: h.setFocus,
      onRequestDelete: () => h.log.add('delete'),
      onRequestBulkEdit: () => h.log.add('bulk'),
      continuousScroll: continuous,
    ),
    (id) => 'Τμήμα $id',
    (id) => 'edit $id',
  ),
  _Kind(
    'Εξοπλισμός',
    EquipmentDataTable,
    (h, {required continuous}) => EquipmentDataTable(
      items: [
        for (var i = 1; i <= _rows; i++)
          (EquipmentModel(id: i, code: 'PC-$i', type: 'Desktop'), null),
      ],
      selectedIds: h.selected,
      sortColumn: null,
      sortAscending: true,
      visibleColumns: [EquipmentColumn.selection, EquipmentColumn.code],
      onToggleSelection: h.toggle,
      onSetSort: (_, _) {},
      onEditEquipment: (row, {focusedField}) => h.log.add('edit ${row.$1.id}'),
      focusedRowIndex: h.focused,
      onSetFocusedRowIndex: h.setFocus,
      onRequestDelete: () => h.log.add('delete'),
      onRequestBulkEdit: () => h.log.add('bulk'),
      continuousScroll: continuous,
    ),
    (id) => 'PC-$id',
    (id) => 'edit $id',
  ),
  _Kind(
    'Κατηγορίες',
    CategoriesDataTable,
    (h, {required continuous}) => CategoriesDataTable(
      categories: [
        for (var i = 1; i <= _rows; i++)
          CategoryModel(id: i, name: 'Κατηγορία $i'),
      ],
      selectedIds: h.selected,
      sortColumn: null,
      sortAscending: true,
      visibleColumns: const [
        CategoryDirectoryColumn.selection,
        CategoryDirectoryColumn.id,
        CategoryDirectoryColumn.name,
      ],
      onToggleSelection: h.toggle,
      onSetSort: (_, _) {},
      onEditCategory: (c, {focusedField}) => h.log.add('edit ${c.id}'),
      focusedRowIndex: h.focused,
      onSetFocusedRowIndex: h.setFocus,
      onRequestDelete: () => h.log.add('delete'),
      onRequestBulkEdit: () => h.log.add('bulk'),
    ),
    (id) => 'Κατηγορία $id',
    (id) => 'edit $id',
    hasPages: false,
  ),
];

Future<_HostState> _pump(
  WidgetTester t,
  _Kind kind, {
  required bool continuous,
}) async {
  // Με σελίδες, και οι 15 γραμμές πρέπει να χωρούν στην οθόνη του τεστ.
  await t.binding.setSurfaceSize(Size(1000, continuous ? 640 : 1100));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    _Host(builder: (h) => kind.table(h, continuous: continuous)),
  );
  await t.pumpAndSettle();
  return t.state<_HostState>(find.byType(_Host));
}

/// Κλικ με ποντίκι σε γραμμή. Η αναμονή καλύπτει τον χρόνο που περιμένει το
/// Flutter για να ξεχωρίσει το απλό κλικ από το διπλό.
Future<void> _clickRow(WidgetTester t, _Kind kind, int id) async {
  await t.tap(find.text(kind.rowText(id)));
  await t.pump(const Duration(milliseconds: 400));
  await t.pumpAndSettle();
}

Future<void> _press(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pumpAndSettle();
}

void main() {
  for (final kind in _kinds) {
    group(kind.name, () {
      testWidgets('κλικ σε γραμμή δίνει τα βέλη στον πίνακα, ακόμη κι αν το '
          'πληκτρολόγιο ήταν στην Αναζήτηση', (t) async {
        final h = await _pump(t, kind, continuous: true);
        await t.tap(find.byKey(const Key('search')));
        await t.pumpAndSettle();

        await _clickRow(t, kind, 5);
        expect(h.focused, 4);

        await _press(t, LogicalKeyboardKey.arrowDown);
        expect(h.focused, 5);
        await _press(t, LogicalKeyboardKey.arrowUp);
        await _press(t, LogicalKeyboardKey.arrowUp);
        expect(h.focused, 3);
      });

      testWidgets('η γραμμή μαρκάρεται ΑΜΕΣΩΣ στο κλικ, χωρίς να περιμένει το '
          'διπλό κλικ', (t) async {
        final h = await _pump(t, kind, continuous: true);

        await t.tap(find.text(kind.rowText(5)));
        await t.pump(const Duration(milliseconds: 30));

        expect(h.focused, 4);
        await t.pumpAndSettle(const Duration(seconds: 1));
      });

      testWidgets('το διπλό κλικ ανοίγει ακόμη τη φόρμα', (t) async {
        final h = await _pump(t, kind, continuous: true);

        await t.tap(find.text(kind.rowText(5)));
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(find.text(kind.rowText(5)));
        await t.pumpAndSettle(const Duration(seconds: 1));

        expect(h.log, [kind.editLog(5)]);
      });

      testWidgets('δεξί και αριστερό βέλος δεν βγάζουν το πληκτρολόγιο από τον '
          'πίνακα', (t) async {
        final h = await _pump(t, kind, continuous: true);
        await _clickRow(t, kind, 5);

        await _press(t, LogicalKeyboardKey.arrowRight);
        await _press(t, LogicalKeyboardKey.arrowLeft);
        await _press(t, LogicalKeyboardKey.arrowDown);

        expect(h.focused, 5, reason: 'ο πίνακας ακούει ακόμη τα πλήκτρα');
      });

      if (kind.hasPages) {
        testWidgets(
          'σε σελίδες: από το 15ο, το κάτω βέλος αλλάζει σελίδα και το '
          'πάνω βέλος την επιστρέφει',
          (t) async {
            final h = await _pump(t, kind, continuous: false);
            await _clickRow(t, kind, 15);
            expect(find.text('1–15 από $_rows'), findsOneWidget);

            await _press(t, LogicalKeyboardKey.arrowDown);
            expect(h.focused, 15);
            expect(find.text('16–30 από $_rows'), findsOneWidget);

            await _press(t, LogicalKeyboardKey.arrowUp);
            expect(h.focused, 14);
            expect(find.text('1–15 από $_rows'), findsOneWidget);
          },
        );

        testWidgets('σε σελίδες: το Page Down πηγαίνει μια σελίδα μπροστά', (
          t,
        ) async {
          final h = await _pump(t, kind, continuous: false);
          await _clickRow(t, kind, 3);

          await _press(t, LogicalKeyboardKey.pageDown);

          expect(h.focused, 17);
          expect(find.text('16–30 από $_rows'), findsOneWidget);
        });
      }

      testWidgets(
        'σε συνεχή κύλιση: η οθόνη ακολουθεί τη γραμμή που κατεβαίνει '
        'και ανεβαίνει',
        (t) async {
          final h = await _pump(t, kind, continuous: true);
          final tableRect = t.getRect(find.byType(kind.tableType));
          await _clickRow(t, kind, 3);

          for (var i = 0; i < 25; i++) {
            await _press(t, LogicalKeyboardKey.arrowDown);
          }
          expect(h.focused, 27);
          final down = t.getRect(find.text(kind.rowText(28)));
          expect(
            down.bottom <= tableRect.bottom && down.top >= tableRect.top,
            isTrue,
            reason: 'η γραμμή 28 πρέπει να φαίνεται μέσα στον πίνακα',
          );

          for (var i = 0; i < 25; i++) {
            await _press(t, LogicalKeyboardKey.arrowUp);
          }
          expect(h.focused, 2);
          final up = t.getRect(find.text(kind.rowText(3)));
          expect(
            up.bottom <= tableRect.bottom && up.top >= tableRect.top,
            isTrue,
            reason: 'η γραμμή 3 πρέπει να φαίνεται μέσα στον πίνακα',
          );
        },
      );

      testWidgets('Space βάζει και βγάζει το τικ στη γραμμή με εστίαση', (
        t,
      ) async {
        final h = await _pump(t, kind, continuous: true);
        await _clickRow(t, kind, 5);

        await _press(t, LogicalKeyboardKey.space);
        expect(h.selected, {5});
        await _press(t, LogicalKeyboardKey.space);
        expect(h.selected, isEmpty);
        expect(h.log, isEmpty, reason: 'το Space δεν ανοίγει φόρμα');
      });

      testWidgets('Enter ανοίγει τη γραμμή με εστίαση· με δύο τικ ανοίγει τη '
          'μαζική επεξεργασία', (t) async {
        final h = await _pump(t, kind, continuous: true);
        await _clickRow(t, kind, 5);

        await _press(t, LogicalKeyboardKey.enter);
        expect(h.log, [kind.editLog(5)]);

        h.selected.addAll({1, 2});
        await _press(t, LogicalKeyboardKey.enter);
        expect(h.log.last, 'bulk');
      });

      testWidgets('Delete χωρίς τικ βάζει τικ στη γραμμή με εστίαση και ζητά '
          'τη διαγραφή', (t) async {
        final h = await _pump(t, kind, continuous: true);
        await _clickRow(t, kind, 5);

        await _press(t, LogicalKeyboardKey.delete);

        expect(h.selected, {5});
        expect(h.log, ['delete']);
      });

      testWidgets('Delete με υπάρχοντα τικ διαγράφει αυτά και δεν προσθέτει '
          'τη γραμμή με εστίαση', (t) async {
        final h = await _pump(t, kind, continuous: true);
        h.selected.add(2);
        await _clickRow(t, kind, 5);

        await _press(t, LogicalKeyboardKey.delete);

        expect(h.selected, {2});
        expect(h.log, ['delete']);
      });

      if (kind.hasPages) {
        testWidgets('τα κουμπιά σελίδων πηγαίνουν μπρος, στο τέλος και πίσω', (
          t,
        ) async {
          await _pump(t, kind, continuous: false);

          Future<void> tapPager(String tooltip) async {
            await t.tap(find.byTooltip(tooltip));
            await t.pumpAndSettle();
          }

          await tapPager('Επόμενη');
          expect(find.text('16–30 από $_rows'), findsOneWidget);
          await tapPager('Τελευταία σελίδα');
          expect(find.text('31–40 από $_rows'), findsOneWidget);
          await tapPager('Προηγούμενη');
          expect(find.text('16–30 από $_rows'), findsOneWidget);
          await tapPager('Πρώτη σελίδα');
          expect(find.text('1–15 από $_rows'), findsOneWidget);
        });
      }

      testWidgets('το τράβηγμα της λαβής φαρδαίνει τη στήλη', (t) async {
        await _pump(t, kind, continuous: true);
        // Τραβάμε την προτελευταία λαβή· η τελευταία πρέπει να πάει δεξιά.
        final handles = find.byType(CatalogColumnResizeHandle);
        final count = handles.evaluate().length;
        final before = t.getCenter(handles.at(count - 1)).dx;

        await t.drag(handles.at(count - 2), const Offset(60, 0));
        await t.pumpAndSettle();

        expect(t.getCenter(handles.at(count - 1)).dx, greaterThan(before + 10));
      });

      testWidgets('το Backspace δεν διαγράφει τίποτα', (t) async {
        final h = await _pump(t, kind, continuous: true);
        h.selected.add(2);
        await _clickRow(t, kind, 5);

        await _press(t, LogicalKeyboardKey.backspace);

        expect(h.log, isEmpty);
        expect(h.selected, {2});
      });
    });
  }
}
