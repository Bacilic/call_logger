import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:call_logger/features/lamp/widgets/lamp_transfer_wizard_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyCandidatesMigrationService extends LampMigrationService {
  @override
  Future<LampMigrationDraft> buildDraft({
    required LampTransferTarget target,
    required Map<String, Object?> sourceRow,
  }) async {
    return LampMigrationDraft(
      target: target,
      oldValues: const {'Παλιός κάτοχος': 'Ξενος Χρηστης'},
      formValues: const {
        'first_name': 'Ξενος',
        'last_name': 'Χρηστης',
        'phones': '',
        'equipment_codes': '',
        'department_name': '',
        'location': '',
        'notes': '',
      },
      newRecordFormValues: const {
        'first_name': 'Ξενος',
        'last_name': 'Χρηστης',
        'phones': '',
        'equipment_codes': '',
        'department_name': '',
        'location': '',
        'notes': '',
      },
      candidateFormValues: const {},
      candidates: const [],
      selectedCandidateId: null,
      updatesExistingRecord: false,
    );
  }
}

void main() {
  testWidgets('κενή λίστα υποψηφίων — μήνυμα και προεπιλογή Νέα εγγραφή', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LampTransferWizardDialog(
            target: LampTransferTarget.owner,
            sourceRow: const {'owner_original_text': 'Ξενος Χρηστης'},
            service: _EmptyCandidatesMigrationService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Καμία πιθανή αντιστοίχιση'), findsOneWidget);
    expect(find.text('Νέα εγγραφή'), findsOneWidget);
    expect(find.textContaining('Confidence:'), findsNothing);

    final newEntryFinder = find.widgetWithText(
      RadioListTile<int?>,
      'Νέα εγγραφή',
    );
    final radioGroup = tester.widget<RadioGroup<int?>>(
      find.ancestor(
        of: newEntryFinder,
        matching: find.byType(RadioGroup<int?>),
      ),
    );
    expect(radioGroup.groupValue, isNull);
    expect(tester.widget<RadioListTile<int?>>(newEntryFinder).value, isNull);  });
}
