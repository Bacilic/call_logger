// Οι πύλες του νέου «πότε» (Φάση 3): αλλαγές → ελάχιστη απόσταση → κατώφλι ή
// μέγιστη αναμονή. Καθαρές συναρτήσεις — και οι δύο άκρες του χρόνου
// ορίζονται από το τεστ.
//
//   flutter test test/features/database/utils/backup_trigger_decision_test.dart

import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/utils/backup_trigger_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 24, 12, 0);

  DatabaseBackupSettings settingsWith({
    bool enabled = true,
    String destination = r'D:\backups',
    int threshold = 100,
    int minSpacing = 15,
    int maxWait = 240,
    DateTime? lastBackupAt,
    DateTime? lastManualAt,
    bool onClose = true,
  }) => DatabaseBackupSettings.defaults().copyWith(
    backupOnExit: enabled,
    destinationDirectory: destination,
    changeThreshold: threshold,
    minSpacingMinutes: minSpacing,
    maxWaitMinutes: maxWait,
    backupOnCloseIfPending: onClose,
    lastBackupAttempt: lastBackupAt,
    lastManualBackupAttempt: lastManualAt,
  );

  group('BackupTriggerDecision.evaluate', () {
    test('απενεργοποιημένα → ποτέ', () {
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(enabled: false),
        pendingChanges: 5000,
        now: now,
      );
      expect(d.due, isFalse);
      expect(d.reason, BackupTriggerReason.disabled);
    });

    test('χωρίς φάκελο προορισμού → ποτέ', () {
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(destination: '  '),
        pendingChanges: 5000,
        now: now,
      );
      expect(d.due, isFalse);
      expect(d.reason, BackupTriggerReason.noDestination);
    });

    test('καμία αλλαγή → κανένα αντίγραφο, όσος χρόνος κι αν περάσει', () {
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(
          lastBackupAt: now.subtract(const Duration(days: 30)),
        ),
        pendingChanges: 0,
        now: now,
      );
      expect(d.due, isFalse);
      expect(d.reason, BackupTriggerReason.noPendingChanges);
    });

    test('πρώτο αντίγραφο: αλλαγές χωρίς προηγούμενο σημάδι → αμέσως', () {
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(),
        pendingChanges: 1,
        now: now,
      );
      expect(d.due, isTrue);
      expect(d.reason, BackupTriggerReason.dueFirstBackup);
    });

    test('η ελάχιστη απόσταση φρενάρει ακόμη και γεμάτο κατώφλι', () {
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(
          lastBackupAt: now.subtract(const Duration(minutes: 10)),
        ),
        pendingChanges: 900,
        now: now,
      );
      expect(d.due, isFalse);
      expect(d.reason, BackupTriggerReason.spacingNotElapsed);
    });

    test('κατώφλι γεμάτο και απόσταση περασμένη → αντίγραφο', () {
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(
          lastBackupAt: now.subtract(const Duration(minutes: 16)),
        ),
        pendingChanges: 100,
        now: now,
      );
      expect(d.due, isTrue);
      expect(d.reason, BackupTriggerReason.dueThreshold);
    });

    test('λίγες αλλαγές πριν από τη μέγιστη αναμονή → αναμονή', () {
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(
          lastBackupAt: now.subtract(const Duration(minutes: 100)),
        ),
        pendingChanges: 7,
        now: now,
      );
      expect(d.due, isFalse);
      expect(d.reason, BackupTriggerReason.belowThreshold);
    });

    test('λίγες αλλαγές αλλά πέρασε η μέγιστη αναμονή → αντίγραφο', () {
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(
          lastBackupAt: now.subtract(const Duration(minutes: 241)),
        ),
        pendingChanges: 1,
        now: now,
      );
      expect(d.due, isTrue);
      expect(d.reason, BackupTriggerReason.dueMaxWait);
    });

    test('και το χειροκίνητο αντίγραφο μετρά ως «τελευταίο»', () {
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(
          lastBackupAt: now.subtract(const Duration(hours: 10)),
          lastManualAt: now.subtract(const Duration(minutes: 5)),
        ),
        pendingChanges: 900,
        now: now,
      );
      expect(
        d.due,
        isFalse,
        reason: 'Το φρέσκο χειροκίνητο μηδενίζει την απόσταση.',
      );
      expect(d.reason, BackupTriggerReason.spacingNotElapsed);
    });

    test('μέγιστη αναμονή μικρότερη από την απόσταση: ισχύει η απόσταση', () {
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(
          minSpacing: 60,
          maxWait: 15,
          lastBackupAt: now.subtract(const Duration(minutes: 59)),
        ),
        pendingChanges: 3,
        now: now,
      );
      expect(d.due, isFalse);
      expect(d.reason, BackupTriggerReason.spacingNotElapsed);

      final after = BackupTriggerDecision.evaluate(
        settings: settingsWith(
          minSpacing: 60,
          maxWait: 15,
          lastBackupAt: now.subtract(const Duration(minutes: 61)),
        ),
        pendingChanges: 3,
        now: now,
      );
      expect(after.due, isTrue);
      expect(after.reason, BackupTriggerReason.dueMaxWait);
    });
  });

  group('Ρολόι λάθος: η ώρα του τελευταίου αντιγράφου είναι στο μέλλον', () {
    // Ένας σταθμός με ρολόι μπροστά γράφει στις ΚΟΙΝΕΣ ρυθμίσεις ώρα που δεν
    // έχει έρθει ακόμη. Οι άλλοι σταθμοί μετρούν τότε με το δικό τους
    // χρονόμετρο, από τη στιγμή που πρωτοείδαν εκείνο το αντίγραφο.
    final future = now.add(const Duration(days: 3));

    test(
      'η ελάχιστη απόσταση μετρά από την πρώτη ματιά, όχι από το μέλλον',
      () {
        final reference = BackupElapsedReference();
        final settings = settingsWith(lastBackupAt: future);

        final atFirstSight = BackupTriggerDecision.evaluate(
          settings: settings,
          pendingChanges: 900,
          now: now,
          reference: reference,
        );
        expect(atFirstSight.reason, BackupTriggerReason.spacingNotElapsed);

        final later = BackupTriggerDecision.evaluate(
          settings: settings,
          pendingChanges: 900,
          now: now.add(const Duration(minutes: 16)),
          reference: reference,
        );
        expect(
          later.due,
          isTrue,
          reason:
              'Πριν από τη διόρθωση κανένας σταθμός δεν έπαιρνε αντίγραφο '
              'ώσπου να φτάσει εκείνη η ώρα, όσες αλλαγές κι αν μαζεύονταν.',
        );
        expect(later.reason, BackupTriggerReason.dueThreshold);
      },
    );

    test('και η μέγιστη αναμονή δουλεύει με λίγες αλλαγές', () {
      final reference = BackupElapsedReference();
      final settings = settingsWith(lastBackupAt: future);

      BackupTriggerDecision.evaluate(
        settings: settings,
        pendingChanges: 1,
        now: now,
        reference: reference,
      );
      final d = BackupTriggerDecision.evaluate(
        settings: settings,
        pendingChanges: 1,
        now: now.add(const Duration(minutes: 241)),
        reference: reference,
      );
      expect(d.due, isTrue);
      expect(d.reason, BackupTriggerReason.dueMaxWait);
    });

    test('νέο αντίγραφο με μελλοντική ώρα ξαναξεκινά τη μέτρηση', () {
      final reference = BackupElapsedReference();
      BackupTriggerDecision.evaluate(
        settings: settingsWith(lastBackupAt: future),
        pendingChanges: 900,
        now: now,
        reference: reference,
      );
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(
          lastBackupAt: future.add(const Duration(hours: 1)),
        ),
        pendingChanges: 900,
        now: now.add(const Duration(minutes: 30)),
        reference: reference,
      );
      expect(d.reason, BackupTriggerReason.spacingNotElapsed);
    });

    test('μελλοντικό χειροκίνητο, κατοπινό αυτόματο με σωστή ώρα: η '
        'απόσταση μετρά από το αυτόματο', () {
      final reference = BackupElapsedReference();
      BackupTriggerDecision.evaluate(
        settings: settingsWith(lastManualAt: future),
        pendingChanges: 900,
        now: now,
        reference: reference,
      );
      final justBackedUp = now.add(const Duration(minutes: 30));
      final d = BackupTriggerDecision.evaluate(
        settings: settingsWith(
          lastManualAt: future,
          lastBackupAt: justBackedUp,
        ),
        pendingChanges: 900,
        now: justBackedUp.add(const Duration(minutes: 5)),
        reference: reference,
      );
      expect(
        d.reason,
        BackupTriggerReason.spacingNotElapsed,
        reason: 'Το αντίγραφο πάρθηκε πριν από 5΄· η ελάχιστη απόσταση ισχύει.',
      );
    });
  });

  group('BackupTriggerDecision.shouldRunOnClose', () {
    test('αφύλακτες αλλαγές στο κλείσιμο → αντίγραφο, χωρίς κατώφλι', () {
      expect(
        BackupTriggerDecision.shouldRunOnClose(
          settings: settingsWith(
            lastBackupAt: now.subtract(const Duration(minutes: 2)),
          ),
          pendingChanges: 1,
        ),
        isTrue,
        reason:
            'Το κλείσιμο είναι η τελευταία ευκαιρία — απόσταση και κατώφλι '
            'δεν ισχύουν εδώ.',
      );
    });

    test('καμία αλλαγή → κανένα αντίγραφο στο κλείσιμο', () {
      expect(
        BackupTriggerDecision.shouldRunOnClose(
          settings: settingsWith(),
          pendingChanges: 0,
        ),
        isFalse,
      );
    });

    test('ο διακόπτης του κλεισίματος το απενεργοποιεί', () {
      expect(
        BackupTriggerDecision.shouldRunOnClose(
          settings: settingsWith(onClose: false),
          pendingChanges: 50,
        ),
        isFalse,
      );
    });

    test('κύριος διακόπτης κλειστός → τίποτα ούτε στο κλείσιμο', () {
      expect(
        BackupTriggerDecision.shouldRunOnClose(
          settings: settingsWith(enabled: false),
          pendingChanges: 50,
        ),
        isFalse,
      );
    });
  });
}
