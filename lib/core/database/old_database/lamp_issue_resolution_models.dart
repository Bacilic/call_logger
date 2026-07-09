import 'resolution_log_entry.dart';

typedef ResolutionLogSink = void Function(ResolutionLogEntry entry);

enum LampIssueType {
  nonNumericFk('non_numeric_fk', 'Επίλυση · Μη αριθμητικό Κλειδί Αναφοράς'),
  unknownId('unknown_id', 'Επίλυση · Ασύμβατο Αναγνωριστικό'),
  duplicateAssetNo('duplicate_asset_no', 'Επίλυση · Διπλότυποι αριθμοί παγίου'),
  duplicateModelSerial(
    'duplicate_model_serial',
    'Επίλυση · Διπλότυποι συνδυασμοί μοντέλου / σειριακού',
  ),
  setMasterSelfReference(
    'set_master_self_reference',
    'Επίλυση · Κύριος εξοπλισμός που δείχνει στον ίδιο εξοπλισμό',
  ),
  setMasterCycle(
    'set_master_cycle',
    'Επίλυση · Κύκλοι ιεραρχίας Κύριου εξοπλισμού',
  );

  const LampIssueType(this.issueType, this.label);

  final String issueType;
  final String label;
}

enum LampIssueResolutionAction {
  autoFix('auto_fix'),
  manualReview('manual_review'),
  unresolved('unresolved'),
  createNew('create_new');

  const LampIssueResolutionAction(this.jsonValue);
  final String jsonValue;
}

extension LampIssueResolutionActionLabelsEl on LampIssueResolutionAction {
  /// Ετικέτα εμφάνισης (το [jsonValue] παραμένει για αποθήκευση / JSON).
  String get labelEl {
    switch (this) {
      case LampIssueResolutionAction.autoFix:
        return 'Αυτόματη διόρθωση';
      case LampIssueResolutionAction.createNew:
        return 'Νέα εγγραφή';
      case LampIssueResolutionAction.manualReview:
        return 'Χειροκίνητη επισκόπηση';
      case LampIssueResolutionAction.unresolved:
        return 'Ανεπίλυτο';
    }
  }
}

class LampIssueResolutionOption {
  const LampIssueResolutionOption({
    required this.id,
    required this.label,
    required this.action,
    this.description,
    this.proposedId,
    this.proposedMatch,
    this.confidence,
    this.requiresTextInput = false,
    this.inputLabel,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String label;
  final LampIssueResolutionAction action;
  final String? description;
  final int? proposedId;
  final String? proposedMatch;
  final int? confidence;
  final bool requiresTextInput;
  final String? inputLabel;
  final Map<String, Object?> metadata;
}

class LampIssueResolutionProposal {
  const LampIssueResolutionProposal({
    required this.issueType,
    required this.issueIds,
    required this.sheet,
    required this.row,
    required this.column,
    required this.originalValue,
    required this.proposedAction,
    this.proposedId,
    this.proposedMatch,
    required this.confidence,
    this.options = const <LampIssueResolutionOption>[],
    required this.notes,
    this.metadata = const <String, Object?>{},
  });

  final LampIssueType issueType;
  final List<int> issueIds;
  final String? sheet;
  final int? row;
  final String? column;
  final String? originalValue;
  final LampIssueResolutionAction proposedAction;
  final int? proposedId;
  final String? proposedMatch;
  final int confidence;
  final List<LampIssueResolutionOption> options;
  final String notes;
  final Map<String, Object?> metadata;

  bool get canApplyAutomatically =>
      proposedAction == LampIssueResolutionAction.autoFix ||
      proposedAction == LampIssueResolutionAction.createNew;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sheet': sheet,
      'row': row,
      'column': column,
      'original_value': originalValue,
      'proposed_action': proposedAction.jsonValue,
      'proposed_id': proposedId,
      'proposed_match': proposedMatch,
      'confidence': confidence,
      'options': <Map<String, Object?>>[
        for (final option in options)
          <String, Object?>{
            'id': option.id,
            'label': option.label,
            'proposed_id': option.proposedId,
            'proposed_match': option.proposedMatch,
          },
      ],
      'notes': notes,
    };
  }
}

class LampIssueResolutionDecision {
  const LampIssueResolutionDecision({
    required this.proposal,
    this.option,
    this.textInput,
  });

  final LampIssueResolutionProposal proposal;
  final LampIssueResolutionOption? option;
  final String? textInput;
}

class LampIssueResolutionApplyResult {
  const LampIssueResolutionApplyResult({
    required this.resolved,
    required this.manualApplied,
    required this.created,
    required this.unresolved,
    required this.errors,
  });

  final int resolved;
  final int manualApplied;
  final int created;
  final int unresolved;
  final List<String> errors;

  int get totalChanged => resolved + manualApplied + created;
}
