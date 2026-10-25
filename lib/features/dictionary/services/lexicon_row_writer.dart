import '../../../core/database/database_helper.dart';
import '../../../core/database/dictionary_repository.dart';
import '../../../core/services/dictionary_service.dart';
import '../../../core/services/master_dictionary_service.dart';

/// Πού κατέληξε μια λέξη μετά την εγγραφή — ό,τι χρειάζεται η λίστα για να
/// ενημερώσει τη γραμμή χωρίς ξαναφόρτωση.
class LexiconRowWriteResult {
  const LexiconRowWriteResult({
    required this.entryId,
    required this.src,
    this.lang,
  });

  final int? entryId;
  final String src;
  final String? lang;
}

/// Οι εγγραφές μιας γραμμής του Λεξικού: διόρθωση, διαγραφή, έγκριση.
///
/// Ένας δρόμος για όλους: η επεξεργασία με το χέρι και ο μαζικός έλεγχος με
/// ΤΝ γράφουν από εδώ, ώστε να ισχύουν οι ίδιοι κανόνες για πρόχειρο, χρήστη
/// και εισαγωγή. Κανόνας: λέξη που ελέγχθηκε από άνθρωπο — διορθώθηκε ή
/// εγκρίθηκε — γίνεται «Χρήστης» και φεύγει από την ουρά της Εισαγωγής.
class LexiconRowWriter {
  LexiconRowWriter(
    this._master, {
    Future<DictionaryRepository> Function()? repository,
  }) : _repository = repository ?? _defaultRepository;

  final MasterDictionaryService _master;
  final Future<DictionaryRepository> Function() _repository;

  static Future<DictionaryRepository> _defaultRepository() async =>
      DictionaryRepository(await DatabaseHelper.instance.database);

  static bool isDraft(Map<String, dynamic> row) =>
      row['entry_id'] == null ||
      row['src'] == DictionaryRepository.kLexiconSourceDraft;

  /// Νέα γραφή ή κατηγορία. `null` όταν δεν άλλαξε τίποτα.
  Future<LexiconRowWriteResult?> update(
    Map<String, dynamic> row,
    String displayWord,
    String category,
  ) async {
    final entryId = row['entry_id'] as int?;
    final normKey = row['norm_key'] as String? ?? '';
    final display = row['display_word'] as String? ?? '';
    final src = row['src'] as String? ?? '';
    final lang = row['lang'] as String? ?? 'el';
    final prevCat = row['cat'] as String? ?? 'Γενική';

    if (displayWord == display && category == prevCat) return null;

    if (isDraft(row)) {
      await _master.microMergeUserDraft(
        normalizedKey: normKey,
        displayWord: displayWord,
        category: category,
        language: lang,
      );
      final promoted = await (await _repository())
          .findFullDictionaryEntryByNormalizedWord(
            DictionaryService.canonicalLexiconKey(displayWord),
          );
      return LexiconRowWriteResult(
        entryId: promoted?['id'] as int?,
        src: promoted?['source'] as String? ?? 'user',
        lang: promoted?['language'] as String?,
      );
    }

    final renamed = displayWord != display;
    final dict = await _repository();
    await dict.upsertFullDictionaryCategory(
      id: entryId!,
      category: category,
      newDisplayWord: renamed ? displayWord : null,
    );
    if ((row['pending_user'] as int? ?? 0) == 1 && renamed) {
      final newKey = DictionaryService.canonicalLexiconKey(displayWord);
      if (newKey != normKey) {
        await dict.updateUserDictionaryWordKey(
          normKey,
          newKey,
          displayWord: displayWord,
        );
      }
    }
    return LexiconRowWriteResult(entryId: entryId, src: renamed ? 'user' : src);
  }

  /// Σβήνει τη λέξη από το Πλήρες Λεξικό και από το πρόχειρο.
  Future<void> delete(Map<String, dynamic> row) async {
    final dict = await _repository();
    final normKey = row['norm_key'] as String? ?? '';
    if (!isDraft(row)) {
      await dict.hardDeleteFullDictionaryById(row['entry_id'] as int);
    }
    await dict.deleteUserDictionaryWord(normKey);
  }

  /// Η λέξη είναι σωστή όπως είναι: γίνεται «Χρήστης» — και το πρόχειρο
  /// μπαίνει στο Πλήρες Λεξικό, όπως όταν το επεξεργάζεται κανείς.
  Future<void> approve(Map<String, dynamic> row) async {
    if (isDraft(row)) {
      await _master.microMergeUserDraft(
        normalizedKey: row['norm_key'] as String? ?? '',
        displayWord: row['display_word'] as String? ?? '',
        category: row['cat'] as String? ?? 'Γενική',
        language: row['lang'] as String?,
      );
      return;
    }
    await (await _repository()).markFullDictionaryEntryAsUser(
      row['entry_id'] as int,
    );
  }
}
