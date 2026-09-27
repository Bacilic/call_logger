// Μία απάντηση στο «ίδια διαδρομή;» για όλη την εφαρμογή.
//
//   flutter test test/core/utils/file_path_identity_test.dart

import 'dart:io';

import 'package:call_logger/core/utils/file_path_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('δύο γραφές του ΙΔΙΟΥ αρχείου', () {
    test('κανονικές και ανάποδες κάθετοι', () {
      expect(
        pathsReferToSameFile(
          r'C:\data\call_logger.db',
          'C:/data/call_logger.db',
        ),
        isTrue,
      );
    }, testOn: 'windows');

    test('πεζά και κεφαλαία', () {
      expect(
        pathsReferToSameFile(
          r'C:\Data\CALL_LOGGER.DB',
          r'c:\data\call_logger.db',
        ),
        isTrue,
      );
    }, testOn: 'windows');

    test('περιττό «.» στη μέση', () {
      expect(
        pathsReferToSameFile(
          r'C:\data\.\call_logger.db',
          r'C:\data\call_logger.db',
        ),
        isTrue,
      );
    });

    test('γονικός φάκελος «..»', () {
      expect(
        pathsReferToSameFile(
          r'C:\data\sub\..\call_logger.db',
          r'C:\data\call_logger.db',
        ),
        isTrue,
      );
    }, testOn: 'windows');

    test('διπλή κάθετος στη μέση', () {
      expect(
        pathsReferToSameFile(
          r'C:\data\\call_logger.db',
          r'C:\data\call_logger.db',
        ),
        isTrue,
      );
    }, testOn: 'windows');

    test('κενά στις άκρες', () {
      expect(
        pathsReferToSameFile(r'  C:\data\db.db  ', r'C:\data\db.db'),
        isTrue,
      );
    });

    group('δικτυακή διαδρομή (UNC)', () {
      test('πεζά και κεφαλαία στον διακομιστή', () {
        expect(
          pathsReferToSameFile(
            r'\\POPINIO\Share\db.db',
            r'\\popinio\share\db.db',
          ),
          isTrue,
        );
      }, testOn: 'windows');

      test('γραμμένη με κανονικές καθέτους', () {
        // Η μορφή που γεννούν εργαλεία και σενάρια εκτός Windows· δείχνει στο
        // ίδιο ακριβώς αρχείο με τη μορφή που δίνει ο επιλογέας των Windows.
        expect(
          pathsReferToSameFile(
            r'\\POPINIO\Share\db.db',
            '//POPINIO/Share/db.db',
          ),
          isTrue,
        );
      }, testOn: 'windows');

      test('δεν χάνεται η διπλή κάθετος της αρχής', () {
        // Το «\\δίσκος» δεν επιτρέπεται να ισοπεδωθεί σε «\δίσκος»: θα έδειχνε
        // σε φάκελο του τοπικού δίσκου αντί για τον διακομιστή.
        expect(
          pathsReferToSameFile(
            r'\\POPINIO\Share\db.db',
            r'\POPINIO\Share\db.db',
          ),
          isFalse,
        );
      }, testOn: 'windows');
    });
  });

  group('διαφορετικά αρχεία μένουν διαφορετικά', () {
    test('άλλο όνομα αρχείου', () {
      expect(
        pathsReferToSameFile(r'C:\data\hospital.db', r'C:\data\lampa.db'),
        isFalse,
      );
    });

    test('άλλος φάκελος', () {
      expect(pathsReferToSameFile(r'C:\data\db.db', r'D:\data\db.db'), isFalse);
    });

    test('κενή διαδρομή δεν ταιριάζει με τίποτα — ούτε με κενή', () {
      // Το κενό δεν είναι αρχείο: δύο «άγνωστα» δεν είναι το ίδιο αρχείο, και
      // ένα «ναι» εδώ θα έσβηνε εγγραφές που δεν έπρεπε να αγγιχτούν.
      expect(pathsReferToSameFile('', ''), isFalse);
      expect(pathsReferToSameFile('   ', r'C:\data\db.db'), isFalse);
    });
  });

  group('το κλειδί σύγκρισης', () {
    test('δύο γραφές του ίδιου αρχείου δίνουν το ΙΔΙΟ κλειδί', () {
      // Το κλειδί τροφοδοτεί υπογραφές και σύνολα: αν διέφερε, η ίδια
      // εγκατάσταση θα μετριόταν δύο φορές.
      expect(filePathKey(r'C:\Data\.\APP.EXE'), filePathKey('c:/data/app.exe'));
    }, testOn: 'windows');

    test('κενή διαδρομή δίνει κενό κλειδί', () {
      expect(filePathKey('   '), isEmpty);
    });
  });

  group('σε συστήματα εκτός Windows', () {
    test('η ανάποδη κάθετος είναι κανονικός χαρακτήρας ονόματος', () {
      // Στο Linux/macOS το «\» επιτρέπεται μέσα σε όνομα αρχείου: αν το
      // γυρίζαμε σε διαχωριστή, θα ταυτίζαμε δύο διαφορετικά αρχεία.
      expect(pathsReferToSameFile(r'/data/a\b.db', '/data/a/b.db'), isFalse);
    }, testOn: '!windows');

    test('τα πεζά/κεφαλαία ΜΕΤΡΑΝΕ', () {
      expect(pathsReferToSameFile('/data/DB.db', '/data/db.db'), isFalse);
    }, testOn: '!windows');
  });

  test('η πραγματική διαδρομή του σταθμού αναγνωρίζεται ως ο εαυτός της', () {
    final exe = Platform.resolvedExecutable;
    expect(pathsReferToSameFile(exe, exe), isTrue);
  });

  // Οι τρεις περιπτώσεις που φύλαγε ο προκάτοχος αυτού του κριτή
  // (`database_path_identity`), με τις πραγματικές διαδρομές του σταθμού.
  group('πραγματικές διαδρομές του έργου', () {
    const callsOnly =
        r'F:\flutter_projects\call_logger\Data Base\Δοκιμές\μόνο_κλήσεις.db';
    const callLogger =
        r'C:\Users\Bacilic\Documents\call_logger\DB\call_logger.db';

    test('ελληνικός φάκελος με διαφορετικά πεζά-κεφαλαία', () {
      expect(
        pathsReferToSameFile(
          callsOnly,
          r'f:\flutter_projects\call_logger\data base\δοκιμές\μόνο_κλήσεις.db',
        ),
        isTrue,
      );
    }, testOn: 'windows');

    test('περιττά στοιχεία μονοπατιού κανονικοποιούνται', () {
      expect(
        pathsReferToSameFile(
          callLogger,
          r'C:\Users\Bacilic\Documents\call_logger\DB\.\call_logger.db',
        ),
        isTrue,
      );
    }, testOn: 'windows');

    test('δύο πραγματικά διαφορετικές διαδρομές', () {
      expect(pathsReferToSameFile(callsOnly, callLogger), isFalse);
    });
  });
}
