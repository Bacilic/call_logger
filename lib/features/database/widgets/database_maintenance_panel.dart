import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calls/provider/lookup_provider.dart';
import '../../settings/widgets/create_new_database_dialog.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../providers/database_browser_stats_provider.dart';
import '../providers/database_maintenance_provider.dart';
import '../services/database_maintenance_service.dart';

const Map<String, String> _kMaintenanceTableLabels = {
  'audit_log': 'Αρχείο καταγραφής (audit)',
  'tasks': 'Εκκρεμότητες',
  'knowledge_base': 'Βάση γνώσεων',
  'user_dictionary': 'Προσωπικό λεξικό',
};

/// Διάλογος συντήρησης βάσης (εκκαθάριση whitelist, VACUUM/REINDEX, νέα βάση).
class DatabaseMaintenancePanel extends ConsumerStatefulWidget {
  const DatabaseMaintenancePanel({
    super.key,
    required this.onDatabaseReopened,
  });

  final Future<void> Function() onDatabaseReopened;

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function() onDatabaseReopened,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DatabaseMaintenancePanel(
        onDatabaseReopened: onDatabaseReopened,
      ),
    );
  }

  @override
  ConsumerState<DatabaseMaintenancePanel> createState() =>
      _DatabaseMaintenancePanelState();
}

