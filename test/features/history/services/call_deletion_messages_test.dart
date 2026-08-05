import 'package:call_logger/core/database/call_deletion_impact.dart';
import 'package:call_logger/features/history/services/call_deletion_messages.dart';
import 'package:flutter_test/flutter_test.dart';

CallConnectionSummary call({
  int callId = 1,
  String date = '2026-08-03',
  String time = '09:40',
  List<String> taskTitles = const <String>[],
  List<String> tickets = const <String>[],
  int? externalLinks,
}) {
  return CallConnectionSummary(
    callId: callId,
    date: date,
    time: time,
    taskTitles: taskTitles,
    lansweeperTicketIds: tickets,
    externalLinks: externalLinks ?? tickets.length,
  );
}

CallDeletionImpact impact({
  List<String> taskTitles = const <String>[],
  int externalLinks = 0,
  List<String> tickets = const <String>[],
}) {
  return CallDeletionImpact([
    call(
      taskTitles: taskTitles,
      tickets: tickets,
      externalLinks: externalLinks,
    ),
  ]);
}

void main() {
  group('εισαγωγική γραμμή μίας κλήσης', () {
    test('χωρίς καμία σύνδεση ζητά απλή επιβεβαίωση', () {
      expect(
        callDeletionHeadline(impact()),
        'Επιβεβαιώστε τη διαγραφή της κλήσης.',
      );
    });

    test('με σύνδεση μόνο σε Lansweeper αναγγέλλει τις συνδέσεις', () {
      expect(
        callDeletionHeadline(impact(externalLinks: 1, tickets: const ['7001'])),
        'Η κλήση συνδέεται με:',
      );
    });

    test('με σύνδεση μόνο σε εκκρεμότητα αναγγέλλει τις συνδέσεις', () {
      expect(
        callDeletionHeadline(impact(taskTitles: const ['Κάτι'])),
        'Η κλήση συνδέεται με:',
      );
    });
  });

  group('εισαγωγική γραμμή μαζικής διαγραφής', () {
    test('χωρίς συνδέσεις ρωτά μόνο για τις κλήσεις', () {
      expect(
        callBulkDeletionHeadline(CallDeletionImpact.empty, callCount: 4),
        'Να διαγραφούν οι 4 επιλεγμένες κλήσεις;',
      );
    });

    test('ονομάζει και τα δύο είδη σύνδεσης, όχι μόνο τις εκκρεμότητες', () {
      final mixed = CallDeletionImpact([
        call(callId: 1, tickets: const ['7001']),
        call(callId: 2, taskTitles: const ['Πρώτη', 'Δεύτερη']),
      ]);

      expect(
        callBulkDeletionHeadline(mixed, callCount: 3),
        'Οι 3 επιλεγμένες κλήσεις έχουν συνολικά 3 συνδέσεις: '
        '2 εκκρεμότητες και 1 αίτημα Lansweeper.',
      );
    });

    test('με ένα μόνο είδος δεν κολλά περιττό «και»', () {
      expect(
        callBulkDeletionHeadline(
          impact(taskTitles: const ['Μία']),
          callCount: 2,
        ),
        'Οι 2 επιλεγμένες κλήσεις έχουν συνολικά 1 σύνδεση: 1 εκκρεμότητα.',
      );
    });

    test('μία κλήση μιλά στον ενικό', () {
      expect(
        callBulkDeletionHeadline(
          impact(externalLinks: 1, tickets: const ['7001']),
          callCount: 1,
        ),
        'Η επιλεγμένη κλήση έχει συνολικά 1 σύνδεση: 1 αίτημα Lansweeper.',
      );
    });
  });

  group('γραμμή Lansweeper', () {
    test('χωρίς δεσμούς δεν εμφανίζεται', () {
      expect(callLansweeperConnectionLine(impact()), isNull);
    });

    test('ένα εισιτήριο ονομάζεται στον ενικό', () {
      expect(
        callLansweeperConnectionLine(
          impact(externalLinks: 1, tickets: const ['7001']),
        ),
        'Lansweeper — εισιτήριο 7001',
      );
    });

    test('δύο εισιτήρια σε δύο εγγραφές δεν επαναλαμβάνουν το πλήθος', () {
      expect(
        callLansweeperConnectionLine(
          impact(externalLinks: 2, tickets: const ['7002', '7003']),
        ),
        'Lansweeper — εισιτήρια 7002, 7003',
      );
    });

    test('περισσότερες εγγραφές από εισιτήρια δηλώνουν το ιστορικό', () {
      expect(
        callLansweeperConnectionLine(
          impact(externalLinks: 3, tickets: const ['7002', '7003']),
        ),
        'Lansweeper — εισιτήρια 7002, 7003 (3 εγγραφές ιστορικού)',
      );
    });

    test('πάνω από τέσσερα εισιτήρια κόβονται με «κ.ά.»', () {
      final line = callLansweeperConnectionLine(
        impact(externalLinks: 6, tickets: const ['1', '2', '3', '4', '5', '6']),
      );
      expect(line, contains('εισιτήρια 1, 2, 3, 4 κ.ά.'));
      expect(line, isNot(contains('5, 6')));
    });

    test('δεσμός χωρίς αριθμό εισιτηρίου το λέει καθαρά', () {
      expect(
        callLansweeperConnectionLine(impact(externalLinks: 1)),
        'Lansweeper — 1 εγγραφή ιστορικού χωρίς αριθμό εισιτηρίου',
      );
    });
  });

  group('γραμμή και τίτλοι εκκρεμοτήτων', () {
    test('χωρίς εκκρεμότητες δεν εμφανίζεται γραμμή', () {
      expect(callTasksConnectionLine(impact()), isNull);
      expect(callTaskTitleLines(impact()), isEmpty);
      expect(callTaskTitlesOverflowLine(impact()), isNull);
    });

    test('μία εκκρεμότητα μιλά στον ενικό και ονομάζεται', () {
      final one = impact(taskTitles: const ['Αντικατάσταση καλωδίου']);
      expect(callTasksConnectionLine(one), '1 συνδεδεμένη εκκρεμότητα:');
      expect(callTaskTitleLines(one), ['Αντικατάσταση καλωδίου']);
    });

    test('εκκρεμότητα χωρίς τίτλο δεν εξαφανίζεται από τη λίστα', () {
      expect(callTaskTitleLines(impact(taskTitles: const ['   '])), [
        '(χωρίς τίτλο)',
      ]);
    });

    test('πάνω από τέσσερις κόβονται και το υπόλοιπο δηλώνεται', () {
      final lots = impact(taskTitles: const ['Α', 'Β', 'Γ', 'Δ', 'Ε', 'Ζ']);
      expect(callTaskTitleLines(lots), ['Α', 'Β', 'Γ', 'Δ']);
      expect(callTaskTitlesOverflowLine(lots), 'και 2 ακόμη');
    });
  });

  group('λίστα συνδέσεων ανά κλήση', () {
    test('απαριθμεί μόνο τις κλήσεις που έχουν κάτι να δείξουν', () {
      final mixed = CallDeletionImpact([
        call(callId: 1, tickets: const ['7001']),
        call(callId: 2),
        call(callId: 3, taskTitles: const ['Μία']),
      ]);

      expect(callConnectionRows(mixed).map((c) => c.callId), [1, 3]);
      expect(callConnectionRowsOverflowLine(mixed), isNull);
    });

    test('πάνω από 30 κλήσεις με συνδέσεις κόβονται και δηλώνονται', () {
      final many = CallDeletionImpact([
        for (var i = 0; i < 35; i++)
          call(callId: i, tickets: const ['7001']),
      ]);

      expect(callConnectionRows(many), hasLength(30));
      expect(
        callConnectionRowsOverflowLine(many),
        'και 5 ακόμη κλήσεις με συνδέσεις (εμφανίζονται οι πρώτες 30)',
      );
    });

    test('κλήσεις χωρίς συνδέσεις δεν μετρούν στο όριο των 30', () {
      final many = CallDeletionImpact([
        for (var i = 0; i < 100; i++) call(callId: i),
        call(callId: 999, tickets: const ['7001']),
      ]);

      expect(callConnectionRows(many).map((c) => c.callId), [999]);
      expect(callConnectionRowsOverflowLine(many), isNull);
    });

    test('η χρονοσήμανση γράφεται όπως στον πίνακα του Ιστορικού', () {
      expect(
        callConnectionRowTimestamp(call(date: '2026-08-03', time: '09:40')),
        '03-08-2026 09:40',
      );
    });

    test('κλήση χωρίς ώρα δεν αφήνει κενό στο τέλος', () {
      expect(
        callConnectionRowTimestamp(call(date: '2026-08-03', time: '')),
        '03-08-2026',
      );
    });

    test('η ετικέτα ενώνει τα δύο είδη σύνδεσης', () {
      expect(
        callConnectionRowLabel(
          call(taskTitles: const ['Α', 'Β'], tickets: const ['7001']),
        ),
        'Lansweeper — εισιτήριο 7001 · 2 εκκρεμότητες',
      );
    });

    test('η ετικέτα με ένα μόνο είδος δεν αφήνει διαχωριστικό', () {
      expect(
        callConnectionRowLabel(call(taskTitles: const ['Α'])),
        '1 εκκρεμότητα',
      );
    });
  });

  group('κουμπιά επιλογής', () {
    test('οι τίτλοι δεν αναφέρουν «tasks» και ακολουθούν το πλήθος', () {
      expect(
        callKeepTasksButtonLabel(callCount: 1),
        'Διαγραφή μόνο της κλήσης',
      );
      expect(
        callKeepTasksButtonLabel(callCount: 5),
        'Διαγραφή μόνο των κλήσεων',
      );
      expect(
        callCascadeButtonLabel(callCount: 1),
        'Διαγραφή κλήσης και εκκρεμοτήτων',
      );
      expect(
        callCascadeButtonLabel(callCount: 5),
        'Διαγραφή κλήσεων και εκκρεμοτήτων',
      );
    });

    test('οι επεξηγήσεις λένε τι απογίνονται οι εκκρεμότητες', () {
      final two = impact(taskTitles: const ['Α', 'Β']);
      expect(
        callKeepTasksButtonHint(two),
        'Οι 2 εκκρεμότητες μένουν στη λίστα σας, χωρίς σύνδεση με κλήση.',
      );
      expect(
        callCascadeButtonHint(two),
        'Διαγράφονται και οι 2 συνδεδεμένες εκκρεμότητες.',
      );
    });

    test('μία εκκρεμότητα δίνει επεξηγήσεις στον ενικό', () {
      final one = impact(taskTitles: const ['Α']);
      expect(callKeepTasksButtonHint(one), startsWith('Η εκκρεμότητα μένει'));
      expect(
        callCascadeButtonHint(one),
        'Διαγράφεται και η συνδεδεμένη εκκρεμότητα.',
      );
    });
  });

  group('σημείωση ότι το Lansweeper δεν επηρεάζεται', () {
    test('εμφανίζεται όταν υπάρχει αίτημα και η διαγραφή είναι αναστρέψιμη', () {
      expect(
        callLansweeperUnaffectedNote(
          impact(externalLinks: 1, tickets: const ['7001']),
          hardDelete: false,
        ),
        'Το αίτημα Lansweeper δεν επηρεάζεται από καμία από τις δύο επιλογές.',
      );
    });

    test('σιωπά στην οριστική διαγραφή, που το σβήνει', () {
      // Δύο μηνύματα για το ίδιο πράγμα θα έλεγαν αντίθετα πράγματα: εδώ
      // μιλά μόνο η κόκκινη προειδοποίηση.
      expect(
        callLansweeperUnaffectedNote(
          impact(externalLinks: 1, tickets: const ['7001']),
          hardDelete: true,
        ),
        isNull,
      );
    });

    test('σιωπά όταν δεν υπάρχει καθόλου αίτημα', () {
      expect(
        callLansweeperUnaffectedNote(
          impact(taskTitles: const ['Α']),
          hardDelete: false,
        ),
        isNull,
      );
    });
  });

  group('προειδοποίηση οριστικής μαζικής διαγραφής', () {
    test('χωρίς αιτήματα δεν λέει τίποτα', () {
      expect(
        callBulkHardDeleteLossWarning(impact(taskTitles: const ['Α'])),
        isNull,
      );
    });

    test('ονομάζει πόσες κλήσεις χάνουν εισιτήριο, όχι πόσες εγγραφές', () {
      // Δύο κλήσεις με αίτημα, η μία με δύο εγγραφές ιστορικού: η απώλεια
      // αφορά δύο κλήσεις, όχι τρεις.
      final many = CallDeletionImpact([
        call(callId: 1, tickets: const ['7001']),
        call(callId: 2, tickets: const ['7002', '7003']),
        call(callId: 3, taskTitles: const ['Α']),
      ]);

      expect(
        callBulkHardDeleteLossWarning(many),
        contains('2 από τις κλήσεις που διαγράφετε έχουν αίτημα Lansweeper'),
      );
    });

    test('μία κλήση μιλά στον ενικό σε όλη την πρόταση', () {
      final one = CallDeletionImpact([
        call(callId: 1, tickets: const ['7001']),
        call(callId: 2),
      ]);

      final message = callBulkHardDeleteLossWarning(one);
      expect(message, contains('1 από τις κλήσεις που διαγράφετε έχει αίτημα'));
      expect(message, contains('δεν βρίσκεται πια'));
    });
  });

  group('προειδοποίηση οριστικής διαγραφής', () {
    test('χωρίς δεσμούς δεν λέει τίποτα', () {
      expect(callHardDeleteLossWarning(impact()), isNull);
    });

    test('με δεσμούς εξηγεί τι χάνεται ανεπιστρεπτί', () {
      final message = callHardDeleteLossWarning(
        impact(externalLinks: 1, tickets: const ['7001']),
      );
      expect(message, contains('σβήνει και το ιστορικό σύνδεσης'));
      expect(message, contains('αναζήτηση του αριθμού εισιτηρίου'));
    });

    test('εκκρεμότητες χωρίς δεσμούς δεν γεννούν προειδοποίηση', () {
      // Οι εκκρεμότητες δεν χάνονται από τον διακόπτη — τις κρίνει το κουμπί
      // που θα πατήσει ο χρήστης, όχι η οριστικότητα της διαγραφής.
      expect(
        callHardDeleteLossWarning(impact(taskTitles: const ['Μία'])),
        isNull,
      );
    });
  });
}
