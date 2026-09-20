// Απόδειξη ότι ο Έλεγχος ακεραιότητας πιάνει όσα υπόσχεται.
//
// Ο έλεγχος δηλώνει είκοσι τύπους ευρημάτων. Ως τώρα κανείς δεν είχε δείξει
// ότι τους βρίσκει **όλους**: κάθε τεστ έστηνε το δικό του ελάττωμα, οπότε
// όποιος τύπος δεν είχε τεστ απλώς δεν ελεγχόταν — και ένας κανόνας που δεν
// ελέγχεται είναι κανόνας που μπορεί να λέει ψέματα χωρίς να το μάθει κανείς.
// Πικρό παράδειγμα: ο κανόνας «εξοπλισμός χωρίς τμήμα» έβγαλε κάποτε 55 ψευδή
// ευρήματα και μηδέν αληθινά.
//
// Το δίχτυ είναι ο **πραγματικός** σπορέας των «Σεναρίων σφαλμάτων» — αυτός
// που τρέχει ο χρήστης από τις Ρυθμίσεις. Έτσι τα τεστ δεν φυλάνε ένα
// αντίγραφο των ελαττωμάτων: φυλάνε αυτά ακριβώς που βλέπει ο χρήστης.
//
//   flutter test test/features/database/services/integrity_check_coverage_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/database/debug/integrity_debug_seeder_service.dart';
import 'package:call_logger/features/database/models/database_integrity_finding.dart';
import 'package:call_logger/features/database/models/integrity_fix_models.dart';
import 'package:call_logger/features/database/services/database_integrity_fix_service.dart';
import 'package:call_logger/features/database/services/database_integrity_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_setup.dart';

/// Τα δύο διαγνωστικά που ο σπορέας **δεν** μπορεί να φυτέψει, και γιατί.
///
/// Δεν είναι κενό κάλυψης· είναι φύση του ελέγχου:
/// - το `quick_check` αναφέρει φθορά του ίδιου του **αρχείου**, που δεν
///   στήνεται με εγγραφές·
/// - οι παραβιάσεις κανόνων σχέσεων δεν επιτρέπονται πια από το σχήμα, οπότε
///   δεν μπορούν να εισαχθούν με ανοιχτούς τους κανόνες.
/// Οι τύποι που χρειάζονται **απόφαση** πριν διορθωθούν: «σε ποιο τμήμα;»,
/// «σε ποιον χρήστη;». Η σκέτη έγκριση δεν αρκεί, και δεν πρέπει να αρκεί.
const _needsDecision = <IntegrityCheckType>{
  IntegrityCheckType.orphanPhone,
  IntegrityCheckType.usersWithoutDepartment,
  IntegrityCheckType.usersInvalidDepartment,
};

/// Τύποι χωρίς αυτόματη επιδιόρθωση — η αιτία τους δεν είναι στα δεδομένα.
const _noAutoFix = <IntegrityCheckType>{
  IntegrityCheckType.pragmaQuickCheck,
  IntegrityCheckType.foreignKeyViolations,
};

/// Το καθάρισμα μιας σπασμένης σύνδεσης **γεννά** ορφανό τηλέφωνο: το τηλέφωνο
/// μένει πραγματικά χωρίς κάτοχο, οπότε ο έλεγχος λέει την αλήθεια. Δεν είναι
/// αποτυχία της επιδιόρθωσης, είναι συνέπειά της.
const _orphanedByCascade = <IntegrityCheckType>{IntegrityCheckType.orphanPhone};

const _notSeedable = <IntegrityCheckType>{
  IntegrityCheckType.pragmaQuickCheck,
  IntegrityCheckType.foreignKeyViolations,
};

