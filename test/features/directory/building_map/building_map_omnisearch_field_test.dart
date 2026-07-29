import 'package:call_logger/core/database/omnisearch_service.dart';
import 'package:call_logger/features/directory/building_map/widgets/building_map_omnisearch_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/*
 * «Ένα ψηφίο πίσω» στην έξυπνη αναζήτηση του χάρτη.
 *
 * Συμβόλαιο: η λίστα προτάσεων δείχνει τα αποτελέσματα ΤΟΥ ΚΕΙΜΕΝΟΥ που είναι
 * στο πεδίο — ποτέ του προηγούμενου ερωτήματος.
 *
 * Πραγματικό σενάριο: «291» → πολλά αποτελέσματα· «2914» → μόνο ο Πρόβος.
 *
 *   flutter test test/features/directory/building_map/building_map_omnisearch_field_test.dart --timeout 30s
 */

BuildingMapOmnisearchHit _hit(String title) => BuildingMapOmnisearchHit(
  kind: BuildingMapOmnisearchEntityKind.user,
  entityId: title.hashCode,
  title: title,
  departmentIds: const [],
);

/// Κατάλογος δοκιμής: το «2914» ανήκει μόνο στον Πρόβο.
Future<List<BuildingMapOmnisearchHit>> _fakeSearch(String query) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  const catalog = {
    '291': ['Πρόβος 2914', 'Ψαρρά 2915', 'Νακαστσή 2916'],
    '2914': ['Πρόβος 2914'],
  };
  return (catalog[query] ?? const <String>[]).map(_hit).toList();
}

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pumpField(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: BuildingMapOmnisearchField(
              enabled: true,
              search: _fakeSearch,
              controller: controller,
              focusNode: focusNode,
              onResolveEntity: (_) async {},
            ),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
  }

  /// Πληκτρολόγηση + αναμονή debounce, αναζήτησης και ανοίγματος overlay.
  Future<void> typeAndSettle(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    '«2914» δείχνει μόνο τον Πρόβο, όχι τα αποτελέσματα του «291»',
    (tester) async {
      await pumpField(tester);

      await typeAndSettle(tester, '291');
      expect(
        find.text('Ψαρρά 2915'),
        findsOneWidget,
        reason: 'Το «291» πρέπει να δείχνει και τους τρεις',
      );

      await typeAndSettle(tester, '2914');

      expect(
        find.text('Πρόβος 2914'),
        findsOneWidget,
        reason: 'Το «2914» ταιριάζει μόνο με τον Πρόβο',
      );
      expect(
        find.text('Ψαρρά 2915'),
        findsNothing,
        reason: 'η λίστα έμενε στα αποτελέσματα του προηγούμενου ερωτήματος',
      );
      expect(find.text('Νακαστσή 2916'), findsNothing);
    },
    experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
  );

  testWidgets(
    'κενό στο τέλος δεν αλλάζει το αποτέλεσμα',
    (tester) async {
      await pumpField(tester);

      await typeAndSettle(tester, '2914');
      await typeAndSettle(tester, '2914 ');

      expect(
        find.text('Πρόβος 2914'),
        findsOneWidget,
        reason: 'Το κείμενο κανονικοποιείται — το κενό δεν είναι νέο ερώτημα',
      );
      expect(find.text('Ψαρρά 2915'), findsNothing);
    },
    experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
  );

  testWidgets(
    'καθαρισμός πεδίου κλείνει τη λίστα',
    (tester) async {
      await pumpField(tester);

      await typeAndSettle(tester, '291');
      expect(find.text('Ψαρρά 2915'), findsOneWidget);

      await typeAndSettle(tester, '');
      expect(find.text('Ψαρρά 2915'), findsNothing);
    },
    experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
  );
}
