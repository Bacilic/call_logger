import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/init/app_initializer.dart';
import 'package:call_logger/core/init/startup_notices.dart';
import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/providers/backup_scheduler_provider.dart';
import 'package:call_logger/features/database/providers/database_backup_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Το συμβόλαιο: μετά από επιτυχή βάση, ΚΑΝΕΝΑ προαιρετικό βήμα δεν επιτρέπεται
/// να ρίξει την εκκίνηση. Η ενεργοποίηση των αντιγράφων ασφαλείας ήταν το
/// μοναδικό βήμα του appInitProvider χωρίς αυτή την προστασία: ένας άφταστος
/// φάκελος προορισμού (UNC εκτός δικτύου νοσοκομείου) έντυνε μια υγιή βάση με
/// οθόνη σφάλματος «Σφάλμα πρόσβασης στο σύστημα αρχείων».
void main() {
  setUp(clearStartupNotices);
  tearDown(clearStartupNotices);

  test('σκάσιμο στην ενεργοποίηση αντιγράφων δεν διαδίδεται — γίνεται '
      'σημείωση εκκίνησης', () async {
    final container = ProviderContainer(
      // Χωρίς αυτόματες επαναδοκιμές: αν ο φράχτης αφαιρεθεί, το τεστ πρέπει
      // να κοκκινίσει αμέσως με την εξαίρεση — όχι να λήξει σε timeout όσο το
      // Riverpod ξαναδοκιμάζει τον αποτυχημένο provider.
      retry: (retryCount, error) => null,
      overrides: [
        databaseBackupSettingsProvider.overrideWith(
          _NetworkGoneSettingsNotifier.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    final probe = FutureProvider<void>(
      (ref) => AppInitializer.activateBackupSchedulingAfterDatabaseReady(ref),
    );

    await expectLater(container.read(probe.future), completes);

    expect(startupNotices, hasLength(1));
    expect(startupNotices.single.phase, 'Έλεγχος αντιγράφων ασφαλείας');
    expect(startupNotices.single.error, isA<PathNotFoundException>());
  });

  test('ο έλεγχος του φακέλου προορισμού δεν κρατά την εκκίνηση', () async {
    // Μετρημένο 15/10/2026: φάκελος αντιγράφων του νοσοκομείου ανοιγμένος από
    // το σπίτι — τα Windows θέλουν ~2,7 δευτ. για να πουν ότι δεν υπάρχει, και
    // τόσο κρατούσε κάθε άνοιγμα της εφαρμογής.
    final folderCheck = Completer<void>();
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        databaseBackupSettingsProvider.overrideWith(_QuietSettingsNotifier.new),
        backupSchedulerProvider.overrideWith(
          () => _SlowFolderSchedulerNotifier(folderCheck.future),
        ),
      ],
    );
    addTearDown(container.dispose);

    final probe = FutureProvider<void>(
      (ref) => AppInitializer.activateBackupSchedulingAfterDatabaseReady(ref),
    );

    await expectLater(
      container.read(probe.future).timeout(const Duration(seconds: 2)),
      completes,
    );
    expect(
      container.read(backupSchedulerProvider.notifier).debugDestinationCheck,
      isNotNull,
      reason: 'ο έλεγχος δεν καταργήθηκε — τρέχει στο παρασκήνιο',
    );
    folderCheck.complete();
  });
}

class _QuietSettingsNotifier extends DatabaseBackupSettingsNotifier {
  @override
  Future<void> load() async {}
}

/// Φάκελος προορισμού που αργεί να απαντήσει όσο θέλει το τεστ.
class _SlowFolderSchedulerNotifier extends BackupSchedulerNotifier {
  _SlowFolderSchedulerNotifier(this._answer);

  final Future<void> _answer;

  @override
  Future<void> checkDestinationFolderStatus(DatabaseBackupSettings settings) =>
      _answer;
}

/// Ρυθμίσεις αντιγράφων των οποίων η φόρτωση σκοντάφτει σε άφταστο δίκτυο —
/// ίδια εξαίρεση με το πραγματικό περιστατικό (OS error 53).
class _NetworkGoneSettingsNotifier extends DatabaseBackupSettingsNotifier {
  @override
  Future<void> load() async {
    throw PathNotFoundException(
      r'\\gnk.local\Departments\TPO\Utilities\Call Logger\Backups',
      const OSError('Η διαδρομή του δικτύου δεν εντοπίστηκε.', 53),
      'Exists failed',
    );
  }
}
