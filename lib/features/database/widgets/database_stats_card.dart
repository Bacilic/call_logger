import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path/path.dart' as p;

import '../../../core/database/database_init_result.dart';
import '../models/database_stats.dart';
import '../providers/active_sessions_provider.dart';
import '../services/active_sessions.dart';
import '../services/database_stats_service.dart';
import 'backup_health_stat_rows.dart';

/// Η κάρτα «Στατιστικά Βάσης Δεδομένων» στην κορυφή της οθόνης περιήγησης.
///
/// **Δύο στήλες, δύο ερωτήσεις:** αριστερά το **αρχείο** (πού είναι, πόσο
/// πιάνει, πότε σώθηκε), δεξιά η **ταυτότητα και η υγεία** του περιεχομένου
/// (πώς λέγεται, τι έκδοση σχήματος κρατά, ως πότε φτάνουν τα δεδομένα).
///
/// Ζει σε δικό της αρχείο επειδή η οθόνη που τη φιλοξενεί κάνει ήδη τέσσερις
/// άλλες δουλειές (περιήγηση πινάκων, προεπισκόπηση, μεγέθυνση, μετονομασία)·
/// η κάρτα δεν χρειάζεται τίποτα από αυτές, μόνο τα στατιστικά που της δίνονται.
class DatabaseStatsCard extends StatelessWidget {
  const DatabaseStatsCard({
    super.key,
    required this.databaseResult,
    required this.statsAsync,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEditLabel,
  });

  /// Το αποτέλεσμα του ανοίγματος — η πάνω γραμμή λέει αν η σύνδεση πέτυχε.
  final DatabaseInitResult databaseResult;

  final AsyncValue<DatabaseStats> statsAsync;

  /// Συμπτυγμένη ή ανοιχτή. Η προτίμηση αποθηκεύεται από τον γονέα, ώστε η
  /// κάρτα να μην αποκτήσει δική της μνήμη για κάτι που ανήκει στην οθόνη.
  final bool expanded;

  final VoidCallback onToggleExpanded;

  /// Κλικ στο όνομα της βάσης· δέχεται το τρέχον όνομα (ή `null`).
  final void Function(String? currentLabel) onEditLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = databaseResult;
    final stats = statsAsync.asData?.value;
    final connOk = r.isSuccess;
    final connText = connOk
        ? (r.message ?? 'Η σύνδεση με τη βάση δεδομένων πέτυχε.')
        : (r.message ?? 'Άγνωστο σφάλμα με τη βάση δεδομένων.');

    final backupText = stats != null
        ? (stats.lastBackupTime != null
              ? DateFormat.yMMMd(
                  'el',
                ).add_Hm().format(stats.lastBackupTime!.toLocal())
              : 'Δεν έχει γίνει ακόμα')
        : (statsAsync.isLoading ? '…' : '—');

    final sizeLabel = stats != null
        ? DatabaseStatsService.formatFileSizeBytes(stats.fileSizeBytes)
        : (statsAsync.isLoading ? '…' : '—');

    final pathText = stats?.dbPath ?? (statsAsync.isLoading ? '…' : '—');

