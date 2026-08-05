// Widget tests: αναβαλλόμενη διαγραφή εγγραφών Ιστορικού Εφαρμογής.
//
//   flutter test test/features/history/application_audit_deferred_delete_test.dart

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/providers/pending_deferred_actions_provider.dart';
import 'package:call_logger/features/audit/models/audit_log_model.dart';
import 'package:call_logger/features/audit/models/audit_page_result.dart';
import 'package:call_logger/features/audit/models/audit_reference_labels.dart';
import 'package:call_logger/features/audit/providers/audit_providers.dart';
import 'package:call_logger/features/history/widgets/application_audit_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Αναβαλλόμενη διαγραφή εγγραφών Ιστορικού Εφαρμογής', () {
    Future<List<int>> seedAuditRows(WidgetTester tester, int count) async {
      final ids = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final inserted = <int>[];
        for (var i = 0; i < count; i++) {
          inserted.add(
            await db.insert('audit_log', {
              'action': 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ',
              'timestamp': '2026-07-11T10:0$i:00.000',
              'user_performing': 'tester',
              'details': 'Δοκιμή αναβαλλόμενης διαγραφής $i',
              'entity_type': AuditEntityTypes.user,
              'entity_id': i + 1,
              'entity_name': 'Χρήστης $i',
            }),
          );
        }
        return inserted;
      });
      return ids!;
    }

    Future<int> rowsInDb(WidgetTester tester, List<int> ids) async {
      final count = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final placeholders = List.filled(ids.length, '?').join(',');
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM audit_log WHERE id IN ($placeholders)',
          ids,
        );
        return (rows.first['c'] as num).toInt();
      });
      return count!;
    }

    ProviderContainer buildContainer(List<AuditLogModel> items) {
      final container = ProviderContainer(
        overrides: [
          auditActionOptionsProvider.overrideWith(
            (ref) async => const ['ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ'],
          ),
          auditListProvider.overrideWith(
            (ref) async =>
                AuditPageResult(items: items, totalCount: items.length),
          ),
          auditPageReferenceLabelsProvider.overrideWith(
            (ref) async => AuditReferenceLabels.empty,
          ),
          auditEntityPreviewProvider.overrideWith((ref, key) async => null),
        ],
      );
      return container;
    }

    List<AuditLogModel> itemsForIds(List<int> ids) => [
      for (final id in ids)
        AuditLogModel.fromMap({
          'id': id,
          'action': 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ',
          'timestamp': '2026-07-11T10:00:00.000',
          'user_performing': 'tester',
          'details': 'Δοκιμή αναβαλλόμενης διαγραφής',
          'entity_type': AuditEntityTypes.user,
          'entity_id': id,
          'entity_name': 'Χρήστης $id',
        }),
    ];

    Future<void> pumpTab(WidgetTester tester, ProviderContainer container) {
      return tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ApplicationAuditTab()),
          ),
        ),
      );
    }

    Future<void> pumpAwayFromTab(
      WidgetTester tester,
      ProviderContainer container,
    ) {
      // Ίδια δομή δέντρου: ο MaterialApp/ScaffoldMessenger επιβιώνει,
      // μόνο το tab ξεφορτώνεται — όπως όταν αλλάζεις οθόνη στην εφαρμογή.
      return tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
    }

    Future<void> selectAllRowsAndConfirmDelete(
      WidgetTester tester,
      int rowCount,
    ) async {
      // Πρώτο Checkbox = «επιλογή όλων» της κεφαλίδας, τα υπόλοιπα = γραμμές.
      for (var i = 1; i <= rowCount; i++) {
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pump();
      }
      await tester.tap(find.byTooltip('Μόνιμη διαγραφή επιλεγμένων'));
      await pumpUntilSettled(tester);
      await tester.tap(find.text('Επιβεβαίωση'));
      await pumpUntilSettled(tester);
    }

    Future<void> drainRealAsyncChain(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        await tester.pump(const Duration(milliseconds: 60));
      }
      await pumpUntilSettled(tester);
    }

    testWidgets(
      'αλλαγή οθόνης μέσα στο παράθυρο → οι εγγραφές διαγράφονται κανονικά στη λήξη',
      (tester) async {
        final ids = await seedAuditRows(tester, 3);
        final container = buildContainer(itemsForIds(ids));
        addTearDown(container.dispose);

        await pumpTab(tester, container);
        await pumpUntilSettled(tester);

        await selectAllRowsAndConfirmDelete(tester, 3);

        // Έντιμο μήνυμα με μέτρηση — όχι «Διαγράφηκαν» πριν συμβεί.
        expect(find.textContaining('θα διαγραφούν οριστικά σε'), findsOneWidget);

        // Το σενάριο του ευρήματος: φεύγουμε από την οθόνη ΜΕΣΑ στα 5″.
        await pumpAwayFromTab(tester, container);
        await tester.pump(const Duration(seconds: 6));
        await drainRealAsyncChain(tester);

        // Ό,τι υποσχέθηκε το snackbar έγινε — κι ας έφυγε η οθόνη.
        expect(await rowsInDb(tester, ids), 0);
        expect(container.read(pendingDeferredActionsProvider), isEmpty);

        // Λήξη snackbar επιβεβαίωσης — καθαρό κλείσιμο χρονομετρητών.
        await tester.pump(const Duration(seconds: 6));
      },
    );

    testWidgets(
      'πάτημα «Αναίρεση» εντός του παραθύρου → οι εγγραφές παραμένουν στη βάση',
      (tester) async {
        final ids = await seedAuditRows(tester, 1);
        final container = buildContainer(itemsForIds(ids));
        addTearDown(container.dispose);

        await pumpTab(tester, container);
        await pumpUntilSettled(tester);

        await selectAllRowsAndConfirmDelete(tester, 1);

        expect(find.textContaining('θα διαγραφεί οριστικά σε'), findsOneWidget);

        await tester.tap(find.text('Αναίρεση'));
        await pumpUntilSettled(tester);
        expect(find.text('Η διαγραφή αναιρέθηκε.'), findsOneWidget);

        await tester.pump(const Duration(seconds: 6));
        await drainRealAsyncChain(tester);

        expect(await rowsInDb(tester, ids), 1);
        expect(container.read(pendingDeferredActionsProvider), isEmpty);

        await tester.pump(const Duration(seconds: 6));
      },
    );
  });
}
