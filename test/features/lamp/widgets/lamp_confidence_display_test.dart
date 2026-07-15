import 'package:call_logger/core/database/old_database/lamp_issue_resolution_models.dart';
import 'package:call_logger/features/lamp/widgets/lamp_issue_row_context.dart';
import 'package:flutter_test/flutter_test.dart';

LampIssueResolutionProposal _proposal({
  required int confidence,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return LampIssueResolutionProposal(
    issueType: LampIssueType.unknownId,
    issueIds: const <int>[1],
    sheet: 'integrity_scan',
    row: 100,
    column: 'office',
    originalValue: 'test',
    proposedAction: LampIssueResolutionAction.unresolved,
    confidence: confidence,
    notes: '',
    metadata: metadata,
  );
}

void main() {
  group('lampConfidenceDisplay', () {
    test('confidenceIsNominal true → null', () {
      expect(
        lampConfidenceDisplay(
          _proposal(
            confidence: 45,
            metadata: const <String, Object?>{'confidenceIsNominal': true},
          ),
        ),
        isNull,
      );
    });

    test('confidence 97 → Υψηλή', () {
      expect(
        lampConfidenceDisplay(_proposal(confidence: 97)),
        'Βεβαιότητα: Υψηλή (97%)',
      );
    });

    test('confidence 70 → Μεσαία', () {
      expect(
        lampConfidenceDisplay(_proposal(confidence: 70)),
        'Βεβαιότητα: Μεσαία (70%)',
      );
    });

    test('confidence 0 → Χαμηλή', () {
      expect(
        lampConfidenceDisplay(_proposal(confidence: 0)),
        'Βεβαιότητα: Χαμηλή (0%)',
      );
    });
  });
}
