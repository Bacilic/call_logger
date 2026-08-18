// Διάγνωση αρχείου που αντιγράφηκε ΕΝΩ η βάση δούλευε.
//
// Το περιστατικό που γέννησε αυτούς τους ελέγχους: αντιγραφή της ζωντανής
// βάσης με τον Explorer σε κοινόχρηστο φάκελο. Τα διαγνωστικά πρόσβασης
// απάντησαν οκτώ φορές [OK] —το αρχείο υπήρχε, διαβαζόταν, γραφόταν— και η
// εφαρμογή είπε μόνο «φαίνεται κατεστραμμένο». Η μόνη χρήσιμη πρόταση,
// «invalid rootpage», είχε ήδη πεταχτεί.
//
//   flutter test test/core/database/database_copied_while_open_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_file_identity.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Κεφαλίδα SQLite 100 bytes με ελεγχόμενο μέγεθος σελίδας και πλήθος σελίδων.
List<int> _header({required int pageSize, required int pageCount}) {
  final bytes = List<int>.filled(100, 0);
  const magic = 'SQLite format 3';
  for (var i = 0; i < magic.length; i++) {
    bytes[i] = magic.codeUnitAt(i);
  }
  bytes[15] = 0;
  // bytes 16-17: μέγεθος σελίδας (big endian)
  bytes[16] = (pageSize >> 8) & 0xFF;
  bytes[17] = pageSize & 0xFF;
  // bytes 28-31: πλήθος σελίδων (big endian)
  bytes[28] = (pageCount >> 24) & 0xFF;
  bytes[29] = (pageCount >> 16) & 0xFF;
  bytes[30] = (pageCount >> 8) & 0xFF;
  bytes[31] = pageCount & 0xFF;
  return bytes;
}

DatabaseFileIdentity _identity({
  required int pageSize,
  required int pageCount,
  required int fileSize,
}) {
  final parsed = parseDatabaseFileIdentity(
    header: _header(pageSize: pageSize, pageCount: pageCount),
    fileSize: fileSize,
  );
  return parsed!;
}

void main() {
  group('δομικός έλεγχος: χωρά το αρχείο όσες σελίδες δηλώνει;', () {
    test('αρχείο ακριβώς όσο δηλώνει η κεφαλίδα → εντάξει', () {
      final verdict = inspectDatabaseFileStructure(
        _identity(pageSize: 4096, pageCount: 2329, fileSize: 2329 * 4096),
      );
      expect(verdict, DatabaseStructuralVerdict.ok);
    });

    test('αρχείο ΜΙΚΡΟΤΕΡΟ από όσο δηλώνει → κομμένο', () {
      // Ακριβώς η περίπτωση του περιστατικού: ο κατάλογος περιμένει σελίδες
      // που το αρχείο δεν έχει.
      final verdict = inspectDatabaseFileStructure(
        _identity(pageSize: 4096, pageCount: 2542, fileSize: 2329 * 4096),
      );
      expect(verdict, DatabaseStructuralVerdict.truncated);
    });

    test('αρχείο ΜΕΓΑΛΥΤΕΡΟ από όσο δηλώνει → εντάξει, όχι συναγερμός', () {
      // Κατηγορούμε μόνο για το αδύνατο. Παραπανίσια bytes στο τέλος δεν
      // εμποδίζουν καμία ανάγνωση.
      final verdict = inspectDatabaseFileStructure(
        _identity(pageSize: 4096, pageCount: 2329, fileSize: 2542 * 4096),
      );
      expect(verdict, DatabaseStructuralVerdict.ok);
    });

    test('χωρίς ταυτότητα → άγνοια, ποτέ συναγερμός', () {
      expect(
        inspectDatabaseFileStructure(null),
        DatabaseStructuralVerdict.unknown,
      );
    });
  });

  group('υπογραφή «αντιγράφηκε ενώ ήταν ανοιχτή»', () {
    test('invalid rootpage: το ακριβές σφάλμα του περιστατικού', () {
      expect(
        looksLikeCopiedWhileInUseError(
          'DatabaseException(malformed database schema '
          '(call_external_links) - invalid rootpage)',
        ),
        isTrue,
      );
    });

    test('malformed database schema χωρίς rootpage: επίσης υπογραφή', () {
      expect(
        looksLikeCopiedWhileInUseError('malformed database schema (calls)'),
        isTrue,
      );
    });

    test('σκέτο disk image is malformed: ΔΕΝ είναι αυτή η υπογραφή', () {
      // Αυτό μιλά για ό,τι διάβασε η ανοιχτή σύνδεση, όχι για ασυνεπές
      // αρχείο· το χειρίζεται ο φρουρός αντικατάστασης.
      expect(
        looksLikeCopiedWhileInUseError('database disk image is malformed'),
        isFalse,
      );
    });

    test('κλείδωμα ή άλλο σφάλμα: όχι', () {
      expect(looksLikeCopiedWhileInUseError('database is locked'), isFalse);
      expect(looksLikeCopiedWhileInUseError('unable to open database'), isFalse);
    });
  });

  group('τι βλέπει ο χρήστης όταν συμβεί', () {
    test('το ωμό μήνυμα του SQLite διατηρείται ατόφιο', () {
      const raw =
          'DatabaseException(malformed database schema '
          '(call_external_links) - invalid rootpage)';
      final result = DatabaseInitResult.fromException(raw, r'C:\vaseis\x.db');

      expect(result.status, DatabaseStatus.corruptedOrInvalid);
      expect(result.originalExceptionText, contains('invalid rootpage'));
    });

    test('το μήνυμα ονομάζει την αιτία, δεν λέει μόνο «κατεστραμμένο»', () {
      const raw =
          'DatabaseException(malformed database schema '
          '(call_external_links) - invalid rootpage)';
      final result = DatabaseInitResult.fromException(raw, r'C:\vaseis\x.db');

      final shown = '${result.message ?? ''}\n${result.details ?? ''}';
      expect(shown, contains('ανοιχτή'));
    });

    test('γενικό «malformed» κρατά το παλιό, γενικό μήνυμα', () {
      final result = DatabaseInitResult.fromException(
        'database disk image is malformed',
        r'C:\vaseis\x.db',
      );
      expect(result.status, DatabaseStatus.corruptedOrInvalid);
      expect(result.message, isNot(contains('ανοιχτή')));
    });
  });

  group('πραγματικό αρχείο κομμένο στη μέση', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db_torn_copy_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('κεφαλίδα δηλώνει περισσότερες σελίδες από όσες έχει το αρχείο', () async {
      const pageSize = 4096;
      final path = '${tempDir.path}${Platform.pathSeparator}kommeno.db';
      // Κεφαλίδα που υπόσχεται 10 σελίδες, αρχείο που έχει 3.
      final content = <int>[
        ..._header(pageSize: pageSize, pageCount: 10),
        ...List<int>.filled(3 * pageSize - 100, 0),
      ];
      await File(path).writeAsBytes(content);

      final identity = await readDatabaseFileIdentity(path);
      expect(identity, isNotNull);
      expect(identity!.pageCount, 10);
      expect(
        inspectDatabaseFileStructure(identity),
        DatabaseStructuralVerdict.truncated,
      );
    });
  });
}
