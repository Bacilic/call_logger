import '../../../core/database/old_database/lamp_issue_matching_engine.dart';
import '../../../core/database/old_database/lamp_issue_resolution_service.dart';

/// Κλειδί ομαδοποίησης χειροκίνητης επισκόπησης FK (κατηγορία + πεδίο + τιμή).
class LampManualReviewGroupKey {
  const LampManualReviewGroupKey({
    required this.issueType,
    required this.column,
    required this.normalizedOriginalValue,
  });

  final LampIssueType issueType;
  final String column;
  final String normalizedOriginalValue;

  @override
  bool operator ==(Object other) {
    return other is LampManualReviewGroupKey &&
        other.issueType == issueType &&
        other.column == column &&
        other.normalizedOriginalValue == normalizedOriginalValue;
  }

  @override
  int get hashCode => Object.hash(issueType, column, normalizedOriginalValue);
}

/// Μονάδα εκτέλεσης στην ορχήστρωση επίλυσης.
sealed class LampIssueOrchestrationUnit {
  const LampIssueOrchestrationUnit();
}

/// Συνεχόμενες αυτόματες προτάσεις σε μία παρτίδα.
class LampAutoBatchOrchestrationUnit extends LampIssueOrchestrationUnit {
  const LampAutoBatchOrchestrationUnit(this.proposals);

  final List<LampIssueResolutionProposal> proposals;
}

/// Χειροκίνητη επισκόπηση — μία ή περισσότερες όμοιες εγγραφές.
class LampManualReviewOrchestrationUnit extends LampIssueOrchestrationUnit {
  const LampManualReviewOrchestrationUnit({
    required this.proposals,
    required this.groupedIdenticalValues,
  });

  final List<LampIssueResolutionProposal> proposals;
  final bool groupedIdenticalValues;
}

/// Ανεπίλυτη πρόταση — ένα βήμα.
class LampUnresolvedOrchestrationUnit extends LampIssueOrchestrationUnit {
  const LampUnresolvedOrchestrationUnit(this.proposal);

  final LampIssueResolutionProposal proposal;
}

final LampIssueMatchingEngine _groupingNormalizer = LampIssueMatchingEngine();

/// Κατηγορίες κλειδιών όπου επιτρέπεται ομαδοποίηση ίδιων τιμών.
bool isManualReviewGroupableIssueType(LampIssueType issueType) {
  return issueType == LampIssueType.nonNumericFk ||
      issueType == LampIssueType.unknownId;
}

/// Κανονικοποιημένη αρχική τιμή πρότασης για κλειδί ομάδας.
String manualReviewNormalizedOriginalValue(LampIssueResolutionProposal proposal) {
  final raw = proposal.originalValue?.trim() ?? '';
  return _groupingNormalizer.normalizeReferenceText(raw);
}

/// Κλειδί ομάδας χειροκίνητης επισκόπησης (null αν δεν ομαδοποιείται).
LampManualReviewGroupKey? manualReviewGroupKey(
  LampIssueResolutionProposal proposal,
) {
  if (proposal.proposedAction != LampIssueResolutionAction.manualReview) {
    return null;
  }
  if (!isManualReviewGroupableIssueType(proposal.issueType)) {
    return null;
  }
  final column = proposal.column?.trim().toLowerCase() ?? '';
  if (column.isEmpty) return null;
  final normalized = manualReviewNormalizedOriginalValue(proposal);
  if (normalized.isEmpty) return null;
  return LampManualReviewGroupKey(
    issueType: proposal.issueType,
    column: column,
    normalizedOriginalValue: normalized,
  );
}

/// Ομαδοποιεί προτάσεις manualReview των κατηγοριών κλειδιών.
///
/// Επιστρέφει λίστα ομάδων· κάθε ομάδα είναι μία ή περισσότερες προτάσεις με
/// ίδιο (κατηγορία + πεδίο + κανονικοποιημένη αρχική τιμή).
List<List<LampIssueResolutionProposal>> groupManualReviewProposals(
  List<LampIssueResolutionProposal> proposals,
) {
  final groups = <LampManualReviewGroupKey, List<LampIssueResolutionProposal>>{};
  final order = <LampManualReviewGroupKey>[];

  for (final proposal in proposals) {
    final key = manualReviewGroupKey(proposal);
    if (key == null) continue;
    if (!groups.containsKey(key)) {
      order.add(key);
      groups[key] = <LampIssueResolutionProposal>[];
    }
    groups[key]!.add(proposal);
  }

  return <List<LampIssueResolutionProposal>>[
    for (final key in order) groups[key]!,
  ];
}

/// Μετατρέπει τη σειρά προτάσεων σε μονάδες εκτέλεσης (παρτίδες, ομάδες, μεμονωμένα).
List<LampIssueOrchestrationUnit> buildLampIssueOrchestrationUnits(
  List<LampIssueResolutionProposal> proposals,
) {
  final units = <LampIssueOrchestrationUnit>[];
  final handledIndices = <int>{};

  for (var i = 0; i < proposals.length; i++) {
    if (handledIndices.contains(i)) continue;
    final proposal = proposals[i];

    if (proposal.canApplyAutomatically) {
      final batch = <LampIssueResolutionProposal>[];
      for (var j = i; j < proposals.length; j++) {
        if (handledIndices.contains(j)) continue;
        if (!proposals[j].canApplyAutomatically) break;
        batch.add(proposals[j]);
        handledIndices.add(j);
      }
      units.add(LampAutoBatchOrchestrationUnit(batch));
      continue;
    }

    if (proposal.proposedAction == LampIssueResolutionAction.manualReview) {
      final key = manualReviewGroupKey(proposal);
      if (key != null) {
        final group = <LampIssueResolutionProposal>[];
        for (var j = 0; j < proposals.length; j++) {
          if (handledIndices.contains(j)) continue;
          final candidate = proposals[j];
          if (manualReviewGroupKey(candidate) == key) {
            group.add(candidate);
            handledIndices.add(j);
          }
        }
        units.add(
          LampManualReviewOrchestrationUnit(
            proposals: group,
            groupedIdenticalValues: group.length > 1,
          ),
        );
        continue;
      }

      handledIndices.add(i);
      units.add(
        LampManualReviewOrchestrationUnit(
          proposals: <LampIssueResolutionProposal>[proposal],
          groupedIdenticalValues: false,
        ),
      );
      continue;
    }

    if (proposal.proposedAction == LampIssueResolutionAction.unresolved) {
      handledIndices.add(i);
      units.add(LampUnresolvedOrchestrationUnit(proposal));
    }
  }

  return units;
}
