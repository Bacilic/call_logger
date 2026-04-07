import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../database/database_helper.dart';
import '../database/dictionary_repository.dart';
import '../utils/lexicon_word_metrics.dart';
import '../errors/dictionary_export_exception.dart';
import '../models/dictionary_import_mode.dart';
import 'dictionary_service.dart';
import 'settings_service.dart';

/// Εισαγωγές στο `full_dictionary` και Compile (εξαγωγή TXT).
class MasterDictionaryService {
  MasterDictionaryService({DictionaryRepository? dictionaryRepository})
      : _dictionaryRepository = dictionaryRepository;

  final DictionaryRepository? _dictionaryRepository;

  Future<DictionaryRepository> _dict() async {
    final injected = _dictionaryRepository;
    if (injected != null) return injected;
    final sqlite = await DatabaseHelper.instance.database;
    return DictionaryRepository(sqlite);
  }

  /// Εισαγωγή από bundled asset (ίδια κατηγορία πηγής με αρχείο TXT: `imported`).
  Future<void> importFromAsset(DictionaryImportMode mode) async {
    final text = await rootBundle.loadString(AppConfig.greekDictionaryAsset);
    await _importFromLineText(text, mode, source: 'imported');
  }

  /// Εισαγωγή από αρχείο δίσκου (.txt).
  Future<void> importFromTxtFile(
    String filePath,
    DictionaryImportMode mode,
  ) async {
    final text = await File(filePath).readAsString();
    await _importFromLineText(text, mode, source: 'imported');
  }

  Future<void> _importFromLineText(
    String text,
    DictionaryImportMode mode, {
    required String source,
  }) async {
    final dict = await _dict();
    if (mode == DictionaryImportMode.replace) {
      await dict.clearFullDictionary();
    }
    final lines = const LineSplitter().convert(text);
    final batch = <Map<String, dynamic>>[];
    for (final line in lines) {
      final display = line.trim();
      if (display.isEmpty || display.startsWith('#')) continue;
      final norm = DictionaryService.canonicalLexiconKey(display);
      if (norm.length < 2) continue;
      final lang = DictionaryRepository.detectDictionaryLanguage(display);
      batch.add({
        'word': display,
        'normalized_word': norm,
        'source': source,
        'language': lang,
        'category': AppConfig.lexiconCategoryUnspecified,
      });
    }
    await dict.batchInsertFullDictionaryRows(batch);
  }

