import 'package:call_logger/core/database/refresh_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ο ρυθμιστής που κρατά την ακριβή ανανέωση μακριά από τον πυκνό κύκλο.
///
/// **Το σενάριο πεδίου (28/09):** η οθόνη «Στατιστικά Βάσης Δεδομένων» έδειχνε
/// σχήμα 66 ενώ η βάση είχε ήδη αναβαθμιστεί σε 67, επειδή τίποτα δεν την
/// ξαναρωτούσε. Η ανανέωση όμως μετρά τις γραμμές κάθε πίνακα χωριστά: σε
/// γραφείο με τέσσερις σταθμούς θα έτρεχε εκατοντάδες φορές την ώρα.
void main() {
  late DateTime clock;
  RefreshThrottle throttle({Duration gap = const Duration(minutes: 1)}) =>
      RefreshThrottle(minimumGap: gap, now: () => clock);

  setUp(() => clock = DateTime(2026, 9, 28, 16, 0, 0));

  test('η πρώτη φορά περνά πάντα', () {
    // Μόλις ανοίξει η οθόνη, η πρώτη ξένη εγγραφή οφείλει να φανεί αμέσως.
    expect(throttle().allow(), isTrue);
  });

  test('η δεύτερη μέσα στο διάστημα φράζεται', () {
    final t = throttle();
    expect(t.allow(), isTrue);
    clock = clock.add(const Duration(seconds: 12));
    expect(t.allow(), isFalse);
  });

  test('ο πυκνός κύκλος δεν περνά ποτέ δεύτερη φορά μέσα στο λεπτό', () {
    final t = throttle();
    expect(t.allow(), isTrue);
    // Τέσσερις χτύποι των 12΄΄ = 48΄΄, ακόμη μέσα στο λεπτό.
    for (var i = 0; i < 4; i++) {
      clock = clock.add(const Duration(seconds: 12));
      expect(t.allow(), isFalse, reason: 'χτύπος ${i + 1}');
    }
  });

  test('μόλις περάσει το διάστημα, ξαναπερνά', () {
    final t = throttle();
    expect(t.allow(), isTrue);
    clock = clock.add(const Duration(minutes: 1));
    expect(t.allow(), isTrue);
  });

  test('η έγκριση ξεκινά νέο διάστημα από τη δική της στιγμή', () {
    final t = throttle();
    t.allow();
    clock = clock.add(const Duration(minutes: 1));
    expect(t.allow(), isTrue);
    clock = clock.add(const Duration(seconds: 30));
    expect(t.allow(), isFalse);
  });

  test('το φράξιμο ΔΕΝ μετακινεί το διάστημα προς τα εμπρός', () {
    // Αλλιώς ένας πυκνός κύκλος θα κρατούσε την ανανέωση φραγμένη για πάντα:
    // κάθε «όχι» θα ξανάρχιζε την αναμονή.
    final t = throttle();
    t.allow();
    for (var i = 0; i < 4; i++) {
      clock = clock.add(const Duration(seconds: 12));
      t.allow();
    }
    clock = clock.add(const Duration(seconds: 12));
    expect(t.allow(), isTrue, reason: 'στα 60΄΄ από την έγκριση');
  });

  test('ο μηδενισμός ανοίγει αμέσως τον δρόμο', () {
    final t = throttle();
    t.allow();
    clock = clock.add(const Duration(seconds: 5));
    expect(t.allow(), isFalse);

    // Άλλαξε η βάση: τα νούμερα της προηγούμενης δεν αφορούν τη νέα.
    t.reset();
    expect(t.allow(), isTrue);
  });

  test('θυμάται πότε εγκρίθηκε τελευταία φορά', () {
    final t = throttle();
    expect(t.lastAllowedAt, isNull);
    t.allow();
    expect(t.lastAllowedAt, clock);
  });
}
