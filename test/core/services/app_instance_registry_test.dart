// Μητρώο αντιγράφων της εφαρμογής που μοιράζονται τις ίδιες ρυθμίσεις.
//
// Συμβόλαιο: καταγράφεται μόνο ό,τι έχει όντως τρέξει — καμία μαντεψιά, άρα
// κανένα ψευδώς θετικό σε υπολογιστή με μία εγκατάσταση.
//
//   flutter test test/core/services/app_instance_registry_test.dart

import 'package:call_logger/core/services/app_instance_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  final t1 = DateTime(2026, 8, 3, 10);
  final t2 = DateTime(2026, 8, 3, 12);

  const installed = r'C:\Users\Bacilic\Documents\Call Logger\call_logger.exe';
  const release = r'F:\flutter_projects\call_logger\build\Release\call_logger.exe';

  test('η πρώτη εκκίνηση καταγράφει ένα μόνο αντίγραφο', () {
    final all = AppInstanceRegistry.touch(
      known: const [],
      executablePath: installed,
      version: '0.22.1',
      now: t1,
    );

    expect(all.length, 1);
    expect(all.single.version, '0.22.1');
    expect(
      AppInstanceRegistry.others(all, installed),
      isEmpty,
      reason: greekExpectMsg(
        'Με μία εγκατάσταση δεν υπάρχει τίποτα να αναφερθεί',
      ),
    );
  });

  test('η επανεκκίνηση του ίδιου αντιγράφου δεν δημιουργεί διπλοεγγραφή', () {
    var all = AppInstanceRegistry.touch(
      known: const [],
      executablePath: installed,
      version: '0.22.0',
      now: t1,
    );
    all = AppInstanceRegistry.touch(
      known: all,
      executablePath: installed,
      version: '0.22.1',
      now: t2,
    );

    expect(all.length, 1);
    expect(all.single.version, '0.22.1', reason: 'κρατά τη νεότερη έκδοση');
    expect(all.single.lastSeen, t2);
  });

  test('διαφορετική γραφή της ίδιας διαδρομής θεωρείται το ίδιο αντίγραφο', () {
    var all = AppInstanceRegistry.touch(
      known: const [],
      executablePath: installed,
      version: '0.22.1',
      now: t1,
    );
    all = AppInstanceRegistry.touch(
      known: all,
      executablePath: installed.toUpperCase(),
      version: '0.22.1',
      now: t2,
    );

    expect(
      all.length,
      1,
      reason: greekExpectMsg(
        'Στα Windows η διαδρομή δεν διακρίνει πεζά/κεφαλαία — αλλιώς ένα '
        'αντίγραφο θα φαινόταν σαν δύο',
      ),
    );
  });

  test('δεύτερο αντίγραφο εντοπίζεται και ξεχωρίζει από το τρέχον', () {
    var all = AppInstanceRegistry.touch(
      known: const [],
      executablePath: installed,
      version: '0.22.0',
      now: t1,
    );
    all = AppInstanceRegistry.touch(
      known: all,
      executablePath: release,
      version: '0.22.1',
      now: t2,
    );

    expect(all.length, 2);
    expect(all.first.executablePath, release, reason: 'νεότερο πρώτο');

    final others = AppInstanceRegistry.others(all, release);
    expect(others.length, 1);
    expect(others.single.executablePath, installed);
    expect(others.single.version, '0.22.0');
  });

  group('υπογραφή συνόλου', () {
    test('δεν αλλάζει όταν απλώς ξανατρέχει το ίδιο αντίγραφο', () {
      final first = AppInstanceRegistry.touch(
        known: const [],
        executablePath: installed,
        version: '0.22.0',
        now: t1,
      );
      final second = AppInstanceRegistry.touch(
        known: first,
        executablePath: installed,
        version: '0.22.1',
        now: t2,
      );

      expect(
        AppInstanceRegistry.signature(second),
        AppInstanceRegistry.signature(first),
        reason: greekExpectMsg(
          'Η ειδοποίηση που έκλεισε ο χρήστης δεν πρέπει να ξαναεμφανίζεται '
          'σε κάθε εκκίνηση',
        ),
      );
    });

    test('αλλάζει μόλις εμφανιστεί νέο αντίγραφο', () {
      final one = AppInstanceRegistry.touch(
        known: const [],
        executablePath: installed,
        version: '0.22.0',
        now: t1,
      );
      final two = AppInstanceRegistry.touch(
        known: one,
        executablePath: release,
        version: '0.22.1',
        now: t2,
      );

      expect(
        AppInstanceRegistry.signature(two),
        isNot(AppInstanceRegistry.signature(one)),
      );
    });

    test('δεν εξαρτάται από τη σειρά εμφάνισης', () {
      final a = AppInstanceRegistry.touch(
        known: AppInstanceRegistry.touch(
          known: const [],
          executablePath: installed,
          version: '1',
          now: t1,
        ),
        executablePath: release,
        version: '1',
        now: t2,
      );
      final b = AppInstanceRegistry.touch(
        known: AppInstanceRegistry.touch(
          known: const [],
          executablePath: release,
          version: '1',
          now: t1,
        ),
        executablePath: installed,
        version: '1',
        now: t2,
      );

      expect(AppInstanceRegistry.signature(a), AppInstanceRegistry.signature(b));
    });
  });

  // Η λωρίδα έχει μία γραμμή· η πλήρης διαδρομή έσπαγε σε άσχημο σημείο
  // («F:» μόνο του στο τέλος της γραμμής).
  group('σύντομη ετικέτα φακέλου', () {
    test('κρατά τα δύο τελευταία τμήματα του φακέλου, χωρίς το εκτελέσιμο', () {
      expect(
        AppInstanceRegistry.shortFolderLabel(release),
        r'…\build\Release',
      );
      expect(
        AppInstanceRegistry.shortFolderLabel(installed),
        r'…\Documents\Call Logger',
      );
    });

    test('κοντή διαδρομή μένει ακέραιη, χωρίς αποσιωπητικά', () {
      expect(
        AppInstanceRegistry.shortFolderLabel(r'C:\app\call_logger.exe'),
        r'C:\app',
        reason: greekExpectMsg(
          'Αποσιωπητικά χωρίς να κόβεται κάτι θα ήταν παραπλανητικά',
        ),
      );
    });

    test('χειρίζεται κάθετες και των δύο ειδών', () {
      expect(
        AppInstanceRegistry.shortFolderLabel('F:/a/b/c/call_logger.exe'),
        r'…\b\c',
      );
    });

    test('εκφυλισμένες τιμές δεν ρίχνουν τη λωρίδα', () {
      expect(AppInstanceRegistry.shortFolderLabel(''), '');
      expect(
        AppInstanceRegistry.shortFolderLabel('call_logger.exe'),
        'call_logger.exe',
      );
    });
  });

  group('αποθήκευση και ανάγνωση', () {
    test('κύκλος encode/decode διατηρεί τα δεδομένα', () {
      final all = AppInstanceRegistry.touch(
        known: const [],
        executablePath: installed,
        version: '0.22.1',
        now: t1,
      );

      final restored = AppInstanceRegistry.decode(
        AppInstanceRegistry.encode(all),
      );

      expect(restored.length, 1);
      expect(restored.single.executablePath, installed);
      expect(restored.single.version, '0.22.1');
      expect(restored.single.lastSeen, t1);
    });

    test('χαλασμένο ή κενό περιεχόμενο δεν ρίχνει την εκκίνηση', () {
      expect(AppInstanceRegistry.decode(null), isEmpty);
      expect(AppInstanceRegistry.decode(''), isEmpty);
      expect(AppInstanceRegistry.decode('όχι json'), isEmpty);
      expect(
        AppInstanceRegistry.decode('[{"path":"","version":"1"}]'),
        isEmpty,
        reason: greekExpectMsg('Εγγραφή χωρίς διαδρομή δεν έχει νόημα'),
      );
    });
  });
}
