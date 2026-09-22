// Όποιος ζητά αναμονή, δίνει και τον χρόνο να γίνει.
//
// Η SQLite ξεκινά κάθε σύνδεση με μηδενική αναμονή, οπότε το έργο της λέει
// ρητά «αν η βάση είναι πιασμένη, περίμενε» (`busy_timeout`). Σε δικτυακή βάση
// αυτή η αναμονή είναι 15 δευτερόλεπτα — αλλά το άνοιγμα παρατούσε στα 8 και
// κάθε ερώτημα στα 10. Η αναμονή δεν έφτανε ποτέ στο τέρμα της: η SQLite
// περίμενε σωστά, όπως της ζητήθηκε, και κοβόταν στο μισό του χρόνου που της
// δόθηκε (αναφορά 21/09/2026, δύο σταθμοί στην κοινόχρηστη βάση).
//
//   flutter test test/core/database/wait_budget_covers_lock_wait_test.dart

import 'package:call_logger/core/database/database_busy_timeout.dart';
import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/timeout_database.dart';
import 'package:flutter_test/flutter_test.dart';

const _networkPath = r'\\gnk.local\Departments\Call Logger\call_logger.db';
const _localPath = r'C:\Data\call_logger.db';

void main() {
  group('το όριο καλύπτει την αναμονή κλειδώματος', () {
    for (final entry in <String, String>{
      'δικτυακή βάση': _networkPath,
      'τοπική βάση': _localPath,
    }.entries) {
      final label = entry.key;
      final path = entry.value;

      test('$label — το άνοιγμα περιμένει όσο χρειάζεται', () {
        final lockWait = resolveDatabaseBusyTimeoutMs(path);
        final openBudget = resolveDatabaseOpenTimeout(path).inMilliseconds;

        expect(
          openBudget,
          greaterThan(lockWait),
          reason:
              'Το άνοιγμα παρατάει στα ${openBudget}ms ενώ η αναμονή '
              'κλειδώματος είναι ${lockWait}ms — η αναμονή δεν προλαβαίνει '
              'ποτέ να δουλέψει.',
        );
      });

      test('$label — η ταξινόμηση περιμένει όσο χρειάζεται', () {
        final lockWait = resolveDatabaseBusyTimeoutMs(path);
        final profileBudget = resolveDatabaseProfileTimeout(
          path,
        ).inMilliseconds;

        expect(
          profileBudget,
          greaterThan(lockWait),
          reason:
              'Έλεγχος τύπου αρχείου στα ${profileBudget}ms με αναμονή '
              '${lockWait}ms κόβει τη στιγμή που η βάση ελευθερώνεται.',
        );
      });
      test('$label — κάθε ερώτημα περιμένει όσο χρειάζεται', () {
        final lockWait = resolveDatabaseBusyTimeoutMs(path);
        final queryBudget = resolveDatabaseQueryTimeout(path).inMilliseconds;

        expect(
          queryBudget,
          greaterThan(lockWait),
          reason:
              'Το ερώτημα παρατάει στα ${queryBudget}ms ενώ η αναμονή '
              'κλειδώματος είναι ${lockWait}ms.',
        );
      });
    }

    test('η ρύθμιση του χρήστη δεν επιτρέπεται να σπάσει τη σχέση', () {
      // Ο χρήστης μπορεί να ορίσει δικό του όριο ανοίγματος από τις Ρυθμίσεις.
      // Μια μικρή τιμή θα ξανάφερνε ακριβώς το σφάλμα, σιωπηλά.
      final lockWait = resolveDatabaseBusyTimeoutMs(_networkPath);

      final budget = resolveDatabaseOpenTimeout(
        _networkPath,
        configuredSeconds: 3,
      ).inMilliseconds;

      expect(
        budget,
        greaterThan(lockWait),
        reason:
            'Ρύθμιση 3 δευτερολέπτων σε βάση με αναμονή ${lockWait}ms πρέπει '
            'να ανεβαίνει στο ελάχιστο, όχι να γίνεται δεκτή ως έχει.',
      );
    });

    test('μεγαλύτερη ρύθμιση του χρήστη γίνεται σεβαστή', () {
      final budget = resolveDatabaseOpenTimeout(
        _networkPath,
        configuredSeconds: 60,
      );

      expect(
        budget,
        const Duration(seconds: 60),
        reason:
            'Το κατώφλι είναι δάπεδο, όχι ταβάνι — όποιος θέλει να περιμένει '
            'περισσότερο, περιμένει.',
      );
    });

    test('η τοπική βάση δεν πληρώνει την αναμονή του δικτύου', () {
      expect(
        resolveDatabaseOpenTimeout(_localPath).inSeconds,
        lessThan(resolveDatabaseOpenTimeout(_networkPath).inSeconds),
        reason:
            'Η διαδρομή αποφασίζει: ένα τοπικό αρχείο δεν έχει λόγο να '
            'περιμένει όσο ένας κοινόχρηστος φάκελος.',
      );
    });
  });
}