class _DatabaseMaintenancePanelState
    extends ConsumerState<DatabaseMaintenancePanel> {
  bool _busy = false;
  String? _banner;
  bool _bannerError = false;
  int _auditMonths = 6;

  Future<void> _runGuarded(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _banner = null;
    });
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showBanner(String msg, {bool error = false}) {
    setState(() {
      _banner = msg;
      _bannerError = error;
    });
  }

  Future<bool> _doubleConfirm(
    BuildContext context, {
    required String title,
    required String body,
  }) async {
    final t = Theme.of(context);
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body, style: t.textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
    if (first != true || !context.mounted) return false;
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Τελική επιβεβαίωση'),
        content: const Text(
          'Η ενέργεια δεν αναιρείται. Θέλετε σίγουρα να συνεχίσετε;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Όχι'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              foregroundColor: t.colorScheme.onError,
              backgroundColor: t.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ναι, εκτέλεση'),
          ),
        ],
      ),
    );
    return second == true;
  }

  Future<bool> _ensureBackupOrWarn(BuildContext context) async {
    final svc = ref.read(databaseMaintenanceServiceProvider);
    final r = await svc.runPreMaintenanceBackup();
    if (r.kind == MaintenanceBackupPrecheck.ok) {
      return true;
    }
    if (!context.mounted) return false;
    if (r.kind == MaintenanceBackupPrecheck.failed) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Αποτυχία αντιγράφου ασφαλείας'),
          content: Text(
            r.message ?? 'Άγνωστο σφάλμα.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Συνέχεια χωρίς αντίγραφο'),
            ),
          ],
        ),
      );
      return proceed == true;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αντίγραφο ασφαλείας'),
        content: const Text(
          'Δεν είναι ενεργό αυτόματο αντίγραφο ή δεν έχει οριστεί φάκελος προορισμού. '
          'Να συνεχιστεί χωρίς αντίγραφο;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  void _invalidateCaches() {
    ref.invalidate(databaseBrowserStatsProvider);
    ref.invalidate(lookupServiceProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(orphanCallsProvider);
  }

  Future<void> _onVacuum(BuildContext context) async {
    final ok = await _doubleConfirm(
      context,
      title: 'VACUUM',
      body:
          'Θα εκτελεστεί VACUUM στην ενεργή βάση. Μεγάλα αρχεία μπορεί να καθυστερήσουν.',
    );
    if (!ok || !context.mounted) return;
    await _runGuarded(() async {
      try {
        await ref.read(databaseMaintenanceServiceProvider).runVacuum();
        _showBanner('Το VACUUM ολοκληρώθηκε.');
        _invalidateCaches();
      } catch (e) {
        _showBanner('Σφάλμα VACUUM: $e', error: true);
      }
    });
  }

  Future<void> _onReindex(BuildContext context) async {
    final ok = await _doubleConfirm(
      context,
      title: 'REINDEX',
      body: 'Θα αναδομηθούν όλα τα ευρετήρια της βάσης.',
    );
    if (!ok || !context.mounted) return;
    await _runGuarded(() async {
      try {
        await ref.read(databaseMaintenanceServiceProvider).runReindex();
        _showBanner('Το REINDEX ολοκληρώθηκε.');
        _invalidateCaches();
      } catch (e) {
        _showBanner('Σφάλμα REINDEX: $e', error: true);
      }
    });
  }

  Future<void> _onClearTableFull(
    BuildContext context,
    String table,
  ) async {
    final label = _kMaintenanceTableLabels[table] ?? table;
    if (!await _ensureBackupOrWarn(context) || !context.mounted) return;
    final ok = await _doubleConfirm(
      context,
      title: 'Πλήρες καθάρισμα: $label',
      body:
          'Θα διαγραφούν όλες οι εγγραφές του πίνακα «$label» ($table).',
    );
    if (!ok || !context.mounted) return;
    await _runGuarded(() async {
      try {
        final n = await ref
            .read(databaseMaintenanceServiceProvider)
            .clearTableFull(table);
        _showBanner('Διαγράφηκαν $n εγγραφές από $label.');
        _invalidateCaches();
      } catch (e) {
        _showBanner('Σφάλμα: $e', error: true);
      }
    });
  }

  Future<void> _onAuditOlderThanMonths(BuildContext context) async {
    if (!await _ensureBackupOrWarn(context) || !context.mounted) return;
    final ok = await _doubleConfirm(
      context,
      title: 'Εκκαθάριση audit',
      body:
          'Θα διαγραφούν εγγραφές audit παλαιότερες των $_auditMonths μηνών.',
    );
    if (!ok || !context.mounted) return;
    await _runGuarded(() async {
      try {
        final svc = ref.read(databaseMaintenanceServiceProvider);
        final cutoff = DatabaseMaintenanceService.subtractCalendarMonths(
          DateTime.now(),
          _auditMonths,
        );
        final n = await svc.deleteAuditLogOlderThan(cutoff);
        _showBanner('Διαγράφηκαν $n εγγραφές audit.');
        _invalidateCaches();
      } catch (e) {
        _showBanner('Σφάλμα: $e', error: true);
      }
    });
  }

  Future<void> _onAuditPickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !context.mounted) return;
    final cutoff =
        DateTime(picked.year, picked.month, picked.day);
    if (!await _ensureBackupOrWarn(context) || !context.mounted) return;
    final ok = await _doubleConfirm(
      context,
      title: 'Εκκαθάριση audit',
      body:
          'Θα διαγραφούν εγγραφές audit με ημερομηνία πριν την ${cutoff.toLocal().toString().split(' ').first}.',
    );
    if (!ok || !context.mounted) return;
    await _runGuarded(() async {
      try {
        final n = await ref
            .read(databaseMaintenanceServiceProvider)
            .deleteAuditLogOlderThan(cutoff);
        _showBanner('Διαγράφηκαν $n εγγραφές audit.');
        _invalidateCaches();
      } catch (e) {
        _showBanner('Σφάλμα: $e', error: true);
      }
    });
  }

  Future<void> _onTasksClosedSixMonths(BuildContext context) async {
    if (!await _ensureBackupOrWarn(context) || !context.mounted) return;
    final ok = await _doubleConfirm(
      context,
      title: 'Κλειστές εκκρεμότητες',
      body:
          'Θα διαγραφούν μόνο ολοκληρωμένες εκκρεμότητες με τελευταία ενημέρωση παλαιότερη των 6 μηνών.',
    );
    if (!ok || !context.mounted) return;
    await _runGuarded(() async {
      try {
        final n = await ref
            .read(databaseMaintenanceServiceProvider)
            .deleteClosedTasksOlderThanSixMonths();
        _showBanner('Διαγράφηκαν $n κλειστές εκκρεμότητες.');
        _invalidateCaches();
      } catch (e) {
        _showBanner('Σφάλμα: $e', error: true);
      }
    });
  }

  Future<void> _onCreateNewDatabase(BuildContext context) async {
    await CreateNewDatabaseFlow.run(
      context,
      ref,
      onDatabaseReopened: widget.onDatabaseReopened,
      onFlowSuccessCloseParent: () {
        if (context.mounted) Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.sizeOf(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.build_circle_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Συντήρηση Βάσης Δεδομένων'),
          ),
        ],
      ),
      content: SizedBox(
        width: (mq.width * 0.5).clamp(360.0, 560.0),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_banner != null) ...[
                    Material(
                      color: _bannerError
                          ? theme.colorScheme.errorContainer
                              .withValues(alpha: 0.9)
                          : theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _banner!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _bannerError
                                ? theme.colorScheme.onErrorContainer
                                : theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _sectionTitle(theme, 'Εκκαθάριση'),
                  const SizedBox(height: 8),
                  ...DatabaseMaintenanceService.purgeableTablesUiOrder
                      .map((t) => _tableSection(context, theme, t)),
                  const SizedBox(height: 16),
                  _sectionTitle(theme, 'Βελτιστοποίηση'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _onVacuum(context),
                        icon: const Icon(Icons.compress),
                        label: const Text('VACUUM'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _onReindex(context),
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('Αναδόμηση ευρετηρίων'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle(theme, 'Νέα βάση'),
                  const SizedBox(height: 8),
                  Text(
                    'Η τρέχουσα βάση μετονομάζεται σε «call_logger_old_ημερομηνία.db» στην ίδια θέση και δημιουργείται νέο κενό αρχείο.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: _busy ? null : () => _onCreateNewDatabase(context),
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Δημιουργία νέας βάσης'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            if (_busy)
              const Positioned.fill(
                child: AbsorbPointer(
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Παρακαλώ περιμένετε…'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Κλείσιμο'),
        ),
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _tableSection(BuildContext context, ThemeData theme, String table) {
    final label = _kMaintenanceTableLabels[table] ?? table;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              table,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 10),
            if (table == 'audit_log') ...[
              Row(
                children: [
                  Text(
                    'Μήνες:',
                    style: theme.textTheme.bodySmall,
                  ),
                  Expanded(
                    child: Slider(
                      value: _auditMonths.toDouble(),
                      min: 1,
                      max: 36,
                      divisions: 35,
                      label: '$_auditMonths',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _auditMonths = v.round()),
                    ),
                  ),
                  Text(
                    '$_auditMonths',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _onAuditOlderThanMonths(context),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text('Διαγραφή παλαιότερων των $_auditMonths μηνών'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _onAuditPickDate(context),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Με βάση ημερομηνία…'),
                  ),
                ],
              ),
            ],
            if (table == 'tasks') ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _onTasksClosedSixMonths(context),
                    icon: const Icon(Icons.task_alt),
                    label: const Text(
                      'Κλειστές > 6 μηνών',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed:
                    _busy ? null : () => _onClearTableFull(context, table),
                icon: Icon(
                  Icons.delete_forever_outlined,
                  color: theme.colorScheme.error,
                ),
                label: Text(
                  'Πλήρες καθάρισμα πίνακα',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
