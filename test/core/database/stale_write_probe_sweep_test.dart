// Το διαγνωστικό «είναι εγγράψιμος ο φάκελος;» γράφει ένα μικρό αρχείο και το
// σβήνει. Όταν η εγγραφή αργήσει πάνω από το όριο (π.χ. antivirus που κρατά το
// αρχείο), η διαγραφή αποτυγχάνει και το υπόλειμμα μένει για πάντα — βρέθηκε
// ένα τέτοιο από τις 10/08/2026 στον φάκελο της βάσης.
//
// Ο καθαρισμός τρέχει στην εκκίνηση και είναι ΑΥΣΤΗΡΑ οριοθετημένος: στον ίδιο
// φάκελο ζουν αντίγραφα βάσης με ζωντανά -wal/-shm και αρχεία του χρήστη.
//
//   flutter test test/core/database/stale_write_probe_sweep_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_access_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('probe_sweep_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  String dbPath() => '${dir.path}${Platform.pathSeparator}call_logger.db';

  Future<File> write(String name, {Duration? age}) async {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsString('probe');
    if (age != null) {
      await file.setLastModified(DateTime.now().subtract(age));
    }
    return file;
  }

  test('παλιό υπόλειμμα probe σβήνεται και αναφέρεται', () async {
    final leftover = await write(
      '.__probe_1786340057335_5301.tmp',
      age: const Duration(days: 2),
    );

    final findings = await const DatabaseAccessProbe().sweepStaleWriteProbes(
      dbPath(),
    );

    expect(await leftover.exists(), isFalse);
    expect(findings, hasLength(1));
    expect(findings.single.code, 'stale_write_probes_swept');
  });

  test('φρέσκο probe ΔΕΝ αγγίζεται — μπορεί να τρέχει άλλη εκκίνηση', () async {
    final live = await write('.__probe_1786340057335_5302.tmp');

    final findings = await const DatabaseAccessProbe().sweepStaleWriteProbes(
      dbPath(),
    );

    expect(await live.exists(), isTrue);
    expect(findings, isEmpty);
  });

  test('χωρίς υπολείμματα δεν αναφέρεται τίποτα', () async {
    await write('call_logger.db');

    final findings = await const DatabaseAccessProbe().sweepStaleWriteProbes(
      dbPath(),
    );

    expect(findings, isEmpty, reason: 'βήμα που δεν έκανε τίποτα είναι θόρυβος');
  });

  test('ΔΕΝ αγγίζει βάσεις, -wal, -shm και αρχεία του χρήστη', () async {
    final keep = <File>[
      await write('call_logger.db', age: const Duration(days: 30)),
      await write(
        'call_logger_υποβαθμισμένη_12-08-2026.db',
        age: const Duration(days: 30),
      ),
      await write(
        'call_logger_υποβαθμισμένη_12-08-2026.db-wal',
        age: const Duration(days: 30),
      ),
      await write(
        'call_logger_υποβαθμισμένη_12-08-2026.db-shm',
        age: const Duration(days: 30),
      ),
      await write('Παλιά Βάση ΟΛΗ.xlsx', age: const Duration(days: 30)),
      await write('probe.tmp', age: const Duration(days: 30)),
      await write('.__probe_.tmp', age: const Duration(days: 30)),
      await write('.__probe_abc_def.tmp', age: const Duration(days: 30)),
      await write('.__probe_123_456.tmp.bak', age: const Duration(days: 30)),
    ];

    await const DatabaseAccessProbe().sweepStaleWriteProbes(dbPath());

    for (final file in keep) {
      expect(
        await file.exists(),
        isTrue,
        reason: 'ο καθαρισμός ξέφυγε από το μοτίβο του: ${file.path}',
      );
    }
  });

  test('πολλά υπολείμματα καθαρίζονται μαζί', () async {
    for (var i = 0; i < 4; i++) {
      await write(
        '.__probe_178634005733${i}_530$i.tmp',
        age: const Duration(hours: 6),
      );
    }

    final findings = await const DatabaseAccessProbe().sweepStaleWriteProbes(
      dbPath(),
    );

    final remaining = await dir.list().length;
    expect(remaining, 0);
    expect(findings.single.message, contains('4'));
  });

  test('ανύπαρκτος φάκελος δεν ρίχνει σφάλμα', () async {
    final missing =
        '${dir.path}${Platform.pathSeparator}δεν-υπάρχει${Platform.pathSeparator}x.db';

    expect(
      await const DatabaseAccessProbe().sweepStaleWriteProbes(missing),
      isEmpty,
    );
  });
}
