import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/backup_pending_changes.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/models/app_permission.dart';
import '../../../core/services/permission_service.dart';
import '../models/database_backup_settings.dart';
import '../providers/database_backup_settings_provider.dart';
import '../utils/backup_schedule_status.dart';

/// Πόσο συχνά ξαναμετριούνται οι αφύλακτες αλλαγές όσο η κάρτα είναι ανοιχτή.
const Duration _kBackupHealthRefreshInterval = Duration(seconds: 30);

/// Πόσες αλλαγές είναι αφύλακτες αυτή τη στιγμή — εισαγόμενο ώστε τα τεστ να
/// μη χρειάζονται πραγματική βάση (ο εικονικός χρόνος δεν κινεί FFI).
typedef BackupPendingChangesLoader =
    Future<int> Function(DatabaseBackupSettings settings);

/// Οι γραμμές υγείας αντιγράφων της κάρτας «Στατιστικά Βάσης» — ορατές σε
/// ΟΛΟΥΣ: αφύλακτες αλλαγές και επόμενο αντίγραφο για όποιον τα χειρίζεται,
/// «ενημερώστε τον διαχειριστή» για τους υπόλοιπους, και το τελευταίο πλήρες.
class BackupHealthStatRows extends ConsumerStatefulWidget {
  const BackupHealthStatRows({
    super.key,
    required this.labelWidth,
    this.pendingLoader,
  });

  final double labelWidth;

  /// Μόνο για τεστ: υποκατάστατο του μετρητή.
  @visibleForTesting
  final BackupPendingChangesLoader? pendingLoader;

  @override
  ConsumerState<BackupHealthStatRows> createState() =>
      _BackupHealthStatRowsState();
}

class _BackupHealthStatRowsState extends ConsumerState<BackupHealthStatRows> {
  Timer? _refreshTimer;
  Future<int> _pendingFuture = Future.value(0);

  @override
  void initState() {
    super.initState();
    _pendingFuture = _loadPending();
    _refreshTimer = Timer.periodic(_kBackupHealthRefreshInterval, (_) {
      if (!mounted) return;
      // Σκόπιμα ΟΧΙ `setState(() => _pendingFuture = _loadPending())`: η
      // ανάθεση με βέλος αποτιμάται στην τιμή της, οπότε το closure θα
      // επέστρεφε Future και το Flutter θα έσκαγε με «setState() callback
      // argument returned a Future». Το analyze δεν το πιάνει.
      setState(() {
        _pendingFuture = _loadPending();
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<int> _loadPending() {
    final settings = ref.read(databaseBackupSettingsProvider);
    final loader = widget.pendingLoader;
    if (loader != null) return loader(settings);
    return _loadPendingFromDatabase(settings);
  }

  Future<int> _loadPendingFromDatabase(DatabaseBackupSettings settings) async {
    try {
      final db = await DatabaseHelper.instance.database;
      return await BackupPendingChangesRepository(db).countPendingSince(
        settings.lastBackupAuditId,
        fallbackSince: settings.lastAnyBackupAt,
      );
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(databaseBackupSettingsProvider);
    final canManage = PermissionService.instance.can(AppPermission.fullBackup);

    Widget row(String label, String value, {bool warning = false}) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: widget.labelWidth,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: warning
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      )
                    : theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<int>(
      future: _pendingFuture,
      builder: (context, snapshot) {
        final health = BackupScheduleStatusFormatter.statsBackupHealth(
          settings: settings,
          pendingChanges: snapshot.data ?? 0,
          canManageBackups: canManage,
        );
        final lastFull = settings.lastFullBackupAt;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row('Κατάσταση αντιγράφων', health.text, warning: health.isWarning),
            if (lastFull != null)
              row(
                'Τελευταίο πλήρες αντίγραφο',
                BackupScheduleStatusFormatter.formatLocalDateTime(
                  lastFull.toLocal(),
                ),
              ),
          ],
        );
      },
    );
  }
}
