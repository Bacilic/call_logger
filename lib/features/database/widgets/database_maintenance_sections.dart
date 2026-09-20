import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/audit_retention_config.dart';
import '../../../core/models/app_permission.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/audit_retention_runner.dart';
import '../../../core/services/audit_retention_plan.dart';
import 'audit_retention_preview_dialog.dart';
import 'database_size_health_card.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../audit/providers/audit_providers.dart';
import '../../calls/provider/lookup_provider.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../providers/database_browser_stats_provider.dart';
import '../providers/database_maintenance_provider.dart';
import '../services/database_maintenance_service.dart';
import 'other_sessions_gate.dart';

const Map<String, String> _kMaintenanceTableLabels = {
  'audit_log': 'Αρχείο καταγραφής (audit)',
  'tasks': 'Εκκρεμότητες',
  'knowledge_base': 'Βάση Γνώσης',
  'user_dictionary': 'Προσωπικό λεξικό',
};

/// Οι ενότητες συντήρησης της βάσης: εκκαθάριση ιστορικού, VACUUM, αναδόμηση
/// ευρετηρίων.
///
/// **Ενσωματώνεται** στην καρτέλα «Συντήρηση» των Ρυθμίσεων αντί να ανοίγει ως
/// ξεχωριστός διάλογος: όσο ζούσε έξω, η συντήρηση ήταν μοιρασμένη σε δύο
/// σπίτια — μια καρτέλα που λεγόταν «Συντήρηση» και είχε μόνο τον έλεγχο
/// ακεραιότητας, και ένας διάλογος αλλού που έκανε τη δουλειά.
///
/// Η «Νέα βάση» έφυγε από εδώ: η δημιουργία και η εναλλαγή αρχείων ανήκουν
/// στην καρτέλα «Βάση», και το να υπάρχει το ίδιο κουμπί σε δύο σημεία σήμαινε
/// δύο δρόμους προς μια μη αναστρέψιμη ενέργεια.
class DatabaseMaintenanceSections extends ConsumerStatefulWidget {
  const DatabaseMaintenanceSections({super.key});

  @override
  ConsumerState<DatabaseMaintenanceSections> createState() =>
      _DatabaseMaintenanceSectionsState();
}

