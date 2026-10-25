import '../../../core/services/dictionary_service.dart';
import 'lexicon_ai_prompts.dart';
import 'lexicon_row_writer.dart';

/// Τι θα γίνει σε μία λέξη αν ο χρήστης το εγκρίνει.
enum LexiconReviewAction {
  /// Νέα γραφή.
  fix,

  /// Η σωστή γραφή υπάρχει ήδη στο λεξικό: φεύγει η λάθος.
  deleteDuplicate,

  /// Δεν είναι λέξη.
  delete,

  /// Σωστή όπως είναι: γίνεται «Χρήστης».
  approve,

  /// Η ΤΝ δεν απάντησε για αυτήν — μένει ως είναι.
  none,
}

/// Μία γραμμή του παραθύρου ελέγχου.
class LexiconReviewItem {
  const LexiconReviewItem({
    required this.row,
    required this.action,
    this.suggestion = '',
    this.sure = false,
  });

  final Map<String, dynamic> row;
  final LexiconReviewAction action;

  /// Η νέα γραφή, ή στη [LexiconReviewAction.deleteDuplicate] η λέξη που
  /// υπάρχει ήδη.
  final String suggestion;
  final bool sure;

  String get word => row['display_word'] as String? ?? '';
  bool get applicable => action != LexiconReviewAction.none;

  /// Τσεκαρισμένη από την αρχή: μόνο όσα η ΤΝ έκρινε με βεβαιότητα.
  bool get preselected => applicable && sure;
}

/// Οι προτάσεις της ΤΝ ως ενέργειες, με τη σειρά που τις διαβάζει ο χρήστης:
/// πρώτα ό,τι αλλάζει (διορθώσεις, διαγραφές), μετά οι σωστές, στο τέλος όσες
/// έμειναν αναπάντητες.
///
/// Διόρθωση προς γραφή που υπάρχει ήδη ως άλλη λέξη γίνεται διαγραφή της
/// λάθος: η μετονομασία θα απορριπτόταν («υπάρχει ήδη στο λεξικό»). Ο
/// [existingEntryId] δίνει τον αριθμό εγγραφής μιας λέξης του Πλήρους
/// Λεξικού από το κανονικοποιημένο κλειδί της.
Future<List<LexiconReviewItem>> planLexiconReview({
  required List<Map<String, dynamic>> rows,
  required Map<int, LexiconAiVerdict> verdicts,
  required Future<int?> Function(String normalizedKey) existingEntryId,
}) async {
  final items = <LexiconReviewItem>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final verdict = verdicts[i + 1];
    items.add(
      verdict == null
          ? LexiconReviewItem(row: row, action: LexiconReviewAction.none)
          : await _itemFor(row, verdict, existingEntryId),
    );
  }
  final ordered = [
    for (final action in LexiconReviewAction.values)
      ...items.where((item) => item.action == action),
  ];
  return ordered;
}

Future<LexiconReviewItem> _itemFor(
  Map<String, dynamic> row,
  LexiconAiVerdict verdict,
  Future<int?> Function(String normalizedKey) existingEntryId,
) async {
  switch (verdict.kind) {
    case LexiconAiVerdictKind.correct:
      return LexiconReviewItem(
        row: row,
        action: LexiconReviewAction.approve,
        sure: verdict.sure,
      );
    case LexiconAiVerdictKind.delete:
      return LexiconReviewItem(
        row: row,
        action: LexiconReviewAction.delete,
        sure: verdict.sure,
      );
    case LexiconAiVerdictKind.fix:
      final display = row['display_word'] as String? ?? '';
      if (verdict.suggestion == display) {
        return LexiconReviewItem(
          row: row,
          action: LexiconReviewAction.approve,
          sure: verdict.sure,
        );
      }
      final newKey = DictionaryService.canonicalLexiconKey(verdict.suggestion);
      final ownKey = row['norm_key'] as String? ?? '';
      if (newKey != ownKey) {
        final existing = await existingEntryId(newKey);
        if (existing != null && existing != row['entry_id']) {
          return LexiconReviewItem(
            row: row,
            action: LexiconReviewAction.deleteDuplicate,
            suggestion: verdict.suggestion,
            sure: verdict.sure,
          );
        }
      }
      return LexiconReviewItem(
        row: row,
        action: LexiconReviewAction.fix,
        suggestion: verdict.suggestion,
        sure: verdict.sure,
      );
  }
}

/// Τι έγινε στην «Εφαρμογή».
class LexiconReviewApplied {
  const LexiconReviewApplied({
    required this.fixed,
    required this.deleted,
    required this.approved,
    required this.failed,
  });

  final int fixed;
  final int deleted;
  final int approved;

  /// Λέξεις που δεν γράφτηκαν (π.χ. δύο διορθώσεις προς την ίδια γραφή).
  final List<String> failed;
}

/// Γράφει τις [chosen] από τον ίδιο δρόμο με την επεξεργασία με το χέρι. Μία
/// λέξη που αποτυγχάνει δεν σταματά τις υπόλοιπες.
Future<LexiconReviewApplied> applyLexiconReview(
  List<LexiconReviewItem> chosen,
  LexiconRowWriter writer,
) async {
  var fixed = 0, deleted = 0, approved = 0;
  final failed = <String>[];
  for (final item in chosen) {
    try {
      switch (item.action) {
        case LexiconReviewAction.fix:
          final cat = (item.row['cat'] as String?)?.trim() ?? '';
          await writer.update(
            item.row,
            item.suggestion,
            cat.isEmpty ? 'Γενική' : cat,
          );
          fixed++;
        case LexiconReviewAction.delete:
        case LexiconReviewAction.deleteDuplicate:
          await writer.delete(item.row);
          deleted++;
        case LexiconReviewAction.approve:
          await writer.approve(item.row);
          approved++;
        case LexiconReviewAction.none:
          break;
      }
    } on Exception {
      failed.add(item.word);
    }
  }
  return LexiconReviewApplied(
    fixed: fixed,
    deleted: deleted,
    approved: approved,
    failed: failed,
  );
}
