import 'dart:io';

import 'package:call_logger/core/database/database_init_progress_provider.dart';
import 'package:call_logger/core/init/app_initializer.dart';
import 'package:call_logger/core/updates/update_residue_cleaner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late Directory installDir;
  late Directory staging;
  late Directory backup;
  late Directory userDataDb;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('update_residue_');
    installDir = Directory(p.join(tempRoot.path, 'install'));
    await installDir.create(recursive: true);

    staging = Directory(p.join(installDir.path, '.update_staging'));
    backup = Directory(p.join(installDir.path, '.update_backup'));
    userDataDb = Directory(p.join(installDir.path, 'Data Base'));
    await userDataDb.create(recursive: true);
    await File(p.join(userDataDb.path, 'call_logger.db')).writeAsBytes([1, 2]);
    await File(p.join(installDir.path, 'call_logger.exe')).writeAsBytes([77]);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<void> createResidue() async {
    await Directory(p.join(staging.path, 'app')).create(recursive: true);
    await File(p.join(staging.path, 'updater.cmd')).writeAsString('@echo off');
    await File(p.join(staging.path, 'updater.log')).writeAsString('SUCCESS');
    await File(
      p.join(staging.path, 'app', 'call_logger.exe'),
    ).writeAsBytes([77]);
    await backup.create(recursive: true);
    await File(p.join(backup.path, 'call_logger.exe')).writeAsBytes([77]);
  }

  /// [age] = πόσο «μπροστά» τρέχει το ρολόι, δηλαδή πόσο παλιά φαίνονται τα
  /// αρχεία που μόλις δημιουργήθηκαν.
  UpdateResidueCleaner buildCleaner({
    bool developmentBuild = false,
    bool pending = false,
    Future<bool> Function()? pendingOverride,
    Duration age = const Duration(hours: 1),
    String? installDirectoryOverride,
  }) {
    final now = DateTime.now().add(age);
    return UpdateResidueCleaner(
      installDirectory: installDirectoryOverride ?? installDir.path,
      isDevelopmentBuild: () => developmentBuild,
      isWindows: () => true,
      hasPendingUpdate: pendingOverride ?? () async => pending,
      clock: () => now,
    );
  }

  group('σάρωση υπολειμμάτων', () {
    test('χωρίς υπολείμματα δεν υπάρχει δουλειά', () async {
      final scan = await buildCleaner().scan();

      expect(scan.hasWork, isFalse);
      expect(scan.removable, isEmpty);
      expect(scan.protected, isEmpty);
    });

    test('παλιό staging και backup σημαίνονται και τα δύο προς διαγραφή', () async {
      await createResidue();

      final scan = await buildCleaner().scan();

      expect(scan.hasWork, isTrue);
      expect(scan.removable, hasLength(2));
      expect(scan.protected, isEmpty);
    });

    test('εκκρεμής ενημέρωση προστατεύει το staging, όχι το backup', () async {
      await createResidue();

      final scan = await buildCleaner(pending: true).scan();

      expect(scan.protected, contains(staging.path));
      expect(scan.removable, equals([backup.path]));
    });

    test('άγνωστη εκκρεμότητα προστατεύει το staging', () async {
      await createResidue();

      final scan = await buildCleaner(
        pendingOverride: () async => throw StateError('δείκτης μη αναγνώσιμος'),
      ).scan();

      expect(scan.protected, contains(staging.path));
      expect(scan.removable, equals([backup.path]));
    });

    test('φρέσκο ίχνος εγγραφής προστατεύει τον φάκελο', () async {
      await createResidue();

      final scan = await buildCleaner(age: const Duration(seconds: 5)).scan();

      expect(scan.hasWork, isFalse);
      expect(scan.protected, hasLength(2));
    });

    test('build ανάπτυξης δεν αγγίζει τίποτα', () async {
      await createResidue();

      final scan = await buildCleaner(developmentBuild: true).scan();

      expect(scan.hasWork, isFalse);
      expect(scan.protected, isEmpty);
    });

    test('εκτός Windows δεν αγγίζει τίποτα', () async {
      await createResidue();

      final cleaner = UpdateResidueCleaner(
        installDirectory: installDir.path,
        isWindows: () => false,
      );

      expect((await cleaner.scan()).hasWork, isFalse);
    });

    test('ρίζα δίσκου ως κατάλογος εγκατάστασης απορρίπτεται', () async {
      await createResidue();

      final scan = await buildCleaner(
        installDirectoryOverride: p.rootPrefix(installDir.path),
      ).scan();

      expect(scan.hasWork, isFalse);
    });
  });

  group('διαγραφή', () {
    test('διαγράφει τα σημασμένα και αφήνει τα δεδομένα χρήστη ανέπαφα', () async {
      await createResidue();
      final cleaner = buildCleaner();

      final removed = await cleaner.clean(await cleaner.scan());

      expect(removed, hasLength(2));
      expect(await staging.exists(), isFalse);
      expect(await backup.exists(), isFalse);
      expect(await userDataDb.exists(), isTrue);
      expect(
        await File(p.join(userDataDb.path, 'call_logger.db')).exists(),
        isTrue,
      );
      expect(
        await File(p.join(installDir.path, 'call_logger.exe')).exists(),
        isTrue,
      );
    });

    test('προστατευμένος φάκελος επιβιώνει της διαγραφής', () async {
      await createResidue();
      final cleaner = buildCleaner(pending: true);

      await cleaner.clean(await cleaner.scan());

      expect(await staging.exists(), isTrue);
      expect(await backup.exists(), isFalse);
    });

    test('φάκελος εκτός καταλόγου εγκατάστασης δεν διαγράφεται ποτέ', () async {
      final outsider = Directory(p.join(tempRoot.path, '.update_backup'));
      await outsider.create(recursive: true);

      final removed = await buildCleaner().clean(
        UpdateResidueScan(removable: [outsider.path]),
      );

      expect(removed, isEmpty);
      expect(await outsider.exists(), isTrue);
    });

    test('φάκελος που χάθηκε στο μεταξύ δεν ρίχνει εξαίρεση', () async {
      await createResidue();
      final cleaner = buildCleaner();
      final scan = await cleaner.scan();
      await staging.delete(recursive: true);

      final removed = await cleaner.clean(scan);

      expect(removed, equals([backup.path]));
    });
  });

  group('βήμα εκκίνησης', () {
    late ProviderContainer container;
    late DatabaseInitProgressNotifier progress;

    setUp(() {
      container = ProviderContainer();
      progress = container.read(databaseInitProgressProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('χωρίς υπολείμματα δεν ανακοινώνεται βήμα', () async {
      await cleanUpdateResidue(
        progressNotifier: progress,
        cleaner: buildCleaner(),
      );

      expect(
        container.read(databaseInitProgressProvider).currentStep,
        equals('Εκκίνηση...'),
      );
    });

    test('με υπολείμματα ανακοινώνεται το βήμα καθαρισμού', () async {
      await createResidue();

      await cleanUpdateResidue(
        progressNotifier: progress,
        cleaner: buildCleaner(),
      );

      expect(
        container.read(databaseInitProgressProvider).currentStep,
        equals('Καθαρισμός υπολειμμάτων ενημέρωσης'),
      );
      expect(await staging.exists(), isFalse);
    });

    test('αποτυχία σάρωσης δεν διακόπτει την εκκίνηση', () async {
      await createResidue();

      await expectLater(
        cleanUpdateResidue(
          progressNotifier: progress,
          cleaner: _ExplodingCleaner(installDir.path),
        ),
        completes,
      );
      expect(
        container.read(databaseInitProgressProvider).currentStep,
        equals('Εκκίνηση...'),
      );
    });
  });
}

/// Σαρωτής που σκάει: ο καθαρισμός οφείλει να το απορροφήσει.
class _ExplodingCleaner extends UpdateResidueCleaner {
  _ExplodingCleaner(String installDirectory)
    : super(installDirectory: installDirectory);

  @override
  Future<UpdateResidueScan> scan() async {
    throw const FileSystemException('δεν διαβάζεται ο κατάλογος');
  }
}
