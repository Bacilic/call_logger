import 'resolution_log_entry.dart';

// Το πρότυπο αρίθμησης ταξιδεύει μέσα στο [LampIssueResolutionDecision]·
// όποιος φτιάχνει απόφαση χρειάζεται και τα εργαλεία του.
export 'lamp_serial_series.dart';

typedef ResolutionLogSink = void Function(ResolutionLogEntry entry);

enum LampIssueType {
  nonNumericFk('non_numeric_fk', 'Επίλυση · Μη αριθμητικό Κλειδί Αναφοράς'),
  unknownId('unknown_id', 'Επίλυση · Ασύμβατο Αναγνωριστικό'),
  duplicateAssetNo('duplicate_asset_no', 'Επίλυση · Διπλότυποι αριθμοί παγίου'),
  duplicateModelSerial(
    'duplicate_model_serial',
    'Επίλυση · Διπλότυποι συνδυασμοί μοντέλου / σειριακού',
  ),
  scientificSerial(
    'serial_scientific_notation',
    'Επίλυση · Σειριακοί σε επιστημονική μορφή',
  ),
  setMasterSelfReference(
    'set_master_self_reference',
    'Επίλυση · Κύριος εξοπλισμός που δείχνει στον ίδιο εξοπλισμό',
  ),
  setMasterCycle(
    'set_master_cycle',
    'Επίλυση · Κύκλοι ιεραρχίας Κύριου εξοπλισμού',
  ),
  setMasterMissingTarget(
    'set_master_missing_target',
    'Επίλυση · Κύριος εξοπλισμός χωρίς υπαρκτό στόχο',
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

/// Κλειδί metadata: ο υποψήφιος δεν έχει κανέναν συνδεδεμένο εξοπλισμό.
///
/// Σημαίνεται με σπασμένο σύνδεσμο **μόνο** στον οδηγό επίλυσης, όπου η
/// πληροφορία αλλάζει απόφαση: τέτοιοι υποψήφιοι συνήθως απορρίπτονται.
const String kLampOptionUnlinkedFlag = 'unlinkedReference';

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
    this.requiresPlacementInput = false,
    this.requiresContractInput = false,
    this.requiresSerialSeriesInput = false,
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

  /// Η επιλογή ανοίγει **δύο** συνδεδεμένα πεδία, γραφείο και υπάλληλο, αντί
  /// για ένα πεδίο κειμένου. Ο υπάλληλος είναι προαιρετικός: μισή σωστή
  /// τοποθέτηση αξίζει περισσότερο από καμία.
  final bool requiresPlacementInput;

  /// Η επιλογή ανοίγει τα πεδία δημιουργίας σύμβασης: όνομα, προμηθευτής,
  /// κατηγορία.
  final bool requiresContractInput;

  /// Η επιλογή ανοίγει τον διακόπτη μορφής και την προεπισκόπηση αρίθμησης.
  final bool requiresSerialSeriesInput;

  final String? inputLabel;
  final Map<String, Object?> metadata;
}

/// Τι διάλεξε ο χρήστης στα δύο πεδία τοποθέτησης.
class LampPlacementInput {
  const LampPlacementInput({required this.officeId, this.ownerId});

  final int officeId;

  /// `null` όταν ο χρήστης ξέρει το γραφείο αλλά όχι τον κάτοχο.
  final int? ownerId;
}

/// Τα στοιχεία μιας νέας σύμβασης, όπως τα συμπλήρωσε ο χρήστης.
class LampContractInput {
  const LampContractInput({
    required this.name,
    this.supplierId,
    this.categoryId,
  });

  /// Το όνομα της σύμβασης — προσυμπληρώνεται από την ωμή τιμή.
  final String name;

  /// Προμηθευτής από τους ήδη καταχωρημένους· `null` όταν δεν είναι γνωστός.
  final int? supplierId;

  final int? categoryId;
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
    this.placementInput,
    this.contractInput,
    this.serialSeriesTemplate,
  });

  final LampIssueResolutionProposal proposal;
  final LampIssueResolutionOption? option;
  final String? textInput;

  /// Συμπληρωμένο μόνο όταν η επιλογή ζητά γραφείο και υπάλληλο.
  final LampPlacementInput? placementInput;

  /// Συμπληρωμένο μόνο όταν η επιλογή δημιουργεί σύμβαση.
  final LampContractInput? contractInput;

  /// Το πρότυπο αρίθμησης, όταν η επιλογή αριθμεί σειρά.
  final String? serialSeriesTemplate;
}

/// Πράξεις επίλυσης ανεπίλυτων προτάσεων (metadata `operation`).
abstract final class LampIssueResolutionOperations {
  static const String setFieldManual = 'set_field_manual';
  static const String clearField = 'clear_field';
  static const String deferIssue = 'defer_issue';
}

/// Πίνακας-στόχος για χειροκίνητη σύνδεση κωδικού FK.
class ManualFkTargetSpec {
  const ManualFkTargetSpec({
    required this.table,
    required this.idColumn,
    required this.labelColumn,
  });

  final String table;
  final String idColumn;
  final String labelColumn;

  static ManualFkTargetSpec? forColumn(String? column) {
    return switch (column?.trim().toLowerCase()) {
      'model' => const ManualFkTargetSpec(
        table: 'model',
        idColumn: 'model',
        labelColumn: 'model_name',
      ),
      'contract' => const ManualFkTargetSpec(
        table: 'contracts',
        idColumn: 'contract',
        labelColumn: 'contract_name',
      ),
      'owner' => const ManualFkTargetSpec(
        table: 'owners',
        idColumn: 'owner',
        labelColumn: 'owner',
      ),
      'office' => const ManualFkTargetSpec(
        table: 'offices',
        idColumn: 'office',
        labelColumn: 'office_name',
      ),
      'set_master' => const ManualFkTargetSpec(
        table: 'equipment',
        idColumn: 'code',
        labelColumn: 'description',
      ),
      _ => null,
    };
  }
}

/// Πρόταση autocomplete κωδικού/ονόματος για χειροκίνητη σύνδεση FK.
class LampEntityCodeSuggestion {
  const LampEntityCodeSuggestion({required this.code, required this.label});

  final int code;
  final String label;

  String get displayText => '$label ($code)';
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
