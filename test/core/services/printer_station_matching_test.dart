// Ποιοι εκτυπωτές ανήκουν σε ποιον σταθμό, και ποιοι είναι ορφανοί.
//
// Αυτοί οι κανόνες κρίνουν σε ποιανού την ουρά θα επέμβει ο χειριστής. Ένα
// λάθος εδώ σβήνει την εκτύπωση άσχετου ανθρώπου, γι' αυτό ελέγχονται και οι
// περιπτώσεις όπου η σωστή απάντηση είναι «μην αγγίξεις τίποτα».
//
//   flutter test test/core/services/printer_station_matching_test.dart

import 'package:call_logger/core/services/server_sessions/printer_station_matching.dart';
import 'package:call_logger/core/services/server_sessions/server_printer_models.dart';
import 'package:call_logger/core/services/server_sessions/server_session_models.dart';
import 'package:flutter_test/flutter_test.dart';

ServerPrinter _printer(String rawName, {int status = 0, int jobs = 0}) {
  final parsed = PrinterStationMatching.parseName(rawName);
  return ServerPrinter(
    fullName: rawName,
    displayName: parsed.displayName,
    stationName: parsed.station,
    sessionId: parsed.session,
    driverName: 'Οδηγός',
    statusFlags: status,
    jobCount: jobs,
  );
}

ServerSession _session(int id, String station) => ServerSession(
  sessionId: id,
  username: 'χρήστης$id',
  state: ServerSessionState.active,
  stationName: station,
);

