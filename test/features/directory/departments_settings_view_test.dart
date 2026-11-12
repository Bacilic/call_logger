// Η οθόνη «Διάφορα → Τμήματα» δείχνει ΔΥΟ ανεξάρτητους καταλόγους.
//
// Ανεξάρτητους στην κυριολεξία: όσο τα κτίρια φορτώνουν, η κάρτα των ομάδων
// μένει στη θέση της. Όταν ζούσε μέσα στην αναμονή των κτιρίων, κάθε
// ξαναφόρτωμα την κατέστρεφε ενώ οι παρατηρητές της την άκουγαν ακόμη.
//
//   flutter test test/features/directory/departments_settings_view_test.dart

import 'dart:async';

import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/services/settings_service_catalogs.dart';
import 'package:call_logger/features/directory/providers/building_catalog_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/departments_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpView(
    WidgetTester tester, {
    required Future<List<String>> buildings,
    List<String> groups = const ['Εργαστήρια'],
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          buildingCatalogProvider.overrideWith((ref) => buildings),
          buildingUsageProvider.overrideWith((ref) => BuildingUsage.empty),
          departmentGroupCatalogProvider.overrideWith((ref) async => groups),
          departmentGroupUsageProvider.overrideWith(
            (ref) async => DepartmentGroupUsage.empty,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: DepartmentsSettingsView()),
          ),
        ),
      ),
    );
  }

  testWidgets('οι δύο κάρτες εμφανίζονται μαζί', (tester) async {
    await pumpView(tester, buildings: Future.value(const ['Καινούριο']));
    await tester.pumpAndSettle();

    expect(find.text('Κτίρια'), findsOneWidget);
    expect(find.text('Ομάδες'), findsOneWidget);
    expect(find.text('Εργαστήρια'), findsOneWidget);
  });

  testWidgets('όσο τα κτίρια φορτώνουν, οι ομάδες μένουν στη θέση τους', (
    tester,
  ) async {
    final pending = Completer<List<String>>();
    await pumpView(tester, buildings: pending.future);
    await tester.pump();

    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'ο κατάλογος κτιρίων περιμένει',
    );
    expect(
      find.text('Ομάδες'),
      findsOneWidget,
      reason: 'η κάρτα ομάδων δεν εξαρτάται από τα κτίρια',
    );

    pending.complete(const ['Καινούριο']);
    await tester.pumpAndSettle();

    expect(find.text('Ομάδες'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Κάθε προσθήκη ομάδας ακυρώνει τον κατάλογο για να τον ξαναδιαβάσει. Αν η
  // κάρτα έχανε τη λίστα σε κάθε ανανέωση, το δέντρο από κάτω της θα άλλαζε
  // σχήμα τη στιγμή που ο διάλογος κλείνει.
  testWidgets('η λίστα ομάδων κρατιέται όσο ο κατάλογος ανανεώνεται', (
    tester,
  ) async {
    var round = 0;
    final container = ProviderContainer(
      overrides: [
        buildingCatalogProvider.overrideWith(
          (ref) async => const ['Καινούριο'],
        ),
        buildingUsageProvider.overrideWith((ref) => BuildingUsage.empty),
        departmentGroupCatalogProvider.overrideWith((ref) async {
          round++;
          if (round > 1) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          return const <String>['Εργαστήρια'];
        }),
        departmentGroupUsageProvider.overrideWith(
          (ref) async => DepartmentGroupUsage.empty,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: DepartmentsSettingsView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Εργαστήρια'), findsOneWidget);

    container.invalidate(departmentGroupCatalogProvider);
    await tester.pump();

    expect(
      find.text('Εργαστήρια'),
      findsOneWidget,
      reason: 'η κάρτα κρατά την τελευταία γνωστή λίστα αντί να εξαφανιστεί',
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // Η λίστα της οθόνης διαβάστηκε ΠΡΙΝ προσθέσει κάτι ο συνάδελφος. Η δική μου
  // αλλαγή δεν επιτρέπεται να σβήσει τη δική του — ούτε σιωπηλά, ούτε καθόλου.
  group('αλλαγή πάνω σε λίστα που πρόλαβε να αλλάξει ο συνάδελφος', () {
    late Map<String, String> stored;

    setUp(() {
      stored = <String, String>{};
      SettingsService.registerAppSettingsProvider(
        (key) async => stored[key],
        (key, value) async => stored[key] = value,
        (key, change) async => stored[key] = change(stored[key]),
      );
    });

    Future<void> pumpLiveView(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            buildingUsageProvider.overrideWith((ref) => BuildingUsage.empty),
            departmentGroupUsageProvider.overrideWith(
              (ref) async => DepartmentGroupUsage.empty,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: DepartmentsSettingsView()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> addThroughDialog(
      WidgetTester tester, {
      required Finder addButton,
      required String name,
    }) async {
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), name);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('προσθήκη κτιρίου κρατά το κτίριο του συναδέλφου', (
      tester,
    ) async {
      stored['building_catalog'] = 'Κτίριο Α';
      await pumpLiveView(tester);
      expect(find.text('Κτίριο Α'), findsOneWidget);

      stored['building_catalog'] = 'Κτίριο Α, Νέα Πτέρυγα';

      await addThroughDialog(
        tester,
        addButton: find.text('Προσθήκη').first,
        name: 'Κτίριο Β',
      );

      expect(
        SettingsServiceCatalogs.splitBuildingCatalog(
          stored['building_catalog'],
        ),
        unorderedEquals(['Κτίριο Α', 'Κτίριο Β', 'Νέα Πτέρυγα']),
      );
      expect(find.text('Νέα Πτέρυγα'), findsOneWidget);
    });

    testWidgets('προσθήκη ομάδας κρατά την ομάδα του συναδέλφου', (
      tester,
    ) async {
      stored['department_group_catalog'] = 'Εργαστήρια';
      await pumpLiveView(tester);
      expect(find.text('Εργαστήρια'), findsOneWidget);

      stored['department_group_catalog'] = 'Εργαστήρια, Κλινικές';

      await addThroughDialog(
        tester,
        addButton: find.text('Προσθήκη').last,
        name: 'Διοίκηση',
      );

      expect(
        SettingsServiceCatalogs.splitDepartmentGroupCatalog(
          stored['department_group_catalog'],
        ),
        unorderedEquals(['Διοίκηση', 'Εργαστήρια', 'Κλινικές']),
      );
      expect(find.text('Κλινικές'), findsOneWidget);
    });

    // Ο συνάδελφος έσβησε το ίδιο κτίριο που πάω να σβήσω: η λίστα του μένει
    // όπως την άφησε, και η οθόνη το λέει αντί να δηλώσει «Διαγράφηκε».
    testWidgets('διαγραφή κτιρίου που έσβησε ήδη ο συνάδελφος δεν γράφει '
        'τίποτα και το λέει', (tester) async {
      stored['building_catalog'] = 'Κτίριο Α, Κτίριο Β';
      await pumpLiveView(tester);

      stored['building_catalog'] = 'Κτίριο Β, Νέα Πτέρυγα';

      await tester.tap(find.byTooltip('Διαγραφή').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Διαγραφή'));
      await tester.pumpAndSettle();

      expect(stored['building_catalog'], 'Κτίριο Β, Νέα Πτέρυγα');
      expect(find.textContaining('δεν υπάρχει πια'), findsOneWidget);
      expect(find.textContaining('Διαγράφηκε'), findsNothing);
      expect(
        find.text('Νέα Πτέρυγα'),
        findsOneWidget,
        reason: 'η οθόνη δείχνει πλέον τη λίστα όπως είναι στη βάση',
      );
    });
  });
}
