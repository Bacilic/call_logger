import 'dart:io';

import 'package:call_logger/core/init/startup_step_failure.dart';
import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Η αποτυχία ενός βήματος νοικοκυριού **γράφεται** — και η ίδια η καταγραφή
/// δεν πετάει ποτέ.
void main() {
  late Directory root;

  setUp(() async {
    // Κάθε έλεγχος ξεκινά **χωρίς** ημερολόγιο, ανεξάρτητα από τη σειρά.
    CrashLogService.resetForTest();
    root = await Directory.systemTemp.createTemp('startup_step_failure');
  });

  tearDown(() async {
    CrashLogService.resetForTest();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('χωρίς ημερολόγιο, η καταγραφή σωπαίνει αντί να πετάξει', () {
    // **Ο πυρήνας του κανόνα.** Το ημερολόγιο λείπει ακριβώς όταν ο δικτυακός
    // φάκελος δεν απαντά — δηλαδή ακριβώς όταν αυτά τα βήματα αποτυγχάνουν.
    // Ένα `CrashLogService.instance` εδώ θα πετούσε, το σφάλμα θα ανέβαινε
    // στον φρουρό της αρχικοποίησης, και η αποτυχία ενός βήματος νοικοκυριού
    // θα εμφανιζόταν στον χρήστη ως **σφάλμα βάσης**.
    expect(CrashLogService.instanceOrNull, isNull);

    expect(
      () => reportStartupStepFailure(
        'Η μετάπτωση απέτυχε',
        StateError('η βάση ήταν κλειδωμένη'),
        StackTrace.current,
      ),
      returnsNormally,
    );
  });

  test('με ημερολόγιο, η αποτυχία αφήνει ίχνος με την αιτία της', () async {
    await CrashLogService.initialize(
      databasePath: '${root.path}/Hospital.db',
      appVersion: '0.59.0',
      retentionCount: 5,
    );

    reportStartupStepFailure(
      'Η μετάπτωση των πεδίων απομακρυσμένης σύνδεσης απέτυχε',
      StateError('database is locked'),
      StackTrace.current,
    );

    final logs = Directory(
      CrashLogService.logsDirectoryForDatabasePath('${root.path}/Hospital.db'),
    );
    final files = await logs
        .list()
        .where((e) => e is File && e.path.contains('events_'))
        .cast<File>()
        .toList();

    expect(files, isNotEmpty, reason: 'δεν γράφτηκε ημερήσιο αρχείο σφαλμάτων');
    final written = await files.first.readAsString();

    // Και οι δύο μισές πληροφορίες χρειάζονται: **ποιο βήμα** απέτυχε και
    // **γιατί**. Χωρίς το πρώτο δεν ξέρεις πού να ψάξεις· χωρίς το δεύτερο
    // ξέρεις πού, αλλά όχι τι.
    expect(written, contains('Η μετάπτωση των πεδίων'));
    expect(written, contains('database is locked'));
  });

  test('η ετικέτα του βήματος ξεχωρίζει από την αιτία', () async {
    await CrashLogService.initialize(
      databasePath: '${root.path}/Hospital.db',
      appVersion: '0.59.0',
      retentionCount: 5,
    );

    reportStartupStepFailure(
      'Το σφράγισμα των αποθηκευμένων κλειδιών απέτυχε',
      'δίσκος γεμάτος',
      StackTrace.current,
    );

    final logs = Directory(
      CrashLogService.logsDirectoryForDatabasePath('${root.path}/Hospital.db'),
    );
    final files = await logs
        .list()
        .where((e) => e is File && e.path.contains('events_'))
        .cast<File>()
        .toList();
    final written = await files.first.readAsString();

    expect(written, contains('Το σφράγισμα'));
    expect(written, contains('δίσκος γεμάτος'));
  });
}
