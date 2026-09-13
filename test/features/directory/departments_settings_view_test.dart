// Η οθόνη «Διάφορα → Τμήματα» δείχνει ΔΥΟ ανεξάρτητους καταλόγους.
//
// Ανεξάρτητους στην κυριολεξία: όσο τα κτίρια φορτώνουν, η κάρτα των ομάδων
// μένει στη θέση της. Όταν ζούσε μέσα στην αναμονή των κτιρίων, κάθε
// ξαναφόρτωμα την κατέστρεφε ενώ οι παρατηρητές της την άκουγαν ακόμη.
//
//   flutter test test/features/directory/departments_settings_view_test.dart

import 'dart:async';

import 'package:call_logger/core/database/department_repository.dart';
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
}
