// Ο φρουρός που φέρνει τις αλλαγές των συναδέλφων στην οθόνη.
//
// Ελέγχεται χωρίς βάση, χωρίς αρχεία και χωρίς χρόνο: του δίνουμε μια ψεύτικη
// ακολουθία μετρητών και μετράμε πότε φώναξε.
//
//   flutter test test/core/database/shared_database_change_watcher_test.dart

import 'package:call_logger/core/database/shared_database_change_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SharedDatabaseChangeWatcher', () {
    late List<int?> versions;
    late int refreshCount;
    late bool busy;
    late SharedDatabaseChangeWatcher watcher;

    setUp(() {
      versions = [];
      refreshCount = 0;
      busy = false;
      watcher = SharedDatabaseChangeWatcher(
        readVersion: () async =>
            versions.isEmpty ? null : versions.removeAt(0),
        onChanged: () async => refreshCount++,
        isBusy: () => busy,
      );
    });

    tearDown(() => watcher.dispose());

    test('η πρώτη ανάγνωση ορίζει αφετηρία και δεν ανανεώνει', () async {
      versions = [7];
      await watcher.checkNow();
      expect(refreshCount, 0);
    });

    test('αλλαγή μετρητή → ανανέωση', () async {
      versions = [7, 8];
      await watcher.checkNow();
      await watcher.checkNow();
      expect(refreshCount, 1);
    });

    test('σταθερός μετρητής → καμία ανανέωση', () async {
      versions = [7, 7, 7];
      await watcher.checkNow();
      await watcher.checkNow();
      await watcher.checkNow();
      expect(refreshCount, 0);
    });

    test('άγνοια δεν είναι αλλαγή, και δεν χάνει την αφετηρία', () async {
      versions = [7, null, 7];
      await watcher.checkNow();
      await watcher.checkNow();
      await watcher.checkNow();
      expect(
        refreshCount,
        0,
        reason: 'Το null δεν πρέπει να μετρήσει ούτε ως αλλαγή ούτε ως μηδέν',
      );
    });

    test('όσο ο χρήστης δουλεύει, η ανανέωση κρατιέται', () async {
      versions = [7, 8];
      await watcher.checkNow();
      busy = true;
      await watcher.checkNow();

      expect(refreshCount, 0, reason: 'Ανοιχτός διάλογος — δεν τραβάμε το χαλί');
      expect(watcher.hasPendingRefresh, isTrue);

      busy = false;
      await watcher.flushPending();
      expect(refreshCount, 1, reason: 'Μόλις ελευθερώθηκε, εκτελείται');
      expect(watcher.hasPendingRefresh, isFalse);
    });

    test('η κρατημένη ανανέωση εκτελείται μία φορά, όχι δύο', () async {
      versions = [7, 8, 8];
      await watcher.checkNow();
      busy = true;
      await watcher.checkNow();
      busy = false;
      await watcher.flushPending();
      await watcher.flushPending();
      expect(refreshCount, 1);
    });

    test('αποτυχία ανάγνωσης δεν ρίχνει τον φρουρό', () async {
      final crashing = SharedDatabaseChangeWatcher(
        readVersion: () async => throw StateError('κλειδωμένη βάση'),
        onChanged: () async => refreshCount++,
      );
      await expectLater(crashing.checkNow(), completes);
      expect(refreshCount, 0);
      crashing.dispose();
    });

    test('αποτυχία ανανέωσης δεν ρίχνει τον φρουρό', () async {
      final crashing = SharedDatabaseChangeWatcher(
        readVersion: () async => versions.removeAt(0),
        onChanged: () async => throw StateError('η βάση έκλεισε'),
      );
      versions = [7, 8];
      await crashing.checkNow();
      await expectLater(crashing.checkNow(), completes);
      crashing.dispose();
    });

    test('start/stop: ο φρουρός δηλώνει αν τρέχει', () {
      expect(watcher.isRunning, isFalse);
      watcher.start();
      expect(watcher.isRunning, isTrue);
      watcher.stop();
      expect(watcher.isRunning, isFalse);
    });
  });
}
