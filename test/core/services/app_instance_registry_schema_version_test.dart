// Έκδοση σχήματος στο μητρώο αντιγράφων της εφαρμογής.
//
// Με αυτήν, όταν ένα παλαιότερο αντίγραφο βρει βάση νεότερης έκδοσης, μπορεί
// να υποδείξει ΜΕ ΒΕΒΑΙΟΤΗΤΑ ποιο εκτελέσιμο τη διαβάζει. Οι εγγραφές παλιών
// εκδόσεων δεν την έχουν — «άγνωστη», ποτέ μάντεμα.
//
//   flutter test test/core/services/app_instance_registry_schema_version_test.dart

import 'package:call_logger/core/services/app_instance_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode/decode διατηρεί την έκδοση σχήματος', () {
    final records = AppInstanceRegistry.touch(
      known: const <AppInstanceRecord>[],
      executablePath: r'C:\Apps\CallLogger\call_logger.exe',
      version: '0.38.0',
      now: DateTime(2026, 8, 11, 9, 30),
      schemaVersion: 45,
    );

    final decoded = AppInstanceRegistry.decode(
      AppInstanceRegistry.encode(records),
    );

    expect(decoded, hasLength(1));
    expect(decoded.first.schemaVersion, 45);
    expect(decoded.first.version, '0.38.0');
  });

  test('παλιά εγγραφή χωρίς schemaVersion → null, όχι σφάλμα, όχι μάντεμα',
      () {
    const legacyJson =
        '[{"path":"C:\\\\Apps\\\\Old\\\\call_logger.exe",'
        '"version":"0.34.0","lastSeen":"2026-08-01T10:00:00.000"}]';

    final decoded = AppInstanceRegistry.decode(legacyJson);

    expect(decoded, hasLength(1));
    expect(decoded.first.schemaVersion, isNull);
    expect(decoded.first.version, '0.34.0');
  });

  test('το touch ανανεώνει την έκδοση σχήματος του τρέχοντος αντιγράφου', () {
    final older = AppInstanceRegistry.touch(
      known: const <AppInstanceRecord>[],
      executablePath: r'C:\Apps\CallLogger\call_logger.exe',
      version: '0.34.0',
      now: DateTime(2026, 7, 1),
      schemaVersion: 40,
    );

    // Το ίδιο εκτελέσιμο ξανατρέχει μετά από ενημέρωση.
    final updated = AppInstanceRegistry.touch(
      known: older,
      executablePath: r'C:\Apps\CallLogger\call_logger.exe',
      version: '0.38.0',
      now: DateTime(2026, 8, 11),
      schemaVersion: 45,
    );

    expect(updated, hasLength(1));
    expect(updated.first.schemaVersion, 45);
  });
}
