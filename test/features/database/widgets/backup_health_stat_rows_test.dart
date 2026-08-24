// Η γραμμή υγείας αντιγράφων της κάρτας Στατιστικών: ο περιοδικός επανέλεγχος
// ΔΕΝ επιτρέπεται να σκάσει με «setState() callback argument returned a
// Future» — η ανάθεση με βέλος μέσα σε setState αποτιμάται στην τιμή της,
// οπότε ένα `setState(() => x = asyncCall())` επιστρέφει Future. Το analyze
// δεν το πιάνει· μόνο ένα widget test που αφήνει τον χρονιστή να χτυπήσει.
//
//   flutter test test/features/database/widgets/backup_health_stat_rows_test.dart

import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/providers/database_backup_settings_provider.dart';
import 'package:call_logger/features/database/widgets/backup_health_stat_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ρυθμίσεις χωρίς άγγιγμα βάσης — ο provider δεν φορτώνει μόνος του.
class _FixedSettingsNotifier extends DatabaseBackupSettingsNotifier {
  _FixedSettingsNotifier(this.value);

  final DatabaseBackupSettings value;

  @override
  DatabaseBackupSettings build() => value;

  @override
  Future<void> load() async {}
}

void main() {
  Future<void> pumpRows(
    WidgetTester tester, {
    required DatabaseBackupSettings settings,
    required Future<int> Function(DatabaseBackupSettings s) loader,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseBackupSettingsProvider.overrideWith(
            () => _FixedSettingsNotifier(settings),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BackupHealthStatRows(labelWidth: 200, pendingLoader: loader),
          ),
        ),
      ),
    );
  }

  testWidgets('ο περιοδικός επανέλεγχος δεν ρίχνει την οθόνη', (tester) async {
    var calls = 0;
    await pumpRows(
      tester,
      settings: DatabaseBackupSettings.defaults().copyWith(
        backupOnExit: true,
        destinationDirectory: r'D:\backups',
        lastBackupAttempt: DateTime.now(),
      ),
      loader: (_) async {
        calls++;
        return 3;
      },
    );
    await tester.pump();
    expect(calls, 1);

    // Ο χρονιστής της κάρτας χτυπά κάθε 30΄΄ — εδώ έσκαγε το setState.
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'setState με ανάθεση-βέλος επιστρέφει Future και ρίχνει την οθόνη.',
    );
    expect(calls, 2, reason: 'Ο επανέλεγχος όντως έτρεξε.');
    expect(find.textContaining('Αφύλακτες αλλαγές: 3'), findsOneWidget);
  });

  testWidgets('χωρίς αφύλακτες αλλαγές δείχνει ήσυχο μήνυμα', (tester) async {
    await pumpRows(
      tester,
      settings: DatabaseBackupSettings.defaults().copyWith(
        backupOnExit: true,
        destinationDirectory: r'D:\backups',
        lastBackupAttempt: DateTime.now(),
      ),
      loader: (_) async => 0,
    );
    await tester.pump();

    expect(find.textContaining('όλα φυλαγμένα'), findsOneWidget);
  });

  testWidgets('η κάρτα δείχνει το τελευταίο πλήρες όταν υπάρχει', (
    tester,
  ) async {
    await pumpRows(
      tester,
      settings: DatabaseBackupSettings.defaults().copyWith(
        backupOnExit: true,
        destinationDirectory: r'D:\backups',
        lastBackupAttempt: DateTime.now(),
        lastFullBackupAt: DateTime(2026, 8, 20, 9, 12),
      ),
      loader: (_) async => 0,
    );
    await tester.pump();

    expect(find.text('Τελευταίο πλήρες αντίγραφο'), findsOneWidget);
    expect(find.textContaining('20-08-2026 09:12'), findsOneWidget);
  });
}
