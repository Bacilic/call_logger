import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/features/lamp/controllers/lamp_issue_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

LampIssueResolutionProposal _manualProposal({
  required LampIssueType issueType,
  required int row,
  required String column,
  required String originalValue,
}) {
  return LampIssueResolutionProposal(
    issueType: issueType,
    issueIds: <int>[row],
    sheet: 'equipment',
    row: row,
    column: column,
    originalValue: originalValue,
    proposedAction: LampIssueResolutionAction.manualReview,
    proposedId: null,
    proposedMatch: null,
    confidence: 50,
    options: const <LampIssueResolutionOption>[],
    notes: 'δοκιμή',
  );
}

void main() {
  group('Λάμπα · ομαδοποίηση χειροκίνητης επισκόπησης', () {
    test(
      'τρεις manualReview με ίδιο πεδίο και ίδια τιμή ομαδοποιούνται',
      () async {
        const officeText = 'Τμήμα Πληροφορικής';
        final proposals = <LampIssueResolutionProposal>[
          _manualProposal(
            issueType: LampIssueType.nonNumericFk,
            row: 1001,
            column: 'office',
            originalValue: officeText,
          ),
          _manualProposal(
            issueType: LampIssueType.nonNumericFk,
            row: 1002,
            column: 'office',
            originalValue: '  τμήμα   πληροφορικής ',
          ),
          _manualProposal(
            issueType: LampIssueType.nonNumericFk,
            row: 1003,
            column: 'office',
            originalValue: officeText,
          ),
        ];

        final groups = groupManualReviewProposals(proposals);
        expect(groups, hasLength(1));
        expect(groups.single, hasLength(3));

        final units = buildLampIssueOrchestrationUnits(proposals);
        expect(units, hasLength(1));
        final unit = units.single;
        expect(unit, isA<LampManualReviewOrchestrationUnit>());
        expect(
          (unit as LampManualReviewOrchestrationUnit).groupedIdenticalValues,
          isTrue,
        );
      },
    );

    test('διαφορετικά πεδία δεν ομαδοποιούνται', () {
      const sharedText = 'Κοινό Κείμενο';
      final proposals = <LampIssueResolutionProposal>[
        _manualProposal(
          issueType: LampIssueType.nonNumericFk,
          row: 2001,
          column: 'office',
          originalValue: sharedText,
        ),
        _manualProposal(
          issueType: LampIssueType.nonNumericFk,
          row: 2002,
          column: 'model',
          originalValue: sharedText,
        ),
      ];

      final groups = groupManualReviewProposals(proposals);
      expect(groups, hasLength(2));
      expect(groups.every((g) => g.length == 1), isTrue);
    });

    test('διαφορετικές κατηγορίες δεν ομαδοποιούνται', () {
      const sharedText = 'Ίδιο Κείμενο';
      final proposals = <LampIssueResolutionProposal>[
        _manualProposal(
          issueType: LampIssueType.nonNumericFk,
          row: 3001,
          column: 'office',
          originalValue: sharedText,
        ),
        _manualProposal(
          issueType: LampIssueType.unknownId,
          row: 3002,
          column: 'office',
          originalValue: sharedText,
        ),
      ];

      final groups = groupManualReviewProposals(proposals);
      expect(groups, hasLength(2));
    });

    test('διπλότυπα (duplicate_asset_no) δεν ομαδοποιούνται', () {
      final proposals = <LampIssueResolutionProposal>[
        LampIssueResolutionProposal(
          issueType: LampIssueType.duplicateAssetNo,
          issueIds: const <int>[1],
          sheet: 'equipment',
          row: 4001,
          column: 'asset_no',
          originalValue: 'DUP-1',
          proposedAction: LampIssueResolutionAction.manualReview,
          proposedId: null,
          proposedMatch: null,
          confidence: 40,
          options: const <LampIssueResolutionOption>[],
          notes: 'δοκιμή',
        ),
        LampIssueResolutionProposal(
          issueType: LampIssueType.duplicateAssetNo,
          issueIds: const <int>[2],
          sheet: 'equipment',
          row: 4002,
          column: 'asset_no',
          originalValue: 'DUP-1',
          proposedAction: LampIssueResolutionAction.manualReview,
          proposedId: null,
          proposedMatch: null,
          confidence: 40,
          options: const <LampIssueResolutionOption>[],
          notes: 'δοκιμή',
        ),
      ];

      final groups = groupManualReviewProposals(proposals);
      expect(groups, isEmpty);

      final units = buildLampIssueOrchestrationUnits(proposals);
      expect(units, hasLength(2));
      expect(units.every((u) => u is LampManualReviewOrchestrationUnit), isTrue);
      expect(
        units
            .cast<LampManualReviewOrchestrationUnit>()
            .every((u) => !u.groupedIdenticalValues),
        isTrue,
      );
    });
  });
}
