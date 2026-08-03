// Πότε ανάβει η υπενθύμιση δημοσίευσης.
//
// Κανόνες χρήστη 03/08: χωρίς εγγραφές ΠΟΤΕ υπενθύμιση· το πλήθος υπερισχύει
// του χρόνου και δεν φρενάρεται από την ημερομηνία· ο χρόνος πιάνει τα αργά
// διαστήματα.
//
//   flutter test test/features/database/debug/publish_reminder_test.dart

import 'package:call_logger/features/database/debug/publish_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  // Καρφωμένη στιγμή αναφοράς: η απόφαση δεν πρέπει να εξαρτάται από το
  // πραγματικό ρολόι, αλλιώς το τεστ κοκκινίζει μια μέρα τον χρόνο.
  final now = DateTime(2026, 8, 3, 14, 30);

  PublishReminderStatus evaluate({
    required int entries,
    DateTime? lastRelease,
    String? version = '0.21.3',
  }) => evaluatePublishReminder(
    unreleasedEntryCount: entries,
    now: now,
    lastReleaseDate: lastRelease,
    lastReleaseVersion: version,
  );

  group('χωρίς αδημοσίευτες εγγραφές δεν υπάρχει υπενθύμιση', () {
    test('ούτε μετά από πολύ καιρό αδράνειας', () {
      final status = evaluate(
        entries: 0,
        lastRelease: DateTime(2026, 5, 1),
      );
      expect(
        status.shouldRemind,
        isFalse,
        reason: greekExpectMsg(
          'Ο χρόνος από μόνος του δεν είναι λόγος δημοσίευσης — δεν υπάρχει '
          'τίποτα να δημοσιευτεί',
        ),
      );
      expect(status.reasonLine, isNull);
    });

    test('αρνητικό πλήθος αντιμετωπίζεται ως μηδέν', () {
      expect(evaluate(entries: -3).shouldRemind, isFalse);
    });
  });

  group('το πλήθος υπερισχύει του χρόνου', () {
    test('αρκετές αλλαγές ΤΗΝ ΙΔΙΑ ημέρα υπενθυμίζουν', () {
      final status = evaluate(
        entries: 30,
        lastRelease: DateTime(2026, 8, 3, 9),
      );
      expect(
        status.shouldRemind,
        isTrue,
        reason: greekExpectMsg(
          'Τριάντα αλλαγές το πρωί και άλλες τριάντα το απόγευμα είναι δύο '
          'δημοσιεύσεις — η ημερομηνία δεν μπαίνει φρένο',
        ),
      );
      expect(status.daysSinceLastRelease, 0);
    });

    test('μία λιγότερη από το κατώφλι, την ίδια ημέρα, δεν υπενθυμίζει', () {
      final status = evaluate(
        entries: 29,
        lastRelease: DateTime(2026, 8, 3, 9),
      );
      expect(status.shouldRemind, isFalse);
    });
  });

  group('ο χρόνος πιάνει τα αργά διαστήματα', () {
    test('λίγες αλλαγές μετά από επτά ημέρες υπενθυμίζουν', () {
      final status = evaluate(
        entries: 1,
        lastRelease: DateTime(2026, 7, 27),
      );
      expect(status.shouldRemind, isTrue);
      expect(status.daysSinceLastRelease, 7);
    });

    test('έξι ημέρες με λίγες αλλαγές δεν υπενθυμίζουν ακόμα', () {
      final status = evaluate(
        entries: 5,
        lastRelease: DateTime(2026, 7, 28),
      );
      expect(status.shouldRemind, isFalse);
      expect(status.daysSinceLastRelease, 6);
    });

    test('μετρούν ημερολογιακές ημέρες, όχι εικοσιτετράωρα', () {
      // Δημοσίευση αργά το βράδυ, έλεγχος νωρίς το πρωί επτά ημέρες μετά.
      final status = evaluate(
        entries: 2,
        lastRelease: DateTime(2026, 7, 27, 23, 50),
      );
      expect(
        status.daysSinceLastRelease,
        7,
        reason: greekExpectMsg(
          'Η ηλικία μετριέται σε ημέρες ημερολογίου· αλλιώς μια δημοσίευση '
          'στις 23:00 θα «γερνούσε» μία ώρα αργότερα',
        ),
      );
    });
  });

  group('κείμενο σήματος και υπόδειξης', () {
    test('το πλήθος κόβεται στο 99+', () {
      expect(evaluate(entries: 99).badgeLabel, '99');
      expect(evaluate(entries: 173).badgeLabel, '99+');
    });

    test('η υπόδειξη εξηγεί πλήθος, ηλικία και έκδοση', () {
      final status = evaluate(
        entries: 173,
        lastRelease: DateTime(2026, 7, 23),
      );
      expect(status.reasonLine, 'Εκκρεμεί δημοσίευση: 173 αλλαγές, 11 ημέρες από την 0.21.3');
    });

    test('ενικός στη μία αλλαγή και στη μία ημέρα', () {
      final status = evaluatePublishReminder(
        unreleasedEntryCount: 1,
        now: now,
        lastReleaseDate: DateTime(2026, 8, 2),
        lastReleaseVersion: '0.21.3',
        dayThreshold: 1,
      );
      expect(status.reasonLine, 'Εκκρεμεί δημοσίευση: 1 αλλαγή, 1 ημέρα από την 0.21.3');
    });

    test('χωρίς γνωστή προηγούμενη έκδοση, η υπόδειξη λέει μόνο το πλήθος', () {
      final status = evaluate(entries: 40, lastRelease: null, version: null);
      expect(status.shouldRemind, isTrue);
      expect(status.reasonLine, 'Εκκρεμεί δημοσίευση: 40 αλλαγές');
    });
  });
}
