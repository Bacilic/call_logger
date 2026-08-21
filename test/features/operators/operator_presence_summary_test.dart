// Τι διαβάζει ο άνθρωπος στην κάρτα του χρήστη, από τα ίχνη σύνδεσης.
//
//   flutter test test/features/operators/operator_presence_summary_test.dart

import 'package:call_logger/core/models/operator_presence.dart';
import 'package:call_logger/features/operators/services/operator_presence_summary.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime(2026, 8, 21, 14, 30);

OperatorPresence _mark(String station, Duration ago, {int operatorId = 1}) =>
    OperatorPresence(
      operatorId: operatorId,
      station: station,
      lastSeenAt: _now.subtract(ago),
    );

void main() {
  test('χωρίς κανένα ίχνος: δεν έχει συνδεθεί ποτέ', () {
    // Φυσιολογικό, όχι σφάλμα: ο διαχειριστής μπορεί να έφτιαξε το προφίλ και
    // να μην το έχει πατήσει ακόμη κανείς.
    final lines = describeOperatorPresence(const [], _now);

    expect(lines, hasLength(1));
    expect(lines.single.online, isFalse);
    expect(lines.single.text, 'Δεν έχει συνδεθεί ποτέ');
  });

  test('φρέσκο ίχνος: συνδεδεμένος τώρα, με τον σταθμό', () {
    final lines = describeOperatorPresence([
      _mark('ΤΠΕ-03', const Duration(seconds: 20)),
    ], _now);

    expect(lines.single.online, isTrue);
    expect(lines.single.text, 'Συνδεδεμένος τώρα — ΤΠΕ-03');
  });

  test('δύο σταθμοί ταυτόχρονα: φαίνονται και οι δύο', () {
    // Το ίδιο προφίλ μπορεί να δουλεύει από δύο θέσεις (κοινόχρηστο προφίλ
    // τμήματος). Μία γραμμή θα έκρυβε σιωπηλά τη μία από τις δύο.
    final lines = describeOperatorPresence([
      _mark('ΤΠΕ-03', const Duration(seconds: 20)),
      _mark('ΓΡΑΜΜΑΤΕΙΑ-01', const Duration(seconds: 40)),
    ], _now);

    expect(lines, hasLength(2));
    expect(lines.every((line) => line.online), isTrue);
    expect(
      lines.map((line) => line.text),
      containsAll([
        'Συνδεδεμένος τώρα — ΤΠΕ-03',
        'Συνδεδεμένος τώρα — ΓΡΑΜΜΑΤΕΙΑ-01',
      ]),
    );
  });

  test('μόνο παλιά ίχνη: μία γραμμή, η πιο πρόσφατη', () {
    // Το «πού ήταν πριν από έναν μήνα» δεν ενδιαφέρει κανέναν και θα γέμιζε
    // την κάρτα.
    final lines = describeOperatorPresence([
      _mark('ΠΑΛΙΟΣ', const Duration(days: 9)),
      _mark('ΤΠΕ-03', const Duration(hours: 2)),
    ], _now);

    expect(lines, hasLength(1));
    expect(lines.single.online, isFalse);
    expect(lines.single.text, 'Τελευταία σύνδεση 21/08/2026 12:30 — ΤΠΕ-03');
  });

  test('φρέσκο μαζί με παλιό: το παλιό δεν εμφανίζεται', () {
    final lines = describeOperatorPresence([
      _mark('ΤΠΕ-03', const Duration(seconds: 10)),
      _mark('ΠΑΛΙΟΣ', const Duration(days: 3)),
    ], _now);

    expect(lines, hasLength(1));
    expect(lines.single.text, 'Συνδεδεμένος τώρα — ΤΠΕ-03');
  });

  group('Το όριο παλαιότητας', () {
    test('λίγο πριν το όριο μετρά ως συνδεδεμένος', () {
      final mark = _mark(
        'ΤΠΕ-03',
        OperatorPresence.onlineWindow - const Duration(seconds: 1),
      );

      expect(mark.isOnlineAt(_now), isTrue);
    });

    test('ακριβώς στο όριο ΔΕΝ μετρά', () {
      final mark = _mark('ΤΠΕ-03', OperatorPresence.onlineWindow);

      expect(mark.isOnlineAt(_now), isFalse);
    });

    test('το όριο αντέχει έναν χαμένο χτύπο', () {
      // Αλλιώς μια στιγμιαία διακοπή δικτύου θα «αποσύνδεε» κάποιον που
      // δουλεύει κανονικά.
      expect(
        OperatorPresence.onlineWindow,
        greaterThan(OperatorPresence.heartbeatInterval * 2),
      );
    });
  });
}
