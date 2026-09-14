// Η υπόδειξη του κουμπιού «Επαναφορά από Αντίγραφο Ασφαλείας».
//
// Συμβόλαιο: η ΕΠΑΝΑΦΟΡΑ δεν φιλτράρει με το όνομα της βάσης — ο χρήστης
// βλέπει όλα τα αντίγραφα του φακέλου. Το όνομα μπαίνει μόνο ως πληροφορία,
// ώστε να ξέρει ποια αφορούν τη βάση που δουλεύει τώρα.
//
//   flutter test test/features/database/utils/backup_restore_tooltip_test.dart

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:call_logger/core/config/app_config.dart';
import 'package:call_logger/core/services/building_map_storage.dart';
import 'package:call_logger/core/services/portable_lamp_storage.dart';
import 'package:call_logger/features/database/utils/backup_destination_folder_validator.dart';
import 'package:call_logger/features/database/utils/backup_restore_tooltip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

late Directory _folder;

String _write(String name) {
  final file = File(p.join(_folder.path, name))
    ..writeAsBytesSync(const <int>[1, 2, 3]);
  return file.path;
}

/// Αντίγραφο με πραγματικό περιεχόμενο, για τον έλεγχο των ετικετών.
String _writeZip(String name, List<String> entryNames) {
  final archive = Archive();
  for (final entry in entryNames) {
    archive.addFile(ArchiveFile(entry, 3, <int>[1, 2, 3]));
  }
  final bytes = ZipEncoder().encode(archive);
  final file = File(p.join(_folder.path, name))..writeAsBytesSync(bytes);
  return file.path;
}

Future<String> _tooltip({String dbBaseName = 'Hospital'}) =>
    BackupRestoreTooltipBuilder.build(
      destinationDirectory: _folder.path,
      dbBaseName: dbBaseName,
    );

