// Το παράθυρο «Είδη αντικειμένων» με το ποντίκι: νέο είδος → γράφεται στη
// βάση, ίδιο όνομα → μήνυμα, είδος με αντικείμενα → δεν αφαιρείται.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_object_kinds_dialog_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/floor_plan_objects_repository.dart';
import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_object_kinds_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_setup.dart';

void main() {
  late Database db;
  late FloorPlanObjectsRepository repo;

  setUp(() async {
    initSqfliteFfiForTests();
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await migrateDatabaseToV71(db);
    repo = FloorPlanObjectsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Αφήνει τη βάση να απαντήσει και την οθόνη να ηρεμήσει. Τρεις γύροι: η
  /// αποθήκευση, το κλείσιμο της φόρμας και η ανανέωση της λίστας είναι
  /// διαδοχικές αναμονές.
  ///
  /// Με [until], συνεχίζει ώσπου να εμφανιστεί ό,τι περιμένει το τεστ (ως 50
  /// γύρους): στην πλήρη σουίτα η βάση απαντά αργότερα από ό,τι μόνη της.
  Future<void> settle(WidgetTester tester, {Finder? until}) async {
    for (var i = 0; i < (until == null ? 3 : 50); i++) {
      if (until != null && i >= 3 && until.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloorPlanObjectKindsDialog(
            repository: repo,
            floorLabel: (id) => id == 1 ? 'Ισόγειο' : '1ος',
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> fillNewKind(WidgetTester tester, String name) async {
    await tester.tap(find.text('Νέο είδος'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Όνομα'), name);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Εκτυπωτής'));
    await tester.pump();
    await tester.tap(find.text('Αποθήκευση'));
    await settle(tester);
  }

  testWidgets('νέο είδος γράφεται στη βάση και εμφανίζεται στη λίστα', (
    tester,
  ) async {
    await pumpDialog(tester);
    expect(find.textContaining('Δεν υπάρχει ακόμη κανένα είδος'), findsOne);

    await tester.tap(find.text('Νέο είδος'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Όνομα'),
      'Εκτυπωτής δικτύου',
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Εκτυπωτής'));
    await tester.tap(find.text('Έχει θύρες (συνδέεται με καλώδιο)'));
    await tester.pump();
    await tester.tap(find.text('Αποθήκευση'));
    await settle(tester, until: find.text('Εκτυπωτής δικτύου'));

    expect(find.text('Εκτυπωτής δικτύου'), findsOne);
    final kinds = await tester.runAsync(repo.listKinds);
    expect(kinds!.single.kind.symbol, FloorPlanSymbol.printer);
    expect(kinds.single.kind.hasPorts, isTrue);
  });

  testWidgets('χωρίς σύμβολο η φόρμα δεν αποθηκεύει', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Νέο είδος'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Όνομα'), 'Γραφείο');
    await tester.tap(find.text('Αποθήκευση'));
    await settle(tester);

    expect(find.text('Διαλέξτε σύμβολο.'), findsOne);
    expect(await tester.runAsync(repo.listKinds), isEmpty);
  });

  testWidgets('ίδιο όνομα με άλλα κεφαλαία: μήνυμα, και δεύτερο είδος δεν '
      'γράφεται', (tester) async {
    await pumpDialog(tester);
    await fillNewKind(tester, 'Εκτυπωτής');

    await fillNewKind(tester, 'ΕΚΤΥΠΩΤΗΣ');

    expect(find.text('Υπάρχει ήδη είδος με αυτό το όνομα.'), findsOne);
    expect(await tester.runAsync(repo.listKinds), hasLength(1));
  });

  testWidgets('είδος με αντικείμενα δεν αφαιρείται, και το παράθυρο λέει πού '
      'είναι', (tester) async {
    await tester.runAsync(() async {
      await repo.addKind(
        name: 'Εκτυπωτής',
        symbol: FloorPlanSymbol.printer,
        hasPorts: false,
      );
      final id = (await repo.listKinds()).single.kind.id;
      await db.insert('building_map_objects', {
        'kind_id': id,
        'floor_id': 1,
        'x': 0,
        'y': 0,
      });
    });
    await pumpDialog(tester);

    await tester.tap(find.byTooltip('Αφαίρεση'));
    await settle(tester);

    expect(find.text('Το είδος δεν αφαιρείται'), findsOne);
    expect(find.textContaining('1 αντικείμενο (Ισόγειο)'), findsWidgets);
    expect(await tester.runAsync(repo.listKinds), hasLength(1));
  });

  testWidgets('είδος χωρίς αντικείμενα αφαιρείται μετά από επιβεβαίωση', (
    tester,
  ) async {
    await tester.runAsync(
      () => repo.addKind(
        name: 'Γραφείο',
        symbol: FloorPlanSymbol.furniture,
        hasPorts: false,
      ),
    );
    await pumpDialog(tester);

    await tester.tap(find.byTooltip('Αφαίρεση'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Αφαίρεση'));
    await settle(tester);

    expect(find.text('Γραφείο'), findsNothing);
    expect(await tester.runAsync(repo.listKinds), isEmpty);
  });

  testWidgets('«Δείχνει πληροφορίες» κλειστό: το είδος γράφεται χωρίς '
      'πληροφορίες', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Νέο είδος'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Όνομα'), 'Γραφείο');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Έπιπλο'));
    // Με όλα τα σύμβολα το παράθυρο κυλά ως το κουτάκι.
    await tester.ensureVisible(find.text('Δείχνει πληροφορίες με το ποντίκι'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Δείχνει πληροφορίες με το ποντίκι'));
    await tester.pump();
    await tester.tap(find.text('Αποθήκευση'));
    await settle(tester, until: find.textContaining('χωρίς πληροφορίες'));

    expect(find.textContaining('χωρίς πληροφορίες'), findsOne);
    final kinds = await tester.runAsync(repo.listKinds);
    expect(kinds!.single.kind.showInfo, isFalse);
  });
}
