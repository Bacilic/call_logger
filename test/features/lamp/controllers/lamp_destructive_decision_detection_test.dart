import 'package:call_logger/core/database/old_database/lamp_issue_resolution_models.dart';
import 'package:call_logger/features/lamp/controllers/lamp_issue_resolution_controller.dart';
import 'package:flutter_test/flutter_test.dart';

LampIssueResolutionProposal _minimalProposal({
  Map<String, Object?> metadata = const <String, Object?>{},
  List<LampIssueResolutionOption> options = const <LampIssueResolutionOption>[],
}) {
  return LampIssueResolutionProposal(
    issueType: LampIssueType.duplicateAssetNo,
    issueIds: const <int>[1],
    sheet: null,
    row: 100,
    column: 'asset_no',
    originalValue: '123',
    proposedAction: LampIssueResolutionAction.manualReview,
    confidence: 80,
    notes: '',
    metadata: metadata,
    options: options,
  );
}

LampIssueResolutionOption _option(String operation) {
  return LampIssueResolutionOption(
    id: operation,
    label: operation,
    action: LampIssueResolutionAction.manualReview,
    metadata: <String, Object?>{'operation': operation},
  );
}

void main() {
  group('decisionIsDestructive', () {
    test(
      'true όταν το option.metadata έχει delete_duplicate_asset_others',
      () {
        final decision = LampIssueResolutionDecision(
          proposal: _minimalProposal(
            metadata: const <String, Object?>{
              'operation': 'delete_duplicate_serial_others',
            },
          ),
          option: _option('delete_duplicate_asset_others'),
        );

        expect(decisionIsDestructive(decision), isTrue);
      },
    );

    test(
      'true όταν μόνο το proposal.metadata έχει delete_duplicate_serial_others',
      () {
        final decision = LampIssueResolutionDecision(
          proposal: _minimalProposal(
            metadata: const <String, Object?>{
              'operation': 'delete_duplicate_serial_others',
            },
          ),
        );

        expect(decisionIsDestructive(decision), isTrue);
      },
    );

    test(
      'false όταν το option υπερισχύει με μη διαγραφικό operation',
      () {
        final decision = LampIssueResolutionDecision(
          proposal: _minimalProposal(
            metadata: const <String, Object?>{
              'operation': 'delete_duplicate_asset_others',
            },
          ),
          option: _option('keep_primary'),
        );

        expect(decisionIsDestructive(decision), isFalse);
      },
    );

    test('false όταν λείπει operation', () {
      final decision = LampIssueResolutionDecision(
        proposal: _minimalProposal(),
      );

      expect(decisionIsDestructive(decision), isFalse);
    });
  });
}
