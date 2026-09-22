// Η ταξινόμηση αρχείου βάσης δεν κρεμάει ποτέ — απαντά ή τα παρατάει.
//
// Σε κοινόχρηστη βάση δικτύου που κρατά κλειδωμένη ένας συνάδελφος, το βήμα
// «Έλεγχος τύπου αρχείου βάσης» έμενε να γυρίζει για πάντα: η σύνδεση άνοιγε
// γυμνή, χωρίς τον φύλακα ορίου χρόνου που το έργο βάζει σε κάθε δικτυακή
// βάση, και οκτώ από τα εννέα ερωτήματα δεν είχαν κανένα όριο. Η οθόνη
// εκκίνησης δεν είχε τρόπο να πει «η βάση είναι κατειλημμένη».
//
//   flutter test test/core/database/database_profile_timeout_test.dart

import 'dart:async';

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Σύνδεση που δεν απαντά ποτέ — ό,τι κάνει μια κλειδωμένη βάση δικτύου.
class _NeverAnsweringDatabase implements Database {
  bool closed = false;

  @override
  bool get isOpen => !closed;

  @override
  String get path => r'\\server\share\call_logger.db';

  @override
  Future<void> close() async => closed = true;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => Completer<List<Map<String, Object?>>>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<dynamic>().future;
}

void main() {
  test('βάση που δεν απαντά δίνει «αδιευκρίνιστο», δεν κρεμάει', () async {
    final db = _NeverAnsweringDatabase();
    final started = DateTime.now();

    final profile = await profileDatabaseFile(
      r'\\server\share\call_logger.db',
      timeout: const Duration(milliseconds: 300),
      openReadOnly: (_) async => db,
    );

    final elapsed = DateTime.now().difference(started);

    expect(
      profile.kind,
      DatabaseFileKind.undetermined,
      reason:
          'Η αναμονή δεν είναι απόδειξη ζημιάς — η εκκίνηση συνεχίζει με τους '
          'δικούς της φύλακες.',
    );
    expect(
      elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'Το όριο πρέπει να τηρείται, αλλιώς η οθόνη μένει να γυρίζει.',
    );
    expect(
      profile.failureReason,
      isNotNull,
      reason: 'Η οθόνη εκκίνησης δείχνει αυτόν τον λόγο ως διαγνωστικό.',
    );
  });

  test('η σύνδεση κλείνει ακόμη κι όταν λήξει ο χρόνος', () async {
    final db = _NeverAnsweringDatabase();

    await profileDatabaseFile(
      r'\\server\share\call_logger.db',
      timeout: const Duration(milliseconds: 300),
      openReadOnly: (_) async => db,
    );

    expect(
      db.closed,
      isTrue,
      reason:
          'Ξεχασμένη ανοιχτή σύνδεση κρατά κλείδωμα και εμποδίζει τους '
          'υπόλοιπους σταθμούς να γράψουν.',
    );
  });

  test('άνοιγμα που δεν επιστρέφει ποτέ δεν κρατά την εκκίνηση', () async {
    final started = DateTime.now();

    final profile = await profileDatabaseFile(
      r'\\server\share\call_logger.db',
      timeout: const Duration(milliseconds: 300),
      openReadOnly: (_) => Completer<Database>().future,
    );

    expect(profile.kind, DatabaseFileKind.undetermined);
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 5)),
      reason:
          'Το κρέμασμα μπορεί να συμβεί και πριν από το πρώτο ερώτημα, στο '
          'ίδιο το άνοιγμα.',
    );
  });
}