  /// Write-ahead Compile: γράφει `.tmp`, μετά transaction merge user→full + clear user, τέλος rename.
  Future<void> compileExportToTxt() async {
    final exportPath = await SettingsService().getDictionaryExportPath();
    if (exportPath == null || exportPath.trim().isEmpty) {
      throw DictionaryExportPathMissingException();
    }
    final finalPath = exportPath.trim();
    final tmpPath = '$finalPath.tmp';

    List<String> lines;
    try {
      lines = await (await _dict()).getDictionaryExportDisplayLinesOrdered();
    } catch (e, st) {
      Error.throwWithStackTrace(e, st);
    }

    final tmp = File(tmpPath);
    try {
      final sink = tmp.openWrite(encoding: utf8);
      try {
        for (final w in lines) {
          sink.writeln(w);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }

    try {
      await (await _dict()).mergeUserToFullDictionary();
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }

    final dest = File(finalPath);
    try {
      if (await dest.exists()) {
        await dest.delete();
      }
      await tmp.rename(finalPath);
    } catch (e) {
      rethrow;
    }
  }

  static final RegExp _kCustomWordsSplitPattern = RegExp(r'[,\s]+');

  /// Προσθήκη μίας λέξης (αντίστοιχο σε [addCustomWords] με ένα στοιχείο).
  Future<void> addCustomWord({
    required String word,
    required String category,
  }) =>
      addCustomWords(input: word, category: category);

  /// Προσθήκη πολλών λέξεων (διαχωρισμός με κενά/κόμμα), all-or-nothing.
  ///
  /// Αν υπάρχει οποιοδήποτε σφάλμα, ρίχνει [Exception] με όλες τις γραμμές
  /// ενωμένες με `\\n`· δεν εκτελείται κανένα INSERT.
  Future<void> addCustomWords({
    required String input,
    required String category,
  }) async {
    final seen = <String>{};
    final unique = <String>[];
    for (final part in input.split(_kCustomWordsSplitPattern)) {
      final w = part.trim();
      if (w.isEmpty) continue;
      if (seen.add(w)) unique.add(w);
    }
    if (unique.isEmpty) {
      throw Exception('Δεν δόθηκαν λέξεις προς προσθήκη.');
    }

    var cat = category.trim().isEmpty ? 'Γενική' : category.trim();
    if (cat == AppConfig.lexiconCategoryUnspecified) {
      cat = 'Γενική';
    }
    final errors = <String>[];
    final rows = <Map<String, dynamic>>[];
    final dictAdd = await _dict();

    for (final display in unique) {
      if (display.length < 2) {
        errors.add(
          "Η λέξη '$display' πρέπει να έχει τουλάχιστον 2 χαρακτήρες.",
        );
        continue;
      }
      final lang = DictionaryRepository.detectDictionaryLanguage(display);
      if (lang == DictionaryRepository.kLexiconLanguageMix) {
        errors.add(
          "Η λέξη '$display' περιέχει μη αποδεκτούς χαρακτήρες.",
        );
        continue;
      }
      final existing = await dictAdd.countFullDictionaryExactWord(display);
      if (existing > 0) {
        errors.add("Η λέξη '$display' υπάρχει ήδη στο λεξικό.");
        continue;
      }
      final norm = DictionaryService.canonicalLexiconKey(display);
      if (norm.length < 2) {
        errors.add(
          "Η λέξη '$display' έχει πολύ σύντομο κανονικοποιημένο κλειδί.",
        );
        continue;
      }
      final m = LexiconWordMetrics.compute(display);
      rows.add({
        'word': display,
        'normalized_word': norm,
        'source': 'user',
        'language': lang,
        'category': cat,
        'letters_count': m.lettersCount,
        'diacritic_mark_count': m.diacriticMarkCount,
      });
    }

    if (errors.isNotEmpty) {
      throw Exception(errors.join('\n'));
    }

    await dictAdd.db.transaction((txn) async {
      for (final row in rows) {
        await txn.insert(AppConfig.fullDictionaryTable, row);
      }
    });
  }

  /// Micro-merge: metadata στο `full_dictionary`, κλειδί/λέξη στο `user_dictionary` ενημερώνεται αν αλλάζει κείμενο.
  Future<void> microMergeUserDraft({
    required String normalizedKey,
    required String displayWord,
    required String category,
    String? language,
  }) async {
    final lang = language ??
        DictionaryRepository.detectDictionaryLanguage(displayWord);
    final d = await _dict();
    await d.upsertFullFromUserDraft(
      normalizedKey: normalizedKey,
      displayWord: displayWord,
      category: category,
      language: lang,
      source: 'user',
    );
    if (DictionaryService.canonicalLexiconKey(displayWord) != normalizedKey) {
      await d.updateUserDictionaryWordKey(
        normalizedKey,
        DictionaryService.canonicalLexiconKey(displayWord),
      );
    }
  }

  /// Επανυπολογισμός στήλης `language` για όλες τις γραμμές του `full_dictionary`.
  ///
  /// Μόνο όσες εγγραφές αλλάζουν γλώσσα γράφονται στη βάση. Τα batches μέσα σε
  /// **μία** συναλλαγή ώστε να είναι ατομική η ενημέρωση.
  Future<void> recalculateAllLanguages({
    void Function(double progress01)? onProgress,
    int batchSize = 1500,
  }) async {
    onProgress?.call(0);
    final db = (await _dict()).db;

    final userUpdates = <({String word, String lang})>[];
    final userRows = await db.query(
      AppConfig.userDictionaryTable,
      columns: ['word', 'language'],
    );
    for (final r in userRows) {
      final word = (r['word'] as String?)?.trim() ?? '';
      if (word.isEmpty) continue;
      final current = r['language'] as String? ?? '';
      final next = DictionaryRepository.detectDictionaryLanguage(word);
      if (current != next) {
        userUpdates.add((word: word, lang: next));
      }
    }

    final fullUpdates = <({int id, String lang})>[];
    final fullRows = await db.query(
      AppConfig.fullDictionaryTable,
      columns: ['id', 'word', 'language'],
    );
    for (final r in fullRows) {
      final idRaw = r['id'];
      final id = idRaw is int ? idRaw : (idRaw as num).toInt();
      final word = r['word'] as String? ?? '';
      final current = r['language'] as String? ?? '';
      final next = DictionaryRepository.detectDictionaryLanguage(word);
      if (current != next) {
        fullUpdates.add((id: id, lang: next));
      }
    }

    final totalWork = userUpdates.length + fullUpdates.length;
    if (totalWork == 0) {
      onProgress?.call(1);
      return;
    }

    final chunk = math.max(1, batchSize);
    var done = 0;
    void report() => onProgress?.call(done / totalWork);

    await db.transaction((txn) async {
      for (var i = 0; i < userUpdates.length; i += chunk) {
        final end = (i + chunk > userUpdates.length)
            ? userUpdates.length
            : i + chunk;
        final slice = userUpdates.sublist(i, end);
        final b = txn.batch();
        for (final u in slice) {
          b.update(
            AppConfig.userDictionaryTable,
            {'language': u.lang},
            where: 'word = ?',
            whereArgs: [u.word],
          );
        }
        await b.commit(noResult: true);
        done += slice.length;
        report();
      }
      for (var i = 0; i < fullUpdates.length; i += chunk) {
        final end = (i + chunk > fullUpdates.length)
            ? fullUpdates.length
            : i + chunk;
        final slice = fullUpdates.sublist(i, end);
        final b = txn.batch();
        for (final u in slice) {
          b.update(
            AppConfig.fullDictionaryTable,
            {'language': u.lang},
            where: 'id = ?',
            whereArgs: [u.id],
          );
        }
        await b.commit(noResult: true);
        done += slice.length;
        report();
      }
    });
    onProgress?.call(1);
  }
}
