import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/mixed_script_detector.dart';
import 'lamp_issue_resolution_models.dart';
import 'lamp_issue_resolution_support.dart';
import 'old_equipment_repository.dart';

/// Χτίζει τις προτάσεις διόρθωσης για τους αλλοιωμένους χαρακτήρες.
///
/// **Ο κανόνας της κατάταξης:** όπου ο ανιχνευτής βγάζει βέβαιη πρόταση, το
/// εύρημα πάει σε «Αυτόματη διόρθωση» και εφαρμόζεται μαζί με τα υπόλοιπα
/// μετά την επιβεβαίωση. Όπου δεν βγάζει — δύο αλφάβητα ισοφαρίζουν, ή κάποιο
/// γράμμα δεν έχει οπτικό δίδυμο — πάει σε «Χειροκίνητη επισκόπηση» και το
/// κρίνει ο άνθρωπος. Καμία λέξη δεν αλλάζει χωρίς να περάσει από τη μία ή
/// την άλλη πόρτα.
class LampMixedScriptAnalyzer {
  const LampMixedScriptAnalyzer(this._support);

  final LampIssueResolutionSupport _support;

  /// Πόσο σίγουρη είναι μια πρόταση που βγήκε από τον κανόνα της πλειοψηφίας.
  static const int kSuggestionConfidence = 90;

  /// Πόσο σίγουρο είναι ένα εύρημα που περιμένει ανθρώπινη κρίση.
  static const int kManualConfidence = 40;

  Future<List<LampIssueResolutionProposal>> analyze(
    Database db,
    LampIssueType issueType,
  ) async {
    final issues = await _support.openIssues(db, issueType);
    final proposals = <LampIssueResolutionProposal>[];

    for (final issue in issues) {
      final issueId = _support.toInt(issue['id']);
      final rowId = _support.toInt(issue['row_number']);
      final column = _support.text(issue['column_name']);
      final word = _support.text(issue['raw_value']);
      final table = _tableOf(issue);
      if (issueId == null ||
          rowId == null ||
          column == null ||
          word == null ||
          table == null) {
        continue;
      }

      final primaryKey = OldEquipmentRepository.kMixedScriptTables[table];
      if (primaryKey == null) continue;

      // Η τρέχουσα τιμή, όχι εκείνη της σάρωσης: ανάμεσα στη σάρωση και στον
      // οδηγό μπορεί να μεσολάβησε διόρθωση, και μια πρόταση πάνω σε τιμή που
      // δεν υπάρχει πια θα έγραφε σκουπίδια.
      final rows = await db.query(
        table,
        columns: <String>[primaryKey, column],
        where: '$primaryKey = ?',
        whereArgs: <Object?>[rowId],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final currentValue = rows.first[column];
      if (currentValue is! String || !currentValue.contains(word)) continue;

      final finding = findMixedScriptWords(
        word,
      ).where((f) => f.word == word).firstOrNull;
      if (finding == null) continue;

      final suggestion = finding.suggestion;
      final where = '$table=$rowId · πεδίο ${_columnLabel(column)}';
      final notes = suggestion == null
          ? '$where\nΤιμή πεδίου: $currentValue\n'
                'Η λέξη «$word» είναι ύποπτη, αλλά ο κανόνας δεν μπορεί να '
                'αποφασίσει μόνος του ποια μορφή είναι η σωστή.'
          : '$where\nΤιμή πεδίου: $currentValue\n'
                'Η λέξη «$word» γίνεται «$suggestion».';

      proposals.add(
        LampIssueResolutionProposal(
          issueType: issueType,
          issueIds: <int>[issueId],
          sheet: table,
          row: rowId,
          column: column,
          originalValue: word,
          proposedAction: suggestion == null
              ? LampIssueResolutionAction.manualReview
              : LampIssueResolutionAction.autoFix,
          proposedMatch: suggestion,
          confidence: suggestion == null
              ? kManualConfidence
              : kSuggestionConfidence,
          notes: notes,
          metadata: <String, Object?>{
            if (suggestion != null) ...<String, Object?>{
              'operation': LampIssueResolutionOperations.replaceMixedScriptWord,
              'table': table,
              'primaryKey': primaryKey,
              'rowId': rowId,
              'column': column,
              'word': word,
              'replacement': suggestion,
            },
            'currentValue': currentValue,
          },
          options: <LampIssueResolutionOption>[
            if (suggestion != null)
              LampIssueResolutionOption(
                id: 'mixed_script_apply_$issueId',
                label: 'Διόρθωση σε «$suggestion»',
                action: LampIssueResolutionAction.autoFix,
                proposedMatch: suggestion,
                confidence: kSuggestionConfidence,
                metadata: <String, Object?>{
                  'operation':
                      LampIssueResolutionOperations.replaceMixedScriptWord,
                  'table': table,
                  'primaryKey': primaryKey,
                  'rowId': rowId,
                  'column': column,
                  'word': word,
                  'replacement': suggestion,
                },
              ),
            LampIssueResolutionOption(
              id: 'mixed_script_manual_$issueId',
              label: 'Γράψε εσύ τη σωστή μορφή',
              action: LampIssueResolutionAction.manualReview,
              requiresTextInput: true,
              inputLabel: 'Σωστή μορφή της λέξης «$word»',
              metadata: <String, Object?>{
                'operation':
                    LampIssueResolutionOperations.replaceMixedScriptWord,
                'table': table,
                'primaryKey': primaryKey,
                'rowId': rowId,
                'column': column,
                'word': word,
              },
            ),
            LampIssueResolutionOption(
              id: 'mixed_script_skip_$issueId',
              label: 'Άφησέ το όπως είναι',
              action: LampIssueResolutionAction.unresolved,
              description: 'Η λέξη είναι σωστή· το εύρημα αναβάλλεται.',
              metadata: <String, Object?>{
                'operation': LampIssueResolutionOperations.deferIssue,
              },
            ),
          ],
        ),
      );
    }
    return proposals;
  }

  /// Σε ποιον πίνακα ζει το εύρημα.
  ///
  /// Το `entity_type` είναι η κανονική πηγή· το `sheet` κρατιέται ως εφεδρεία
  /// για εγγραφές που γράφτηκαν πριν υπάρξει η στήλη.
  String? _tableOf(Map<String, Object?> issue) {
    final entityType = _support.text(issue['entity_type']);
    if (entityType != null &&
        OldEquipmentRepository.kMixedScriptTables.containsKey(entityType)) {
      return entityType;
    }
    final sheet = _support.text(issue['sheet']);
    if (sheet != null &&
        OldEquipmentRepository.kMixedScriptTables.containsKey(sheet)) {
      return sheet;
    }
    return null;
  }

  static String _columnLabel(String column) {
    switch (column) {
      case 'description':
        return 'περιγραφή';
      case 'comments':
      case 'network_comments':
        return 'σχόλια';
      case 'attributes':
        return 'χαρακτηριστικά';
      case 'consumables':
        return 'αναλώσιμα';
      case 'office_name':
        return 'όνομα γραφείου';
      case 'department_name':
        return 'όνομα τμήματος';
      case 'first_name':
        return 'όνομα';
      case 'last_name':
        return 'επώνυμο';
      case 'model_name':
        return 'όνομα μοντέλου';
      case 'supplier_name':
        return 'προμηθευτής';
      case 'committee':
        return 'επιτροπή';
      case 'serial_no':
        return 'σειριακός αριθμός';
      default:
        return column;
    }
  }
}
