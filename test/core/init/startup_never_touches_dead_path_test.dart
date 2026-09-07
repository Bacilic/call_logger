import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/init/startup_notices.dart';
import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Το συμβόλαιο, στο σκέλος που είχε ξεφύγει: **όταν η υπηρεσία έχει κρίνει τον
/// φάκελό της απρόσιτο, κανένα βήμα της εκκίνησης δεν τον ξαναρωτά.**
///
/// Το πρώτο πέρασμα έβαλε όρια χρόνου στις ασύγχρονες πράξεις και σταμάτησε
/// εκεί. Έμεινε ένας **σύγχρονος** έλεγχος φακέλου στο άδειασμα των σημειώσεων
/// εκκίνησης — και το όριο χρόνου δεν πιάνει σύγχρονη κλήση. Σε δικτυακή
/// διαδρομή χωρίς δίκτυο, εκείνη η μία γραμμή αρκούσε για λευκό παράθυρο.
///
/// Ο ανιχνευτής: ο φάκελος **υπάρχει** στον δίσκο, αλλά η υπηρεσία είναι σε
/// κατάσταση «χωρίς δίσκο». Έτσι οι δύο πηγές διαφωνούν, και φαίνεται ποια από
/// τις δύο ρωτήθηκε. Με τον παλιό κώδικα ο φάκελος έλεγε «υπάρχω» και οι
/// σημειώσεις γράφονταν — δηλαδή η διαδρομή ξαναγγιζόταν.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('startup_notices_gate');
    clearStartupNotices();
  });

  tearDown(() async {
    clearStartupNotices();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  String dbPathInside(Directory dir) => p.join(dir.path, 'call_logger.db');

  test(
    'φάκελος κριμένος απρόσιτος δεν ξαναρωτιέται, ακόμη κι αν υπάρχει',
    () async {
      // Ο φάκελος υπάρχει: αν κάποιος ρωτήσει το σύστημα αρχείων, θα πάρει
      // «ναι» — και θα γράψει. Η υπηρεσία όμως ξέρει ότι δεν απαντά.
      final logs = Directory(p.join(temp.path, 'logs'));
      await logs.create(recursive: true);

      await expectLater(
        CrashLogService.initialize(
          databasePath: dbPathInside(temp),
          appVersion: 'test',
          retentionCount: 5,
          timeout: const Duration(milliseconds: 200),
          createDirectory: (_) => Completer<void>().future,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(CrashLogService.instance.isDiskAvailable, isFalse);

      recordStartupNotice('Δοκιμή', StateError('κάτι'), StackTrace.current);
      flushStartupNoticesToCrashLog();

      // Τίποτα δεν γράφτηκε στον φάκελο που δεν απαντά.
      final written = await logs
          .list()
          .where((e) => p.basename(e.path).startsWith('errors_'))
          .toList();
      expect(written, isEmpty);

      // Και οι σημειώσεις κρατήθηκαν, ώστε να μπουν στην αναφορά σφάλματος.
      expect(startupNoticesReport(), contains('Δοκιμή'));
    },
  );

  test('όταν ο φάκελος απαντά, οι σημειώσεις γράφονται κανονικά', () async {
    await CrashLogService.initialize(
      databasePath: dbPathInside(temp),
      appVersion: 'test',
      retentionCount: 5,
    );
    expect(CrashLogService.instance.isDiskAvailable, isTrue);

    recordStartupNotice('Δοκιμή', StateError('κάτι'), StackTrace.current);
    flushStartupNoticesToCrashLog();

    expect(startupNoticesReport(), isNull);
    final logs = Directory(p.join(temp.path, 'logs'));
    final written = await logs
        .list()
        .where((e) => p.basename(e.path).startsWith('errors_'))
        .toList();
    expect(written, isNotEmpty);
  });
}