    Widget statRow(String label, String value, {TextStyle? valueStyle}) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 200,
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
                style: valueStyle ?? theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggleExpanded,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Στατιστικά Βάσης Δεδομένων',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: expanded ? 'Σύμπτυξη' : 'Επέκταση',
                      child: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: expanded
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final left = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _fileColumn(
                            theme: theme,
                            connText: connText,
                            connOk: connOk,
                            details: r.details,
                            statRow: statRow,
                            sizeLabel: sizeLabel,
                            backupText: backupText,
                            pathText: pathText,
                            databaseName: databaseDisplayName(stats),
                          ),
                        );
                        final right = _identityColumn(theme, stats);
                        // Κάτω από αυτό το πλάτος οι δύο στήλες στριμώχνονται
                        // τόσο που η διαδρομή σπάει σε πέντε γραμμές: τότε η
                        // μία κάτω από την άλλη διαβάζεται καλύτερα.
                        if (constraints.maxWidth < 900) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [left, const SizedBox(height: 12), right],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: 14),
                            Expanded(child: right),
                          ],
                        );
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// Πώς λέγεται η βάση για τον χρήστη: το όνομα που της έδωσε αν υπάρχει,
  /// αλλιώς το όνομα του αρχείου της.
  ///
  /// Το δικό του όνομα είναι πιο χρήσιμο σε προειδοποίηση («Δικτυακή Βάση»
  /// λέει περισσότερα από «Hospital_shared.db»), αλλά είναι προαιρετικό — και
  /// το αρχείο υπάρχει πάντα.
  static String? databaseDisplayName(DatabaseStats? stats) {
    final label = stats?.label?.trim();
    if (label != null && label.isNotEmpty) return label;
    final path = stats?.dbPath.trim() ?? '';
    if (path.isEmpty) return null;
    final name = p.basename(path).trim();
    return name.isEmpty ? null : name;
  }

  /// Η αριστερή στήλη: το **αρχείο** — πού είναι, πόσο πιάνει, πότε σώθηκε.
  List<Widget> _fileColumn({
    required ThemeData theme,
    required String connText,
    required bool connOk,
    required String? details,
    required Widget Function(String, String, {TextStyle? valueStyle}) statRow,
    required String sizeLabel,
    required String backupText,
    required String pathText,
    required String? databaseName,
  }) {
    return [
      const SizedBox(height: 10),
      Text(
        connText,
        style: theme.textTheme.bodySmall?.copyWith(
          color: connOk ? Colors.green.shade700 : theme.colorScheme.error,
          fontWeight: FontWeight.w500,
        ),
      ),
      if (!connOk && details != null && details.trim().isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          details,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error.withValues(alpha: 0.85),
          ),
        ),
      ],
      if (statsAsync.isLoading) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Φόρτωση στατιστικών…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
      statRow('Μέγεθος αρχείου', sizeLabel),
      statRow('Τελευταίο αντίγραφο ασφαλείας', backupText),
      // Φάση 7: η υγεία των αντιγράφων ορατή σε ΟΛΟΥΣ — αφύλακτες αλλαγές,
      // καθυστερήσεις, τελευταίο πλήρες.
      BackupHealthStatRows(labelWidth: 200, databaseName: databaseName),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 200,
              child: Text(
                'Διαδρομή βάσης',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                pathText,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['Consolas', 'monospace'],
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Η δεξιά στήλη: **ταυτότητα και υγεία** του περιεχομένου.
  ///
  /// Ξεχωριστή επιφάνεια, όχι μόνο για διαχωρισμό: το όνομα δέχεται κλικ, και
  /// ένα πεδίο που πατιέται χρειάζεται ορατό όριο για να μη μοιάζει με ακόμη
  /// μία ετικέτα ανάμεσα σε ετικέτες.
  Widget _identityColumn(ThemeData theme, DatabaseStats? stats) {
    final pending = statsAsync.isLoading ? '…' : '—';

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
    }

    final label = stats?.label;
    final schema = stats?.schemaVersion;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: stats == null ? null : () => onEditLabel(label),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label ?? 'Χωρίς όνομα',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: label == null
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                        fontStyle: label == null ? FontStyle.italic : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          row('Έκδοση σχήματος', schema == null ? pending : '$schema'),
          row(
            'Τελευταία αλλαγή',
            _formatLastChange(stats?.lastChangeAt, pending),
          ),
          row('Κλήσεις', _formatCallRange(stats, pending)),
          row(
            'Χαμένος χώρος',
            _formatOptionalSize(stats?.reclaimableBytes, pending),
          ),
          // Μόνο όταν υπάρχει κάτι να αναφερθεί. Με κλασικό ημερολόγιο δεν
          // υπάρχει «-wal», οπότε μια γραμμή που θα έλεγε αιωνίως «καμία» δεν
          // πληροφορεί — αφήνει να εννοηθεί ότι μετράει κάτι.
          if ((stats?.pendingWalBytes ?? 0) > 0)
            row(
              'Εκκρεμείς εγγραφές',
              DatabaseStatsService.formatFileSizeBytes(stats!.pendingWalBytes!),
            ),
          _OpenNowRow(theme: theme),
        ],
      ),
    );
  }

  static String _formatLastChange(DateTime? value, String pending) {
    if (value == null) return pending;
    return DateFormat('dd/MM/yyyy, HH:mm').format(value);
  }

  /// «από–έως» με ελληνικές ημερομηνίες· μία μέρα δεν γράφεται δύο φορές.
  static String _formatCallRange(DatabaseStats? stats, String pending) {
    final first = stats?.firstCallDate;
    final last = stats?.lastCallDate;
    if (first == null || last == null) {
      return stats == null ? pending : 'καμία';
    }
    final a = _formatIsoDay(first);
    final b = _formatIsoDay(last);
    return a == b ? a : '$a – $b';
  }

  static String _formatIsoDay(String isoDay) {
    final parsed = DateTime.tryParse(isoDay);
    if (parsed == null) return isoDay;
    return DateFormat('dd/MM/yyyy').format(parsed);
  }

  static String _formatOptionalSize(int? bytes, String pending) {
    if (bytes == null) return pending;
    if (bytes <= 0) return 'κανένας';
    return DatabaseStatsService.formatFileSizeBytes(bytes);
  }
}

/// «Ανοιχτή τώρα από — 3 υπολογιστές», με τις συνεδρίες από κάτω.
///
/// **Εμφανίζεται μόνο όταν υπάρχει κι άλλος.** Σε βάση που δουλεύει ένας
/// άνθρωπος, μια γραμμή που θα έλεγε αιωνίως «1 υπολογιστής — εσείς» δεν
/// πληροφορεί· γεμίζει την κάρτα και σπρώχνει κάτω ό,τι μετράει.
class _OpenNowRow extends ConsumerWidget {
  const _OpenNowRow({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(activeSessionsProvider).asData?.value;
    if (sessions == null || otherSessions(sessions).isEmpty) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final mine = myAppVersion(sessions);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                'Ανοιχτή τώρα από',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                describeStationCount(distinctStationCount(sessions)),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final session in sessions)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 14),
              child: Text(
                describeActiveSession(session, now: now, myAppVersion: mine),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
