import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/features/audit/models/audit_filter_model.dart';
import 'package:call_logger/features/audit/models/audit_log_model.dart';
import 'package:call_logger/features/audit/models/audit_page_result.dart';
import 'package:call_logger/features/audit/models/audit_reference_labels.dart';
import 'package:call_logger/features/audit/providers/audit_providers.dart';
import 'package:call_logger/features/history/widgets/application_audit_tab.dart';
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
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ApplicationAuditTab(),
          ),
        ),
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
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Ενέργεια',
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
}