void main() {
  setUp(() {
    _folder = Directory.systemTemp.createTempSync('tooltip_test');
  });

  tearDown(() {
    if (_folder.existsSync()) _folder.deleteSync(recursive: true);
  });

  group('όταν δεν υπάρχει αρχείο να προταθεί', () {
    test(
      'χωρίς ορισμένο φάκελο, το μήνυμα δεν μιλά για φάκελο που δεν υπάρχει',
      () async {
        final text = await BackupRestoreTooltipBuilder.build(
          destinationDirectory: '   ',
          dbBaseName: 'Hospital',
        );
        expect(text, contains('Δεν έχει οριστεί φάκελος'));
        expect(text, contains(BackupRestoreTooltipBuilder.chooseFreelyHint));
      },
    );

    test(
      'φάκελος που δεν υπάρχει ξεχωρίζει από φάκελο χωρίς αντίγραφα',
      () async {
        final missing = await BackupRestoreTooltipBuilder.build(
          destinationDirectory: p.join(_folder.path, 'δεν-υπάρχει'),
          dbBaseName: 'Hospital',
        );
        expect(missing, contains('δεν είναι προσβάσιμος'));

        final empty = await _tooltip();
        expect(empty, contains('κανένα αρχείο .zip'));
        expect(empty, isNot(contains('δεν είναι προσβάσιμος')));
      },
    );

    test('αρχεία που δεν είναι .zip δεν μετρούν ως αντίγραφα', () async {
      _write('Hospital_2026-09-13_07-15.db');
      _write('σημειώσεις.txt');
      expect(await _tooltip(), contains('κανένα αρχείο .zip'));
    });

    test(
      'κάθε αδιέξοδο κλείνει με την παρότρυνση ελεύθερης επιλογής',
      () async {
        expect(
          await _tooltip(),
          contains(BackupRestoreTooltipBuilder.chooseFreelyHint),
        );
      },
    );
  });

  group('το πλήθος μετράει ΟΛΑ τα αντίγραφα, όχι μόνο της τρέχουσας βάσης', () {
    test('αντίγραφο άλλης βάσης μετριέται και αναφέρεται', () async {
      _write('Hospital_2026-09-13_07-15.zip');
      _write('call_logger_2026-09-12_08-00.zip');
      _write('2026-09-11_09-00_call_logger.zip');

      final text = await _tooltip();
      expect(text, contains('3 αντίγραφα στον φάκελο'));
      expect(text, contains('1 της βάσης «Hospital»'));
    });

    test('όταν κανένα δεν αφορά την τρέχουσα βάση, το λέει ρητά', () async {
      _write('call_logger_2026-09-12_08-00.zip');
      _write('call_logger_2026-09-11_08-00.zip');

      final text = await _tooltip();
      expect(text, contains('2 αντίγραφα στον φάκελο'));
      expect(text, contains('κανένα της βάσης «Hospital»'));
    });

    test(
      'όταν όλα αφορούν την τρέχουσα βάση, η διάκριση θα ήταν θόρυβος',
      () async {
        _write('Hospital_2026-09-13_07-15.zip');
        _write('Hospital_2026-09-12_07-15.zip');

        final text = await _tooltip();
        expect(text, contains('2 αντίγραφα στον φάκελο'));
        expect(text, isNot(contains('της βάσης')));
      },
    );
  });

  group('ποιο αρχείο προτείνεται πρώτο', () {
    test(
      'προτείνεται το πιο πρόσφατο ΤΗΣ ΤΡΕΧΟΥΣΑΣ βάσης, ακόμη κι αν ο φάκελος έχει νεότερο αλλουνού',
      () async {
        final mine = _write('Hospital_2026-09-10_07-15.zip');
        final other = _write('call_logger_2026-09-12_08-00.zip');
        File(mine).setLastModifiedSync(DateTime(2026, 9, 10));
        File(other).setLastModifiedSync(DateTime(2026, 9, 12));

        final text = await _tooltip();
        expect(text, contains('Hospital_2026-09-10_07-15.zip'));
        expect(text, isNot(contains('δεν είναι αντίγραφο της τρέχουσας')));
        expect(
          text,
          contains('2 αντίγραφα στον φάκελο'),
          reason: 'Η προτίμηση δεν κρύβει τα υπόλοιπα από το πλήθος',
        );
      },
    );

    test(
      'χωρίς κανένα αντίγραφο της τρέχουσας βάσης, προτείνεται αλλουνού — και το λέει',
      () async {
        _write('call_logger_2026-09-12_08-00.zip');

        final text = await _tooltip();
        expect(text, contains('call_logger_2026-09-12_08-00.zip'));
        expect(text, contains('δεν είναι αντίγραφο της τρέχουσας βάσης'));
      },
    );

    test('αντίγραφο της τρέχουσας βάσης δεν φέρει την προειδοποίηση', () async {
      _write('Hospital_2026-09-13_07-15.zip');
      final text = await _tooltip();
      expect(text, contains('Hospital_2026-09-13_07-15.zip'));
      expect(text, isNot(contains('δεν είναι αντίγραφο της τρέχουσας')));
    });
  });

  group(
    'οι ετικέτες περιεχομένου είναι οι ίδιες με τον διάλογο επαναφοράς',
    () {
      test('κάθε φάκελος του αντιγράφου δίνει τη δική του ετικέτα', () async {
        final zip = _writeZip('Hospital_2026-09-13_07-15.zip', [
          'Hospital.db',
          '${BuildingMapStorage.backupZipMapsFolderName}/a.webp',
          '${AppConfig.portableImagesDirName}/tool.png',
          '${AppConfig.portableDictionariesDirName}/el.json',
          '${PortableLampStorage.backupZipLampDbFolderName}/lampa.db',
        ]);

        final contents = await BackupRestoreTooltipBuilder.describeZipContents(
          zip,
        );
        expect(contents.problem, isNull);
        expect(contents.labels, [
          'Βάση δεδομένων',
          'Κατόψεις κτιρίων',
          'Εικονίδια εργαλείων και χρηστών',
          'Λεξικό',
          'Βάση Λάμπας',
        ]);
      });

      test('η βάση της Λάμπας δεν περνά για βάση της εφαρμογής', () async {
        final zip = _writeZip('Hospital_2026-09-13_07-15.zip', [
          '${PortableLampStorage.backupZipLampDbFolderName}/lampa.db',
        ]);

        final contents = await BackupRestoreTooltipBuilder.describeZipContents(
          zip,
        );
        expect(contents.labels, ['Βάση Λάμπας']);
      });

      test(
        'χαλασμένο αρχείο: η υπόδειξη το λέει, δεν υπόσχεται βάση',
        () async {
          // Ως τις 14/09 η λίστα περιεχομένων έβγαινε κενή και μια εφεδρεία
          // γέμιζε τη θέση με «Βάση δεδομένων» — υπόσχεση για ό,τι ακριβώς δεν
          // μπορεί να δοθεί. Το τεστ φύλαγε τότε αυτή τη συμπεριφορά.
          _write('Hospital_2026-09-13_07-15.zip');
          final text = await _tooltip();
          expect(text, contains('1 αντίγραφο στον φάκελο'));
          expect(
            text,
            isNot(contains('Βάση δεδομένων')),
            reason: 'Το αρχείο δεν διαβάζεται — δεν ξέρουμε τι έχει μέσα',
          );
          expect(text, isNot(contains('Περιέχει:')));
          expect(text, contains('δεν έχει τη μορφή'));
          expect(
            text,
            contains(BackupRestoreTooltipBuilder.chooseFreelyHint),
            reason: 'Η υπόδειξη δεν σταματά χωρίς διέξοδο',
          );
        },
      );

      test('κομμένο zip: η υπόδειξη λέει ότι είναι χαλασμένο', () async {
        final archive = Archive();
        archive.addFile(ArchiveFile('Hospital.db', 3, <int>[1, 2, 3]));
        final bytes = ZipEncoder().encode(archive);
        File(
          p.join(_folder.path, 'Hospital_2026-09-13_07-15.zip'),
        ).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));

        final text = await _tooltip();
        expect(text, contains('χαλασμένο'));
        expect(text, isNot(contains('Βάση δεδομένων')));
      });

      test('έγκυρο zip χωρίς τίποτα δικό μας: το λέει κι αυτό', () async {
        _writeZip('Hospital_2026-09-13_07-15.zip', const <String>[
          'τυχαίο/αρχείο.txt',
        ]);
        final text = await _tooltip();
        expect(text, contains('δεν περιέχει τίποτα'));
        expect(text, isNot(contains('Βάση δεδομένων')));
      });
    },
  );

  group('η κατάσταση της άλλης καρτέλας ΔΕΝ άλλαξε', () {
    test('εκεί μετρούν μόνο τα αντίγραφα της τρέχουσας βάσης', () async {
      _write('Hospital_2026-09-13_07-15.zip');
      _write('call_logger_2026-09-12_08-00.zip');
      _write('call_logger_2026-09-11_08-00.zip');

      final content =
          await BackupDestinationFolderValidator.inspectDestinationContent(
            destinationDirectory: _folder.path,
            dbBaseName: 'Hospital',
          );
      expect(content.kind, BackupDestinationContentKind.folderOk);
      expect(content.matchingBackupFileCount, 1);

      final survey =
          await BackupDestinationFolderValidator.surveyRestorableZips(
            destinationDirectory: _folder.path,
            dbBaseName: 'Hospital',
          );
      expect(survey.totalZipCount, 3);
      expect(survey.matchingZipCount, 1);
    });
  });
}