void main() {
  group('Ανάλυση ονόματος εκτυπωτή', () {
    test('μορφή Windows Server 2003 δίνει σταθμό και συνεδρία', () {
      final p = PrinterStationMatching.parseName(
        'EPSON WF-M5399 Series PCL6 (from PC2129) in session 11',
      );

      expect(p.displayName, 'EPSON WF-M5399 Series PCL6');
      expect(p.station, 'PC2129');
      expect(p.session, 11);
    });

    test('όνομα με παρενθέσεις μέσα του δεν μπερδεύεται', () {
      // Πραγματικό παράδειγμα από τον .82.
      final p = PrinterStationMatching.parseName(
        'EPSON WF-M5399 (3847) on Pandora (from PC3675) in session 14',
      );

      expect(p.displayName, 'EPSON WF-M5399 (3847) on Pandora');
      expect(p.station, 'PC3675');
      expect(p.session, 14);
    });

    test('νεότερη μορφή δίνει συνεδρία χωρίς σταθμό', () {
      final p = PrinterStationMatching.parseName('HP LaserJet (redirected 7)');

      expect(p.displayName, 'HP LaserJet');
      expect(p.station, '');
      expect(p.session, 7);
    });

    test('το πρόθεμα του διακομιστή φεύγει από το εμφανιζόμενο όνομα', () {
      // Η απομακρυσμένη απαρίθμηση επιστρέφει πλήρεις διαδρομές δικτύου —
      // επιβεβαιωμένο ζωντανά στον .82.
      final p = PrinterStationMatching.parseName(
        r'\\192.168.13.82\EPSON WF-M5399 Series PCL6 (from PC3140) in session 1',
      );

      expect(p.displayName, 'EPSON WF-M5399 Series PCL6');
      expect(p.station, 'PC3140');
      expect(p.session, 1);
    });

    test('πρόθεμα διακομιστή και σε μη ανακατευθυνόμενο εκτυπωτή', () {
      final p = PrinterStationMatching.parseName(
        r'\\192.168.13.82\CutePDF Writer',
      );

      expect(p.displayName, 'CutePDF Writer');
      expect(p.session, isNull);
    });

    test('τοπικός εκτυπωτής του διακομιστή μένει ανέγγιχτος', () {
      final p = PrinterStationMatching.parseName('CutePDF Writer');

      expect(p.displayName, 'CutePDF Writer');
      expect(p.station, '');
      expect(p.session, isNull);
    });
  });

  group('Εκτυπωτές ανά σταθμό', () {
    final printers = [
      _printer('EPSON A (from PC5068) in session 27'),
      _printer('doPDF v7 (from PC5068) in session 27'),
      _printer('EPSON B (from PC2129) in session 11'),
      _printer('CutePDF Writer'),
    ];

    test('επιστρέφονται μόνο οι εκτυπωτές του σταθμού', () {
      final result = PrinterStationMatching.printersForStation(
        printers: printers,
        stationName: 'PC5068',
        stationSessionIds: const {27},
        liveSessionIds: const {27, 11},
      );

      // Και οι δύο υγιείς και χωρίς ουρά, οπότε αποφασίζει το αλφαβητικό.
      expect(result.map((s) => s.printer.displayName), ['doPDF v7', 'EPSON A']);
    });

    test('ο τοπικός εκτυπωτής του διακομιστή δεν μπαίνει ποτέ', () {
      final result = PrinterStationMatching.printersForStation(
        printers: printers,
        stationName: '',
        stationSessionIds: const {},
        liveSessionIds: const {27, 11},
      );

      expect(result, isEmpty);
    });

    test('ταιριάζει και μόνο με τη συνεδρία, όταν λείπει το όνομα', () {
      // Νεότερη μορφή ονόματος: σταθμό δεν δίνει, αλλά τη συνεδρία τη ξέρουμε
      // από τη ζωντανή λίστα.
      final result = PrinterStationMatching.printersForStation(
        printers: [_printer('HP LaserJet (redirected 27)')],
        stationName: 'PC5068',
        stationSessionIds: const {27},
        liveSessionIds: const {27},
      );

      expect(result.single.printer.displayName, 'HP LaserJet');
    });

    test('κενό όνομα σταθμού δεν ταιριάζει με κενό όνομα εκτυπωτή', () {
      // Χωρίς φρουρό, το «κενό ισούται με κενό» θα επέστρεφε ξένους εκτυπωτές.
      final result = PrinterStationMatching.printersForStation(
        printers: [_printer('HP LaserJet (redirected 9)')],
        stationName: '',
        stationSessionIds: const {},
        liveSessionIds: const {9},
      );

      expect(result, isEmpty);
    });
  });

  group('Ορφανοί', () {
    test('εκτυπωτής συνεδρίας που δεν υπάρχει πια είναι ορφανός', () {
      final result = PrinterStationMatching.printersForStation(
        printers: [_printer('EPSON A (from PC5068) in session 14')],
        stationName: 'PC5068',
        stationSessionIds: const {},
        liveSessionIds: const {27, 11},
      );

      expect(result.single.isOrphan, isTrue);
    });

    test('εκτυπωτής ζωντανής συνεδρίας ΔΕΝ είναι ορφανός', () {
      final result = PrinterStationMatching.printersForStation(
        printers: [_printer('EPSON A (from PC5068) in session 27')],
        stationName: 'PC5068',
        stationSessionIds: const {27},
        liveSessionIds: const {27},
      );

      expect(result.single.isOrphan, isFalse);
    });

    test('άγνωστες συνεδρίες ΔΕΝ κάνουν τους πάντες ορφανούς', () {
      // Αν η ερώτηση για τις συνεδρίες απέτυχε και γυρίσει άδεια λίστα, το
      // «κανείς δεν είναι ζωντανός» θα πρότεινε διαγραφή ΟΛΩΝ των εκτυπωτών
      // του διακομιστή. Άγνοια δεν σημαίνει απουσία.
      final result = PrinterStationMatching.printersForStation(
        printers: [_printer('EPSON A (from PC5068) in session 27')],
        stationName: 'PC5068',
        stationSessionIds: const {27},
        liveSessionIds: const {},
      );

      expect(result.single.isOrphan, isFalse);
    });

    test('η λίστα ορφανών του διακομιστή αγνοεί τους τοπικούς', () {
      final orphans = PrinterStationMatching.orphans(
        printers: [
          _printer('CutePDF Writer'),
          _printer('EPSON A (from PC1) in session 3'),
          _printer('EPSON B (from PC2) in session 27'),
        ],
        liveSessionIds: const {27},
      );

      expect(orphans.map((p) => p.displayName), ['EPSON A']);
    });

    test('χωρίς ζωντανή λίστα δεν προτείνεται κανένας ορφανός', () {
      final orphans = PrinterStationMatching.orphans(
        printers: [_printer('EPSON A (from PC1) in session 3')],
        liveSessionIds: const {},
      );

      expect(orphans, isEmpty);
    });
  });

  group('Ταξινόμηση και συνεδρίες σταθμού', () {
    test('πρώτα τα προβλήματα, τελευταίοι οι ορφανοί', () {
      final result = PrinterStationMatching.printersForStation(
        printers: [
          _printer('Ορφανός (from PC1) in session 99'),
          _printer('Ήσυχος (from PC1) in session 5'),
          _printer('Με ουρά (from PC1) in session 5', jobs: 3),
          _printer(
            'Με σφάλμα (from PC1) in session 5',
            status: PrinterStatusFlags.error,
          ),
        ],
        stationName: 'PC1',
        stationSessionIds: const {5},
        liveSessionIds: const {5},
      );

      expect(result.map((s) => s.printer.displayName), [
        'Με σφάλμα',
        'Με ουρά',
        'Ήσυχος',
        'Ορφανός',
      ]);
    });

    test('οι συνεδρίες ενός σταθμού βρίσκονται από τη ζωντανή λίστα', () {
      final ids = PrinterStationMatching.sessionIdsForStation(
        sessions: [
          _session(27, 'PC5068'),
          _session(31, 'PC5068'),
          _session(11, 'PC2129'),
        ],
        stationName: 'pc5068',
      );

      expect(ids, {27, 31});
    });

    test('κενό όνομα σταθμού δεν επιστρέφει συνεδρίες', () {
      final ids = PrinterStationMatching.sessionIdsForStation(
        sessions: [_session(27, '')],
        stationName: '',
      );

      expect(ids, isEmpty);
    });
  });

  group('Κατάσταση εκτυπωτή και εργασιών', () {
    test('το σφάλμα υπερισχύει της παύσης', () {
      final health = printerHealthFromFlags(
        PrinterStatusFlags.paused | PrinterStatusFlags.paperJam,
      );

      expect(health, PrinterHealth.error);
    });

    test('καθαρός εκτυπωτής δεν ζητά προσοχή', () {
      expect(printerHealthFromFlags(0), PrinterHealth.ready);
      expect(PrinterHealth.ready.needsAttention, isFalse);
      expect(PrinterHealth.offline.needsAttention, isTrue);
    });

    test('η ετικέτα κατάστασης δίνει προτεραιότητα στο σφάλμα', () {
      // Οι σημαίες συνυπάρχουν: μια εργασία που κόλλησε κρατά συχνά ΚΑΙ το
      // «τυπώνεται». Πρέπει να διαβάζεται η αιτία, όχι η κίνηση.
      const stuckWhilePrinting = PrintJob(
        jobId: 7,
        document: 'Ετικέτα.lbl',
        user: 'nslpathall',
        machine: 'PC3686',
        statusFlags: PrintJobStatusFlags.printing | PrintJobStatusFlags.error,
        totalPages: 1,
        pagesPrinted: 0,
      );

      expect(stuckWhilePrinting.statusLabel, 'σφάλμα');
      expect(stuckWhilePrinting.isStuck, isTrue);
    });

    test('εργασία χωρίς καμία σημαία είναι σε αναμονή', () {
      const waiting = PrintJob(
        jobId: 8,
        document: 'Παραπεμπτικό.pdf',
        user: 'gramtep2',
        machine: 'PC5068',
        statusFlags: 0,
        totalPages: 2,
        pagesPrinted: 0,
      );

      expect(waiting.statusLabel, 'αναμονή');
      expect(waiting.isActive, isFalse);
      expect(waiting.isStuck, isFalse);
    });

    test('εργασία που τυπώνεται τώρα ξεχωρίζει από κολλημένη', () {
      const printing = PrintJob(
        jobId: 1,
        document: 'Παραπεμπτικό.pdf',
        user: 'gramtep2',
        machine: 'PC5068',
        statusFlags: PrintJobStatusFlags.printing,
        totalPages: 3,
        pagesPrinted: 1,
      );
      const stuck = PrintJob(
        jobId: 2,
        document: 'Εξιτήριο.pdf',
        user: 'gramtep2',
        machine: 'PC5068',
        statusFlags: PrintJobStatusFlags.error,
        totalPages: 1,
        pagesPrinted: 0,
      );

      expect(printing.isActive, isTrue);
      expect(printing.isStuck, isFalse);
      expect(stuck.isActive, isFalse);
      expect(stuck.isStuck, isTrue);
      expect(stuck.statusLabel, 'σφάλμα');
    });
  });
}
