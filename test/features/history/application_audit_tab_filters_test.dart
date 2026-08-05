import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/features/audit/models/audit_filter_model.dart';
import 'package:call_logger/features/audit/models/audit_log_model.dart';
import 'package:call_logger/features/audit/models/audit_page_result.dart';
import 'package:call_logger/features/audit/models/audit_reference_labels.dart';
import 'package:call_logger/features/audit/providers/audit_providers.dart';
import 'package:call_logger/features/history/widgets/application_audit_tab.dart';
import 'package:call_logger/features/history/widgets/audit_entity_side_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final seedItems = <AuditLogModel>[
    AuditLogModel.fromMap({
      'id': 1,
      'action': 'συσχέτιση από κλήση',
      'timestamp': '2026-07-11T10:00:00.000',
      'user_performing': 'tester',
      'details': 'Όνομα - Τμήμα',
      'entity_type': AuditEntityTypes.user,
      'entity_id': 1,
      'entity_name': 'Όνομα',
    }),
    AuditLogModel.fromMap({
      'id': 2,
      'action': 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ',
      'timestamp': '2026-07-11T11:00:00.000',
      'user_performing': 'tester',
      'details': 'users id=2',
      'entity_type': AuditEntityTypes.user,
      'entity_id': 2,
      'entity_name': 'Νέος',
    }),
  ];

  List<AuditLogModel> filterItems(AuditFilterModel filter) {
    return seedItems.where((row) {
      if (filter.action != null && filter.action!.isNotEmpty) {
        if (row.action != filter.action) return false;
      }
      if (filter.entityType != null && filter.entityType!.isNotEmpty) {
        if (row.entityType != filter.entityType) return false;
      }
      return true;
    }).toList();
  }

  Future<void> pumpAuditTab(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          auditActionOptionsProvider.overrideWith(
            (ref) async => const [
              'συσχέτιση από κλήση',
              'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ',
              'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
            ],
          ),
          auditListProvider.overrideWith((ref) async {
            final filter = ref.watch(auditFilterProvider);
            final filtered = filterItems(filter);
            return AuditPageResult(
              items: filtered,
              totalCount: filtered.length,
            );
          }),
          auditPageReferenceLabelsProvider.overrideWith(
            (ref) async => AuditReferenceLabels.empty,
          ),
          auditEntityPreviewProvider.overrideWith((ref, key) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: ApplicationAuditTab())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finishInteraction(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Finder actionField() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Ενέργεια',
  );

  group('ApplicationAuditTab autocomplete φίλτρα', () {
    testWidgets('πληκτρολόγηση φιλτράρει τις προτάσεις ενέργειας', (
      tester,
    ) async {
      await pumpAuditTab(tester);

      await tester.tap(actionField());
      await tester.pumpAndSettle();
      await tester.enterText(actionField(), 'δημι');
      await tester.pumpAndSettle();

      expect(find.text('ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ'), findsOneWidget);
      expect(find.text('συσχέτιση από κλήση'), findsNothing);

      await finishInteraction(tester);
    });

    testWidgets('Enter στην επισημασμένη πρόταση εφαρμόζει φίλτρο ενέργειας', (
      tester,
    ) async {
      await pumpAuditTab(tester);

      await tester.tap(actionField());
      await tester.pumpAndSettle();
      await tester.enterText(actionField(), 'συσχ');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.textContaining('1 / 1'), findsOneWidget);
      expect(find.textContaining('2 /'), findsNothing);

      await finishInteraction(tester);
    });

    testWidgets(
      'βελάκι κάτω + Enter εφαρμόζει τη δεύτερη πρόταση ενέργειας',
      (tester) async {
        await pumpAuditTab(tester);

        await tester.tap(actionField());
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        // Εφαρμόστηκε η δεύτερη πρόταση («ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ») → 1 εγγραφή.
        expect(find.textContaining('1 εγγραφές'), findsOneWidget);
        final field = tester.widget<TextField>(actionField());
        expect(field.controller!.text, 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ');

        await finishInteraction(tester);
      },
    );

    testWidgets('κενό πεδίο ενέργειας δείχνει όλες τις εγγραφές', (
      tester,
    ) async {
      await pumpAuditTab(tester);

      expect(find.textContaining('2 εγγραφές'), findsOneWidget);

      await tester.tap(actionField());
      await tester.pumpAndSettle();
      await tester.enterText(actionField(), 'συσχ');
      await tester.pumpAndSettle();
      await tester.tap(find.text('συσχέτιση από κλήση'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 εγγραφές'), findsOneWidget);

      final clearButtons = find.byIcon(Icons.clear);
      await tester.tap(clearButtons.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('2 εγγραφές'), findsOneWidget);

      await finishInteraction(tester);
    });
  });

  group('επαναφορά κύλισης στην κορυφή (σελίδα & φίλτρα)', () {
    List<AuditLogModel> manyItems() => List.generate(
      100,
      (i) => AuditLogModel.fromMap({
        'id': i + 1,
        'action': 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ',
        'timestamp': '2026-07-11T10:00:00.000',
        'user_performing': 'tester',
        'details': 'Εγγραφή ${i + 1}',
        'entity_type': AuditEntityTypes.user,
        'entity_id': i + 1,
        'entity_name': 'Χρήστης ${i + 1}',
      }),
    );

    Future<void> pumpPagedAuditTab(WidgetTester tester) async {
      final items = manyItems();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            auditActionOptionsProvider.overrideWith(
              (ref) async => const ['ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ'],
            ),
            auditListProvider.overrideWith((ref) async {
              final page = ref.watch(auditPageIndexProvider);
              ref.watch(auditFilterProvider);
              final slice = items
                  .skip(page * kAuditPageSize)
                  .take(kAuditPageSize)
                  .toList();
              return AuditPageResult(items: slice, totalCount: items.length);
            }),
            auditPageReferenceLabelsProvider.overrideWith(
              (ref) async => AuditReferenceLabels.empty,
            ),
            auditEntityPreviewProvider.overrideWith((ref, key) async => null),
          ],
          child: const MaterialApp(home: Scaffold(body: ApplicationAuditTab())),
        ),
      );
      await tester.pumpAndSettle();
    }

    // `.first`: όταν το overlay προτάσεων είναι ανοιχτό υπάρχει δεύτερο
    // ListView — η κύρια λίστα προηγείται πάντα στο δέντρο.
    ScrollableState listScrollable(WidgetTester tester) =>
        tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );

    testWidgets('η αλλαγή σελίδας ξεκινά την προβολή από την κορυφή', (
      tester,
    ) async {
      await pumpPagedAuditTab(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(listScrollable(tester).position.pixels, greaterThan(0));

      await tester.tap(find.byTooltip('Επόμενη σελίδα'));
      await tester.pumpAndSettle();

      expect(listScrollable(tester).position.pixels, 0);
    });

    testWidgets('η αλλαγή φίλτρου ξεκινά την προβολή από την κορυφή', (
      tester,
    ) async {
      await pumpPagedAuditTab(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(listScrollable(tester).position.pixels, greaterThan(0));

      await tester.tap(actionField());
      await tester.pumpAndSettle();
      await tester.tap(find.text('ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ'));
      await tester.pumpAndSettle();

      expect(listScrollable(tester).position.pixels, 0);

      await finishInteraction(tester);
    });
  });

  group('σήμανση επιλεγμένης γραμμής (πάνελ λεπτομερειών)', () {
    testWidgets(
      'πάτημα γραμμής ανοίγει το πάνελ και σημαίνει ορατά τη γραμμή στη λίστα',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await pumpAuditTab(tester);

        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();

        // Το πάνελ λεπτομερειών άνοιξε για την εγγραφή.
        expect(find.byType(AuditEntitySidePanel), findsOneWidget);

        // Ακριβώς μία γραμμή σημαίνεται επιλεγμένη — με ορατό υπόστρωμα.
        final markedTiles = tester
            .widgetList<ListTile>(find.byType(ListTile))
            .where((tile) => tile.selected)
            .toList();
        expect(markedTiles, hasLength(1));
        expect(
          markedTiles.single.selectedTileColor,
          isNotNull,
          reason:
              'Χωρίς selectedTileColor η επιλογή είναι αόρατη: τίτλος, '
              'υπότιτλος και εικονίδιο της γραμμής έχουν δικά τους χρώματα.',
        );

        await finishInteraction(tester);
      },
    );
  });
}