void main() {
  group('Κάλυψη του Ελέγχου ακεραιότητας', () {
    late DatabaseIntegrityService service;
    late String dbPath;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('integrity_coverage_');
      dbPath = '${dir.path}/integrity_coverage.db';
      await DatabaseHelper.bindTestDatabaseFile(dbPath);
      await DatabaseHelper.instance.database;
      service = DatabaseIntegrityService();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      // Ο σπορέας φυτεύει επίτηδες σπασμένες αναφορές — από την v38 η βάση τις
      // απορρίπτει, οπότε το στήσιμο παρακάμπτει τον κανόνα που το ίδιο το
      // σενάριο παραβιάζει.
      await db.execute('PRAGMA foreign_keys = OFF');
      await IntegrityDebugSeederService().seedIntegrityErrorsInto(dbPath);
    });

    test('ο σπορέας φυτεύει ΚΑΘΕ τύπο που μπορεί να φυτευτεί', () async {
      final report = await service.runChecks();
      final found = report.findings.map((f) => f.checkType).toSet();

      final expected = IntegrityCheckType.values
          .where((t) => !_notSeedable.contains(t))
          .toSet();
      final missed = expected.difference(found).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      expect(
        missed,
        isEmpty,
        reason:
            'Ο σπορέας φυτεύει το ελάττωμα αλλά ο έλεγχος ΔΕΝ το βρίσκει — ή ο '
            'σπορέας σταμάτησε να το φυτεύει. Και στις δύο περιπτώσεις ο '
            'κανόνας είναι αναπόδεικτος:\n'
            '${missed.map((t) => '  · ${t.name} (${t.displayNameEl})').join('\n')}',
      );
    });

    // Ένα εύρημα χωρίς ελληνικό τίτλο ή χωρίς βαρύτητα φτάνει στην οθόνη
    // μισό — και ο χρήστης δεν έχει τρόπο να κρίνει αν τον αφορά.
    test('κάθε εύρημα φτάνει πλήρες στην οθόνη', () async {
      final report = await service.runChecks();
      expect(report.findings, isNotEmpty);

      for (final finding in report.findings) {
        expect(
          finding.title.trim(),
          isNotEmpty,
          reason: 'Ο τύπος ${finding.checkType.name} βγήκε χωρίς τίτλο.',
        );
        expect(
          finding.description.trim(),
          isNotEmpty,
          reason:
              'Ο τύπος ${finding.checkType.name} βγήκε χωρίς περιγραφή — ο '
              'χρήστης βλέπει τίτλο και δεν μαθαίνει τι φταίει.',
        );
        // Η ταυτότητα είναι αυτή που αφαιρεί το εύρημα μετά τη διόρθωση· χωρίς
        // αυτήν το εύρημα μένει στην οθόνη σαν να μη διορθώθηκε ποτέ.
        expect(
          finding.findingKey.trim(),
          isNotEmpty,
          reason: 'Ο τύπος ${finding.checkType.name} βγήκε χωρίς ταυτότητα.',
        );
      }
    });

    // ── Δεύτερο μισό: διορθώνει όντως ο κάθε κανόνας; ────────────────────────

    test(
      'η «Διόρθωση όλων» καθαρίζει ΚΑΘΕ τύπο που δέχεται σκέτη έγκριση',
      () async {
        final before = await service.runChecks();
        final fixer = DatabaseIntegrityFixService();

        // Ο ίδιος δρόμος με το κουμπί «Διόρθωση όλων» της οθόνης.
        final bulkTypes = before.findings
            .where((f) => f.checkType.allowsBulkFix)
            .where((f) => !_noAutoFix.contains(f.checkType))
            .toList();
        expect(bulkTypes, isNotEmpty);

        for (final finding in bulkTypes) {
          await fixer.applyFix(finding, const IntegrityFixConfirm());
        }

        final after = await service.runChecks();
        final remaining = after.findings.map((f) => f.checkType).toSet();
        final shouldBeGone = bulkTypes
            .map((f) => f.checkType)
            .toSet()
            .difference(_orphanedByCascade);
        final survivors = shouldBeGone.intersection(remaining).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        expect(
          survivors,
          isEmpty,
          reason:
              'Η επιδιόρθωση δήλωσε ότι έγινε, αλλά ο έλεγχος βρίσκει ακόμη το '
              'ίδιο εύρημα:\n'
              '${survivors.map((t) => '  · ${t.name}').join('\n')}',
        );
      },
    );

    // Τρεις τύποι ΔΕΝ διορθώνονται με σκέτη έγκριση, και σωστά: χρειάζονται
    // απόφαση («σε ποιο τμήμα;», «σε ποιον χρήστη;»). Η οθόνη τους δίνει
    // διάλογο επιλογής αντί για κουμπί επιβεβαίωσης — αυτό το φυλάει εδώ.
    test('όσοι θέλουν απόφαση ΔΕΝ διορθώνονται σιωπηλά', () async {
      final before = await service.runChecks();
      final fixer = DatabaseIntegrityFixService();

      for (final type in _needsDecision) {
        final finding = before.findings.firstWhere(
          (f) => f.checkType == type,
          orElse: () => throw StateError('Ο σπορέας δεν φύτεψε $type.'),
        );
        expect(
          type.allowsBulkFix,
          isFalse,
          reason:
              'Ο τύπος ${type.name} χρειάζεται απόφαση — δεν επιτρέπεται να '
              'μπαίνει στη «Διόρθωση όλων».',
        );
        final result = await fixer.applyFix(
          finding,
          const IntegrityFixConfirm(),
        );
        expect(
          result,
          isA<IntegrityFixFailure>(),
          reason:
              'Ο τύπος ${type.name} δέχτηκε σκέτη έγκριση. Τότε η οθόνη θα '
              'μπορούσε να τον «διορθώσει» χωρίς να ρωτήσει πού.',
        );
      }
    });

    // Ο φύλακας της απογραφής: ένας εικοστός πρώτος τύπος δεν επιτρέπεται να
    // μπει σιωπηλά. Ή τον φυτεύει ο σπορέας, ή δηλώνεται ρητά ως μη φυτεύσιμος
    // — με γραπτό λόγο, εδώ πάνω.
    test('κανένας τύπος δεν μένει αταξινόμητος', () async {
      final report = await service.runChecks();
      final found = report.findings.map((f) => f.checkType).toSet();

      final unclassified = IntegrityCheckType.values
          .where((t) => !found.contains(t) && !_notSeedable.contains(t))
          .toList();

      expect(
        unclassified,
        isEmpty,
        reason:
            'Νέος τύπος ελέγχου χωρίς σενάριο στον σπορέα. Πρόσθεσέ τον εκεί, '
            'ή δήλωσέ τον στο _notSeedable εξηγώντας γιατί δεν φυτεύεται.',
      );
    });
  });
}