class _DatabaseMaintenanceSectionsState
    extends ConsumerState<DatabaseMaintenanceSections> {
  bool _busy = false;
  String? _banner;
  bool _bannerError = false;
  int _auditMonths = 6;

  AuditRetentionConfig _retentionCfg = const AuditRetentionConfig();

  /// Επίπεδο 1 — μετά από πόσες μέρες πετιέται το βοηθητικό κείμενο.
  final TextEditingController _compactDaysController = TextEditingController();

  /// Επίπεδο 2 — όριο ηλικίας για τις αλλαγές σε καρτέλες.
  final TextEditingController _operationalDaysController =
      TextEditingController();

  /// Επίπεδο 2 — όριο ηλικίας για κλήσεις, εκκρεμότητες, αντίγραφα.
  final TextEditingController _volatileDaysController = TextEditingController();

  final TextEditingController _retentionRowsController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRetentionConfig();
  }

  @override
  void dispose() {
    _compactDaysController.dispose();
    _operationalDaysController.dispose();
    _volatileDaysController.dispose();
    _retentionRowsController.dispose();
    super.dispose();
  }

  Future<void> _loadRetentionConfig() async {
    final c = await SettingsService().catalogs.getAuditRetentionConfig();
    if (!mounted) return;
    setState(() {
      _retentionCfg = c;
      _compactDaysController.text = c.compactSearchTextAfterDays != null
          ? '${c.compactSearchTextAfterDays}'
          : '';
      _operationalDaysController.text = c.operationalMaxAgeDays != null
          ? '${c.operationalMaxAgeDays}'
          : '';
      _volatileDaysController.text = c.volatileMaxAgeDays != null
          ? '${c.volatileMaxAgeDays}'
          : '';
      _retentionRowsController.text = c.maxRows != null ? '${c.maxRows}' : '';
    });
  }

  AuditRetentionConfig _retentionFromForm() {
    int? read(TextEditingController c) {
      final raw = c.text.trim();
      return raw.isEmpty ? null : int.tryParse(raw);
    }

    bool empty(TextEditingController c) => c.text.trim().isEmpty;

    return _retentionCfg.copyWith(
      compactSearchTextAfterDays: read(_compactDaysController),
      clearCompactSearchText: empty(_compactDaysController),
      operationalMaxAgeDays: read(_operationalDaysController),
      clearOperationalMaxAge: empty(_operationalDaysController),
      volatileMaxAgeDays: read(_volatileDaysController),
      clearVolatileMaxAge: empty(_volatileDaysController),
      maxRows: read(_retentionRowsController),
      clearMaxRows: empty(_retentionRowsController),
    );
  }

  Future<void> _onSaveRetentionConfig() async {
    final next = _retentionFromForm();
    await _runGuarded(() async {
      try {
        await SettingsService().catalogs.setAuditRetentionConfig(next);
        if (mounted) {
          setState(() => _retentionCfg = next);
        }
        _showBanner('Οι ρυθμίσεις retention audit αποθηκεύτηκαν.');
      } catch (e) {
        _showBanner(
          'Σφάλμα αποθήκευσης: ${humanizeUserFacingError(e)}',
          error: true,
        );
      }
    });
  }

  /// Εκκαθάριση με προεπισκόπηση: **πρώτα** δείχνει τι θα σβηστεί.
  ///
  /// Το σχέδιο που εγκρίνεται είναι **το ίδιο αντικείμενο** που εκτελείται —
  /// δεν ξαναϋπολογίζεται μετά την έγκριση, ώστε να μη διαφέρει από αυτό που
  /// είδε ο χειριστής.
  Future<void> _onPurgeAuditRetentionNow(BuildContext context) async {
    final cfg = _retentionFromForm();
    if (!cfg.hasAnyPolicy) {
      _showBanner('Ορίστε τουλάχιστον ένα όριο παραπάνω.', error: true);
      return;
    }

    AuditRetentionPlan plan;
    try {
      plan = await AuditRetentionRunner.buildPlan(cfg);
    } catch (e) {
      _showBanner(
        'Δεν ήταν δυνατός ο υπολογισμός: ${humanizeUserFacingError(e)}',
        error: true,
      );
      return;
    }
    if (!context.mounted) return;

    if (plan.isNoOp) {
      _showBanner('Με αυτά τα όρια δεν υπάρχει τίποτα να καθαριστεί.');
      return;
    }

    final approved = await showAuditRetentionPreviewDialog(
      context: context,
      plan: plan,
      exportsBeforePurge: cfg.exportBeforePurge,
    );
    if (!approved || !context.mounted) return;

    await _runGuarded(() async {
      try {
        final r = await AuditRetentionRunner.executePlan(plan, cfg);
        ref.invalidate(auditListProvider);
        final parts = <String>[];
        if (r.deleted > 0) parts.add('διαγράφηκαν ${r.deleted} εγγραφές');
        if (r.compacted > 0) {
          parts.add('συμπιέστηκαν ${r.compacted} χωρίς απώλεια');
        }
        if (r.exportPath != null) parts.add('αντίγραφο: ${r.exportPath}');
        _showBanner(
          parts.isEmpty ? 'Δεν χρειάστηκε καμία αλλαγή.' : parts.join(' · '),
        );
      } catch (e) {
        _showBanner('Σφάλμα: ${humanizeUserFacingError(e)}', error: true);
      }
    });
  }

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

  /// Η τελετουργία πριν από κάθε μη αναστρέψιμη ενέργεια συντήρησης.
  ///
  /// **Ο φρουρός των ανοιχτών συνεδριών ζει εδώ, όχι στα κουμπιά.** Κάθε ροή
  /// αυτής της οθόνης περνά από εδώ, οπότε καμία δεν μπορεί να ξεχάσει να
  /// ρωτήσει ποιος άλλος έχει τη βάση ανοιχτή — ούτε αυτές που θα προστεθούν
  /// αργότερα. Ρωτά **πρώτος**: ο άνθρωπος μαθαίνει ότι υπάρχουν άλλοι μέσα
  /// πριν ξεκινήσει τη διπλή επιβεβαίωση, όχι στο τέλος της.
  Future<bool> _doubleConfirm(
    BuildContext context, {
    required String title,
    required String body,
  }) async {
    if (!await confirmDespiteOtherSessions(context, actionLabel: title) ||
        !context.mounted) {
      return false;
    }
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
          content: Text(r.message ?? 'Άγνωστο σφάλμα.'),
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
    ref.invalidate(totalTasksCountProvider);
    ref.invalidate(orphanCallsProvider);
    ref.read(taskServiceProvider).resetSnoozeHistoryColumnCache();
    // Άμεσο flush ώστε το lookup να μη μείνει «βρόμικο» και ξεπλυθεί σύγχρονα
    // μέσα στο επόμενο build της οθόνης κλήσεων (setState during build).
    ref.read(lookupServiceProvider);
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
        _showBanner(
          'Σφάλμα VACUUM: ${humanizeUserFacingError(e)}',
          error: true,
        );
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
        _showBanner(
          'Σφάλμα REINDEX: ${humanizeUserFacingError(e)}',
          error: true,
        );
      }
    });
  }

  Future<void> _onClearTableFull(BuildContext context, String table) async {
    final label = _kMaintenanceTableLabels[table] ?? table;
    if (!await _ensureBackupOrWarn(context) || !context.mounted) return;
    final ok = await _doubleConfirm(
      context,
      title: 'Πλήρες καθάρισμα: $label',
      body: 'Θα διαγραφούν όλες οι εγγραφές του πίνακα «$label» ($table).',
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
        _showBanner('Σφάλμα: ${humanizeUserFacingError(e)}', error: true);
      }
    });
  }

  Future<void> _onAuditOlderThanMonths(BuildContext context) async {
    if (!await _ensureBackupOrWarn(context) || !context.mounted) return;
    final ok = await _doubleConfirm(
      context,
      title: 'Εκκαθάριση audit',
      body: 'Θα διαγραφούν εγγραφές audit παλαιότερες των $_auditMonths μηνών.',
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
        _showBanner('Σφάλμα: ${humanizeUserFacingError(e)}', error: true);
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
    final cutoff = DateTime(picked.year, picked.month, picked.day);
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
        _showBanner('Σφάλμα: ${humanizeUserFacingError(e)}', error: true);
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
        _showBanner('Σφάλμα: ${humanizeUserFacingError(e)}', error: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Χωρίς κέλυφος διαλόγου και χωρίς σταθερό πλάτος: το πλάτος το ορίζει
    // πλέον η καρτέλα που μας φιλοξενεί.
    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_banner != null) ...[
                Material(
                  color: _bannerError
                      ? theme.colorScheme.errorContainer.withValues(alpha: 0.9)
                      : theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.55,
                        ),
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
              // Ορίζει τι σβήνεται αυτόματα από το Ιστορικό και πότε. Το
              // λάθος εδώ δεν φαίνεται τη στιγμή που γίνεται — φαίνεται
              // μήνες μετά, όταν ψάξεις παλιά εγγραφή και δεν υπάρχει πια.
              if (PermissionService.instance.can(
                AppPermission.manageAuditRetention,
              )) ...[
                _sectionTitle(theme, 'Αυτόματη εκκαθάριση audit (retention)'),
                const SizedBox(height: 8),
                // Η απάντηση στο «πρέπει να ασχοληθώ;» μπαίνει ΠΡΙΝ από τα
                // όρια: χωρίς αυτήν, ο χειριστής καλείται να ρυθμίσει κάτι
                // χωρίς να ξέρει αν το χρειάζεται.
                const DatabaseSizeHealthCard(),
                const SizedBox(height: 8),
                // Η ρύθμιση είναι ΚΟΙΝΗ (SharedSettingKeys.auditRetentionConfig)
                // και το έλεγε «τοπική»: ο χειριστής όριζε 90 ημέρες νομίζοντας
                // ότι ρυθμίζει τον υπολογιστή του, και η επόμενη εκκίνηση
                // οποιουδήποτε σταθμού έσβηνε το Ιστορικό όλων.
                Text(
                  'Περιορισμός μεγέθους του πίνακα audit_log. Η πολιτική είναι '
                  'κοινή για όλους τους σταθμούς — ό,τι ορίσετε εδώ ισχύει για '
                  'όλους, και η εκκαθάριση σβήνει οριστικά εγγραφές από το '
                  'Ιστορικό όλων.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                // ΕΝΑΣ διακόπτης, όχι δύο. Ως τις 18/09/2026 υπήρχε από πάνω
                // και μια «Ενεργή πολιτική retention» που δεν έκανε τίποτα
                // μόνη της: η εκκαθάριση απαιτούσε ούτως ή άλλως και αυτόν
                // εδώ, οπότε «αναμμένη πολιτική με σβηστή εκκίνηση» έδειχνε
                // ενεργή ρύθμιση που δεν επρόκειτο να τρέξει ποτέ.
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Εκκαθάριση κατά την εκκίνηση εφαρμογής'),
                  subtitle: const Text(
                    'Σε κάθε άνοιγμα, όποιου σταθμού, εφαρμόζονται τα όρια '
                    'παρακάτω. Σβηστό: τίποτα δεν διαγράφεται αυτόματα.',
                  ),
                  value: _retentionCfg.purgeOnAppStart,
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () => _retentionCfg = _retentionCfg.copyWith(
                            purgeOnAppStart: v,
                          ),
                        ),
                ),
                const SizedBox(height: 14),

                // ── Επίπεδο 1: συμπίεση χωρίς απώλεια ──────────────────────
                _retentionFieldGroup(
                  theme,
                  title: 'Συμπίεση παλιών εγγραφών',
                  description:
                      'Πετά μόνο το βοηθητικό κείμενο που κρατά η εφαρμογή '
                      'για γρήγορη αναζήτηση. Καμία εγγραφή δεν σβήνεται και '
                      'τίποτα δεν χάνεται — μετρημένο, κερδίζει τα δύο τρίτα '
                      'του χώρου. Οι παλιές εγγραφές γίνονται πιο δύσκολα '
                      'αναζητήσιμες, και το κείμενο ξαναφτιάχνεται όποτε '
                      'θέλετε.',
                  child: TextField(
                    controller: _compactDaysController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Μετά από (ημέρες)',
                      hintText: 'Κενό = ποτέ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),

                // ── Επίπεδο 2: διαβάθμιση ανά είδος ────────────────────────
                _retentionFieldGroup(
                  theme,
                  title: 'Οριστική διαγραφή, ανά είδος εγγραφής',
                  description:
                      'Οι δημιουργίες και οι διαγραφές του Καταλόγου '
                      '(υπάλληλοι, τμήματα, εξοπλισμός, τηλέφωνα) **δεν '
                      'σβήνονται ποτέ**: είναι η μόνη απάντηση στο «ποιος το '
                      'έφτιαξε και πότε». Τα παρακάτω όρια αφορούν μόνο τα '
                      'υπόλοιπα.',
                  child: Column(
                    children: [
                      TextField(
                        controller: _volatileDaysController,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText:
                              'Κλήσεις, εκκρεμότητες, αντίγραφα (ημέρες)',
                          hintText:
                              'Κενό = χωρίς όριο · οι ίδιες οι κλήσεις μένουν '
                              'άθικτες',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _operationalDaysController,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Αλλαγές σε καρτέλες (ημέρες)',
                          hintText:
                              'Κενό = χωρίς όριο · η σημερινή μορφή της '
                              'καρτέλας μένει',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _retentionRowsController,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Μέγιστο συνολικό πλήθος γραμμών',
                          hintText: 'Κενό = χωρίς όριο πλήθους',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Επίπεδο 3: δικλείδες ───────────────────────────────────
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Αντίγραφο πριν από κάθε διαγραφή'),
                  subtitle: Text(
                    'Ό,τι πρόκειται να σβηστεί γράφεται πρώτα σε αρχείο '
                    'δίπλα στη βάση. Αν η εγγραφή αποτύχει, δεν σβήνεται '
                    'τίποτα. Κρατάει πάντα τουλάχιστον '
                    '${_retentionCfg.minimumRowsFloor} γραμμές, όποια όρια '
                    'κι αν οριστούν.',
                    style: theme.textTheme.bodySmall,
                  ),
                  value: _retentionCfg.exportBeforePurge,
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () => _retentionCfg = _retentionCfg.copyWith(
                            exportBeforePurge: v,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _onSaveRetentionConfig,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Αποθήκευση ρυθμίσεων'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy
                          ? null
                          : () => _onPurgeAuditRetentionNow(context),
                      icon: const Icon(Icons.auto_delete_outlined),
                      label: const Text('Εκκαθάριση τώρα'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              _sectionTitle(theme, 'Εκκαθάριση'),
              const SizedBox(height: 8),
              ...DatabaseMaintenanceService.purgeableTablesUiOrder.map(
                (t) => _tableSection(context, theme, t),
              ),
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
              const SizedBox(height: 8),
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
    );
  }

  /// Μια ομάδα πεδίων της εκκαθάρισης, με τίτλο και εξήγηση από πάνω.
  ///
  /// Ζει εδώ ώστε τα τρία επίπεδα να μοιάζουν μεταξύ τους χωρίς να
  /// επαναληφθεί τρεις φορές η ίδια διάταξη.
  Widget _retentionFieldGroup(
    ThemeData theme, {
    required String title,
    required String description,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
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
                  Text('Μήνες:', style: theme.textTheme.bodySmall),
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
                  Text('$_auditMonths', style: theme.textTheme.labelLarge),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _onAuditOlderThanMonths(context),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text('Διαγραφή παλαιότερων των $_auditMonths μηνών'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _onAuditPickDate(context),
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
                    onPressed: _busy
                        ? null
                        : () => _onTasksClosedSixMonths(context),
                    icon: const Icon(Icons.task_alt),
                    label: const Text('Κλειστές > 6 μηνών'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _onClearTableFull(context, table),
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
