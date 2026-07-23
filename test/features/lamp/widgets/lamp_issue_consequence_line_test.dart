import 'package:call_logger/core/database/old_database/lamp_issue_resolution_models.dart';
import 'package:call_logger/features/lamp/widgets/lamp_issue_manual_review_dialog.dart';
import 'package:call_logger/features/lamp/widgets/lamp_issue_row_context.dart';
import 'package:flutter_test/flutter_test.dart';

LampIssueResolutionProposal _proposal({
  int? row = 5005,
  String? column = 'owner',
  String? description = 'DELL',
}) {
  return LampIssueResolutionProposal(
    issueType: LampIssueType.nonNumericFk,
    issueIds: const <int>[1],
    sheet: 'integrity_scan',
    row: row,
    column: column,
    originalValue: 'Τσουκαλά',
    proposedAction: LampIssueResolutionAction.manualReview,
    confidence: 45,
    notes: 'δοκιμή',
    metadata: <String, Object?>{
      'rowContextDescription': ?description,
      'rowContextCode': '$row',
    },
  );
}

void main() {
  group('lampResolutionConsequenceLine', () {
    test('(α) σύνδεση με υπάρχοντα', () {
      final option = const LampIssueResolutionOption(
        id: 'owner_link_88',
        label: '88 · Τσουκαλά Παναγιώτα',
        action: LampIssueResolutionAction.autoFix,
        proposedId: 88,
        proposedMatch: 'Τσουκαλά Παναγιώτα',
        metadata: <String, Object?>{
          'operation': 'update_equipment_fk',
          'fkColumn': 'owner',
          'proposedId': 88,
        },
      );

      expect(
        lampResolutionConsequenceLine(_proposal(), option),
        'Επιλεγμένη ενέργεια: Κωδικός 5005 (DELL) → υπάλληλος: 88 · Τσουκαλά Παναγιώτα',
      );
    });

    test('(αβ) σύνδεση χωρίς περιγραφή — χωρίς παρένθεση', () {
      final option = const LampIssueResolutionOption(
        id: 'owner_link_88',
        label: '88 · Τσουκαλά Παναγιώτα',
        action: LampIssueResolutionAction.autoFix,
        proposedId: 88,
      );

      expect(
        lampResolutionConsequenceLine(
          _proposal(description: null),
          option,
        ),
        'Επιλεγμένη ενέργεια: Κωδικός 5005 → υπάλληλος: 88 · Τσουκαλά Παναγιώτα',
      );
    });

    test('(β) δημιουργία νέου', () {
      final option = const LampIssueResolutionOption(
        id: 'owner_create_full',
        label: 'Νέος υπάλληλος: επώνυμο=Παπαδόπουλος',
        action: LampIssueResolutionAction.createNew,
        metadata: <String, Object?>{
          'operation': 'create_owner_and_update_equipment',
        },
      );

      expect(
        lampResolutionConsequenceLine(_proposal(), option),
        '→ Δημιουργία: Νέος υπάλληλος: επώνυμο=Παπαδόπουλος',
      );
    });

    test('(β) δημιουργία νέου με textInput', () {
      final option = const LampIssueResolutionOption(
        id: 'owner_manual_edit',
        label: 'Τροποποίηση',
        action: LampIssueResolutionAction.createNew,
        requiresTextInput: true,
        inputLabel: 'Επώνυμο, μικρό όνομα',
      );

      expect(
        lampResolutionConsequenceLine(
          _proposal(),
          option,
          textInput: 'Παπαδόπουλος, Γιώργος',
        ),
        '→ Δημιουργία: Τροποποίηση · Παπαδόπουλος, Γιώργος',
      );
    });

    test('(γ) εκκαθάριση/αποσύνδεση', () {
      final clearOption = const LampIssueResolutionOption(
        id: 'owner_null_clear_original',
        label: 'Αποσύνδεση υπαλλήλου και εκκαθάριση του αρχικού κειμένου',
        action: LampIssueResolutionAction.autoFix,
        metadata: <String, Object?>{
          'operation': 'update_equipment_owner_null_clear_original',
        },
      );
      final disconnectOption = const LampIssueResolutionOption(
        id: 'owner_null_keep_note',
        label: 'Αποσύνδεση υπαλλήλου, διατήρηση του αρχικού κειμένου',
        action: LampIssueResolutionAction.autoFix,
        metadata: <String, Object?>{
          'operation': 'update_equipment_fk',
          'fkColumn': 'owner',
          'proposedId': null,
        },
      );

      expect(
        lampResolutionConsequenceLine(_proposal(), clearOption),
        '→ Εκκαθάριση/Αποσύνδεση υπάλληλος',
      );
      expect(
        lampResolutionConsequenceLine(_proposal(), disconnectOption),
        '→ Εκκαθάριση/Αποσύνδεση υπάλληλος',
      );
    });

    test('(δ) skip sentinel', () {
      expect(
        lampResolutionConsequenceLine(_proposal(), kLampManualSkipOption),
        'Επιλεγμένη ενέργεια: Παράλειψη — η εγγραφή μένει ανοιχτή',
      );
    });

    test('(ε) null — καμία επιλογή', () {
      expect(
        lampResolutionConsequenceLine(_proposal(), null),
        'Δεν έχει επιλεγεί ενέργεια.',
      );
    });
  });
}
