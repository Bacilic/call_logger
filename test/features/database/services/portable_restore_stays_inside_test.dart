// Οι εγγραφές ενός αντιγράφου δεν βγαίνουν ποτέ έξω από τον φάκελο που τους
// ανήκει.
//
// Το αντίγραφο που φτιάχνει η ίδια η εφαρμογή δεν έχει τέτοιες διαδρομές —
// αλλά ο επιλογέας επαναφοράς δέχεται ΟΠΟΙΟΔΗΠΟΤΕ `.zip` δώσει ο χρήστης, και
// στο νοσοκομείο τα αρχεία ταξιδεύουν. Ένα «maps_images/../evil.txt» έγραφε
// δίπλα στο εκτελέσιμο της εφαρμογής (επαληθεύτηκε ζωντανά 13/09/2026).
//
//   flutter test test/features/database/services/portable_restore_stays_inside_test.dart

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:call_logger/features/database/services/database_backup_service.dart';
import 'package:call_logger/features/database/services/restore_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late String mapsRoot;
  late String imagesRoot;
  late String dictRoot;
  late String lampRoot;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('portable_escape_');
    // Οι ρίζες μπαίνουν ΒΑΘΙΑ μέσα στον δοκιμαστικό χώρο επίτηδες: με ρηχή
    // τοποθέτηση, ένα «../../../» θα έγραφε έξω από τον χώρο και το τεστ θα
    // περνούσε βλέποντας «κανένα αρχείο» — ψεύτικο πράσινο πάνω σε αληθινή
    // διαφυγή. Μετρήθηκε: το αρχείο κατέληξε στον φάκελο Temp των Windows.
    final install = p.join(sandbox.path, 'α', 'β', 'γ', 'εγκατάσταση');
    mapsRoot = p.join(install, 'maps_images');
    imagesRoot = p.join(install, 'images');
    dictRoot = p.join(install, 'dictionaries');
    lampRoot = p.join(install, 'Data Base');
  });

  tearDown(() {
    try {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    } catch (_) {}
  });

  Archive archiveWith(Map<String, String> entries) {
    final archive = Archive();
    entries.forEach((name, content) {
      final bytes = content.codeUnits;
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return archive;
  }

  Future<
    ({
      int mapImagesCopied,
      int mapImagesFailed,
      int toolImagesCopied,
      int toolImagesFailed,
      int dictionaryFilesCopied,
      int dictionaryFilesFailed,
      String? restoredLampDbPath,
      bool lampDbFailed,
      List<String> warnings,
    })
  >
  restore(Archive archive) {
    return DatabaseBackupService.copyPortableEntriesFromArchive(
      archive: archive,
      mapsRoot: mapsRoot,
      imagesRoot: imagesRoot,
      dictionariesRoot: dictRoot,
      lampDataBaseRoot: lampRoot,
      parts: const {
        RestorePortablePart.maps,
        RestorePortablePart.toolImages,
        RestorePortablePart.lexicon,
        RestorePortablePart.lampDatabase,
      },
    );
  }

  /// Κάθε αρχείο που γράφτηκε οπουδήποτε μέσα στον δοκιμαστικό χώρο.
  List<String> filesWritten() => sandbox
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => p.relative(f.path, from: sandbox.path))
      .toList()
    ..sort();

  test('κανένα τεστ δεν γράφει έξω από τον δοκιμαστικό χώρο', () {
    // Φύλακας του ίδιου του τεστ: αν η δικλείδα σπάσει ξανά, θέλουμε να το
    // μάθουμε από αποτυχία, όχι από ένα ορφανό αρχείο στο Temp.
    expect(p.isWithin(sandbox.path, mapsRoot), isTrue);
    expect(
      p.split(p.relative(mapsRoot, from: sandbox.path)).length,
      greaterThanOrEqualTo(4),
      reason: 'Αρκετό βάθος ώστε τρία βήματα προς τα πάνω να μένουν ορατά',
    );
  });

  test('η κανονική περίπτωση: κάθε αρχείο πάει στον φάκελό του', () async {
    final outcome = await restore(
      archiveWith({
        'maps_images/ισόγειο.png': 'κάτοψη',
        'images/εργαλείο.png': 'εικονίδιο',
        'dictionaries/core.txt': 'λέξη',
      }),
    );

    expect(outcome.mapImagesCopied, 1);
    expect(outcome.toolImagesCopied, 1);
    expect(outcome.dictionaryFilesCopied, 1);
    expect(File(p.join(mapsRoot, 'ισόγειο.png')).existsSync(), isTrue);
  });

  test('υποφάκελος μέσα στον φάκελο επιτρέπεται', () async {
    // Το λεξικό έχει πραγματικά υποφακέλους — η δικλείδα δεν πρέπει να τους
    // μπερδέψει με διαφυγή.
    final outcome = await restore(
      archiveWith({'dictionaries/ιατρικά/όροι.txt': 'λέξη'}),
    );

    expect(outcome.dictionaryFilesCopied, 1);
    expect(
      File(p.join(dictRoot, 'ιατρικά', 'όροι.txt')).existsSync(),
      isTrue,
    );
  });

  group('διαδρομές διαφυγής', () {
    test('ένα βήμα προς τα πάνω δεν βγαίνει από τον φάκελο', () async {
      final outcome = await restore(
        archiveWith({'maps_images/../ΑΠΟΔΕΙΞΗ.txt': 'διαφυγή'}),
      );

      expect(
        filesWritten(),
        isEmpty,
        reason: 'Τίποτα δεν γράφτηκε πουθενά μέσα στον δοκιμαστικό χώρο',
      );
      expect(
        outcome.warnings,
        isNotEmpty,
        reason: 'Η παράλειψη λέγεται — δεν γίνεται στη σιωπή',
      );
      expect(outcome.mapImagesCopied, 0);
    });

    test('πολλά βήματα προς τα πάνω ούτε αυτά', () async {
      await restore(
        archiveWith({'maps_images/../../../ΡΙΖΑ.txt': 'διαφυγή'}),
      );
      expect(filesWritten(), isEmpty);
    });

    test('ανάποδη κάθετος των Windows δεν παρακάμπτει τον έλεγχο', () async {
      await restore(
        archiveWith({r'maps_images\..\ΑΠΟΔΕΙΞΗ.txt': 'διαφυγή'}),
      );
      expect(filesWritten(), isEmpty);
    });

    test('απόλυτη διαδρομή με γράμμα δίσκου απορρίπτεται', () async {
      // Το `p.join` με απόλυτο δεύτερο όρισμα ΑΓΝΟΕΙ εντελώς το root.
      final outcome = await restore(
        archiveWith({'maps_images/C:/Windows/Temp/ΕΞΩ.txt': 'διαφυγή'}),
      );
      expect(filesWritten(), isEmpty);
      expect(outcome.warnings, isNotEmpty);
    });

    test('και στους τέσσερις φακέλους ισχύει ο ίδιος κανόνας', () async {
      final outcome = await restore(
        archiveWith({
          'maps_images/../μία.txt': 'x',
          'images/../δύο.txt': 'x',
          'dictionaries/../τρία.txt': 'x',
          'lamp_db/../τέσσερα.txt': 'x',
        }),
      );

      expect(filesWritten(), isEmpty);
      expect(
        outcome.warnings.length,
        4,
        reason: 'Κάθε παράλειψη έχει τη δική της προειδοποίηση',
      );
    });

    test('η ύποπτη εγγραφή δεν ακυρώνει τις υγιείς', () async {
      // Η κρίσιμη διαφορά από τον εγκαταστάτη ενημερώσεων: εκεί μια ύποπτη
      // εγγραφή ακυρώνει το πακέτο. Εδώ ο χρήστης επαναφέρει ό,τι έχει —
      // το να χάσει 14 κατόψεις εξαιτίας μιας κακής εγγραφής θα ήταν η ίδια
      // η απώλεια που ήρθε να αποτρέψει.
      final outcome = await restore(
        archiveWith({
          'maps_images/ισόγειο.png': 'κάτοψη',
          'maps_images/../ΚΑΚΟ.txt': 'διαφυγή',
          'maps_images/όροφος.png': 'κάτοψη',
        }),
      );

      expect(outcome.mapImagesCopied, 2);
      expect(outcome.warnings, hasLength(1));
      expect(
        filesWritten().map(p.basename),
        containsAll(<String>['ισόγειο.png', 'όροφος.png']),
      );
    });
  });
}
