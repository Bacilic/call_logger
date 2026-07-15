import 'package:call_logger/features/lamp/controllers/lamp_issue_resolution_controller.dart';
import 'package:call_logger/features/lamp/widgets/lamp_issue_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('issueFamilyColor + αντιγραψιμότητα (ΓΕΝ-4)', () {
    test('χρώματα οικογενειών επίλυσης', () {
      expect(
        LampIssueHelpers.issueFamilyColor('non_numeric_fk'),
        Colors.indigo,
      );
      expect(
        LampIssueHelpers.issueFamilyColor('serial_scientific_notation'),
        Colors.orange,
      );
      expect(
        LampIssueHelpers.issueFamilyColor('set_master_missing_target'),
        Colors.deepPurple,
      );
      expect(
        LampIssueHelpers.issueFamilyColor('network_invalid_ip'),
        Colors.teal,
      );
      expect(
        LampIssueHelpers.issueFamilyColor('network_sheet_invalid'),
        Colors.blueGrey,
      );
      expect(
        LampIssueHelpers.issueFamilyColor('missing_sheet'),
        Colors.blueGrey,
      );
    });

    testWidgets('LampIssueEntryListTile · title και subtitle είναι SelectableText',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LampIssueEntryListTile(
              issue: <String, Object?>{
                'row_number': 42,
                'column_name': 'serial_no',
                'raw_value': 'ABC123',
                'message': 'Δοκιμαστικό μήνυμα',
              },
            ),
          ),
        ),
      );

      expect(find.byType(SelectableText), findsNWidgets(2));
    });
  });

  group('issueResolutionPriority (ΓΕΝ-3)', () {
    const knownTypes = <String>[
      'non_numeric_fk',
      'unknown_id',
      'duplicate_asset_no',
      'duplicate_model_serial',
      'serial_scientific_notation',
      'set_master_self_reference',
      'set_master_missing_target',
      'set_master_cycle',
      'network_invalid_ip',
      'network_duplicate_ip',
      'network_duplicate_name',
      'network_name_code_mismatch',
      'network_code_not_found',
      'network_duplicate_hostname',
      'network_hostname_unmatched',
      'network_no_hostname',
      'network_ip_in_comments',
      'network_model_mismatch',
      'missing_sheet',
      'missing_primary_key',
      'duplicate_code_discarded',
      'xls_conversion_failed',
      'network_sheet_invalid',
    ];

    test('κάθε γνωστός τύπος έχει προτεραιότητα < 999', () {
      for (final type in knownTypes) {
        expect(
          LampIssueHelpers.issueResolutionPriority(type),
          lessThan(999),
          reason: 'Ο $type δεν πρέπει να πέφτει στο αλφαβητικό τέλος.',
        );
      }
    });

    test('σχετική σειρά ενοτήτων', () {
      expect(
        LampIssueHelpers.issueResolutionPriority('serial_scientific_notation'),
        lessThan(
          LampIssueHelpers.issueResolutionPriority('set_master_self_reference'),
        ),
      );
      expect(
        LampIssueHelpers.issueResolutionPriority('set_master_cycle'),
        lessThan(
          LampIssueHelpers.issueResolutionPriority('network_invalid_ip'),
        ),
      );
      expect(
        LampIssueHelpers.issueResolutionPriority('network_model_mismatch'),
        lessThan(LampIssueHelpers.issueResolutionPriority('missing_sheet')),
      );
    });

    test('άγνωστος τύπος → 999 και κενός → 10000', () {
      expect(LampIssueHelpers.issueResolutionPriority('foo'), 999);
      expect(LampIssueHelpers.issueResolutionPriority(''), 10000);
      expect(LampIssueHelpers.issueResolutionPriority('   '), 10000);
    });
  });

  group('Πληροφοριακοί τύποι (ΓΕΝ-2)', () {
    test('οι 5 πληροφοριακοί τύποι αναγνωρίζονται', () {
      for (final type in <String>[
        'missing_sheet',
        'missing_primary_key',
        'duplicate_code_discarded',
        'xls_conversion_failed',
        'network_sheet_invalid',
      ]) {
        expect(
          LampIssueResolutionController.isInformationalIssueType(type),
          isTrue,
          reason: 'Ο $type είναι πληροφοριακός.',
        );
      }
    });

    test('οι επιλύσιμοι τύποι ΔΕΝ είναι πληροφοριακοί', () {
      for (final type in <String>[
        'non_numeric_fk',
        'network_duplicate_ip',
        'set_master_missing_target',
      ]) {
        expect(
          LampIssueResolutionController.isInformationalIssueType(type),
          isFalse,
          reason: 'Ο $type έχει οδηγό επίλυσης.',
        );
      }
    });
  });

  group('LampIssueGroupHeaderCard · εκκαθάριση ομάδας', () {
    Future<void> pumpHeader(
      WidgetTester tester, {
      VoidCallback? onClearGroup,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LampIssueGroupHeaderCard(
              rawIssueType: 'missing_sheet',
              categoryLabel: 'Λείπει φύλλο',
              issues: const [
                <String, Object?>{'id': 1},
                <String, Object?>{'id': 2},
              ],
              lampIssueType: null,
              expanded: false,
              onToggleExpanded: () {},
              resolvingIssueType: null,
              canResolve: false,
              onResolve: null,
              onClearGroup: onClearGroup,
            ),
          ),
        ),
      );
    }

    testWidgets('με onClearGroup εμφανίζεται κουμπί εκκαθάρισης που καλείται',
        (tester) async {
      var cleared = false;
      await pumpHeader(tester, onClearGroup: () => cleared = true);

      final button = find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined);
      expect(button, findsOneWidget);
      expect(
        find.byTooltip('Εκκαθάριση ομάδας (2 πληροφοριακές εγγραφές)'),
        findsOneWidget,
      );

      await tester.tap(button);
      expect(cleared, isTrue);
    });

    testWidgets('χωρίς onClearGroup δεν υπάρχει κουμπί εκκαθάρισης',
        (tester) async {
      await pumpHeader(tester);
      expect(
        find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined),
        findsNothing,
      );
    });
  });

  group('LampIssueHelpers.resolveNetworkIssueIcon', () {
    const cases = <String, IconData>{
      'network_invalid_ip': Icons.wrong_location_outlined,
      'network_duplicate_ip': Icons.difference_outlined,
      'network_duplicate_name': Icons.content_copy_outlined,
      'network_duplicate_hostname': Icons.file_copy_outlined,
      'network_name_code_mismatch': Icons.sync_problem_outlined,
      'network_no_hostname': Icons.label_off_outlined,
      'network_hostname_unmatched': Icons.link_off_outlined,
      'network_code_not_found': Icons.search_off_outlined,
      'network_ip_in_comments': Icons.comment_outlined,
      'network_model_mismatch': Icons.devices_other_outlined,
      'network_sheet_invalid': Icons.grid_off_outlined,
    };

    for (final entry in cases.entries) {
      test('${entry.key} → ${entry.value}', () {
        expect(
          LampIssueHelpers.resolveNetworkIssueIcon(entry.key),
          entry.value,
        );
      });
    }

    test('άγνωστος τύπος επιστρέφει Icons.hub_outlined', () {
      expect(
        LampIssueHelpers.resolveNetworkIssueIcon('network_κατι_αλλο'),
        Icons.hub_outlined,
      );
    });
  });
}
