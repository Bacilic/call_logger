import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_size_health.dart';
import '../providers/database_browser_stats_provider.dart';
import '../services/database_stats_service.dart';

/// Λέει με μια ματιά αν η βάση χρειάζεται εκκαθάριση — και πότε θα χρειαστεί.
///
/// **Συμβουλευτική και μόνο.** Δεν ενεργοποιεί τίποτα, δεν εμποδίζει τίποτα,
/// και δεν αλλάζει καμία ρύθμιση: απαντά στο «πρέπει να ασχοληθώ;» ώστε ο
/// χειριστής να μη χρειάζεται να μαντέψει τι σημαίνουν τα μεγαβάιτ.
///
/// **Γιατί εδώ και όχι στα Στατιστικά:** εκεί το μέγεθος είναι ένας αριθμός
/// ανάμεσα σε άλλους. Εδώ, ακριβώς από πάνω από τα όρια της εκκαθάρισης,
/// είναι η απάντηση στο ερώτημα που ήρθε να λύσει ο χειριστής.
class DatabaseSizeHealthCard extends ConsumerWidget {
  const DatabaseSizeHealthCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(databaseBrowserStatsProvider).value;
    if (stats == null) return const SizedBox.shrink();

    final verdict = judgeDatabaseSize(
      sizeBytes: stats.fileSizeBytes,
      oldestRecordAt: stats.oldestRecordAt,
      now: DateTime.now(),
    );

    final theme = Theme.of(context);
    final palette = _paletteFor(theme, verdict.level);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(palette.icon, color: palette.foreground, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DatabaseStatsService.formatFileSizeBytes(stats.fileSizeBytes)}'
                  ' · ${databaseSizeAdvice(verdict.level)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _detailLine(verdict),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Η δεύτερη γραμμή: τι σημαίνει το μέγεθος, και πόσο καιρό έχει ως το
  /// επόμενο όριο.
  ///
  /// Το «γιατί» μπαίνει πάντα, γιατί ο αριθμός μόνος του δεν λέει τίποτα: τα
  /// μεγαβάιτ γίνονται κατανοητά μόνο ως **δευτερόλεπτα αναμονής** στο
  /// αντίγραφο ασφαλείας.
  String _detailLine(DatabaseSizeVerdict verdict) {
    final seconds = verdict.backupSecondsOnSlowNetwork;
    final cost = seconds < 1
        ? 'Κάθε αντίγραφο ασφαλείας διαβάζει όλο το αρχείο — εδώ, ακαριαία.'
        : 'Κάθε αντίγραφο ασφαλείας διαβάζει όλο το αρχείο: περίπου '
              '${seconds.round()} δευτερόλεπτα σε αργό δίκτυο.';

    final days = verdict.daysUntilNextLevel;
    if (days == null) return cost;

    final threshold = verdict.nextLevelBytes == kDatabaseSizeCrowdedBytes
        ? '200 MB'
        : '50 MB';
    return '$cost Με τον σημερινό ρυθμό, φτάνει τα $threshold '
        '${formatDaysAhead(days)}.';
  }

  _SizePalette _paletteFor(ThemeData theme, DatabaseSizeLevel level) {
    // Τα χρώματα βγαίνουν από το θέμα και όχι από σταθερές τιμές, ώστε να
    // δουλεύουν και στο σκοτεινό θέμα.
    switch (level) {
      case DatabaseSizeLevel.comfortable:
        return _SizePalette(
          background: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
          border: theme.colorScheme.outlineVariant,
          foreground: theme.colorScheme.primary,
          icon: Icons.check_circle_outline,
        );
      case DatabaseSizeLevel.watch:
        return _SizePalette(
          background: theme.colorScheme.tertiaryContainer.withValues(
            alpha: 0.45,
          ),
          border: theme.colorScheme.tertiary.withValues(alpha: 0.5),
          foreground: theme.colorScheme.tertiary,
          icon: Icons.info_outline,
        );
      case DatabaseSizeLevel.crowded:
        return _SizePalette(
          background: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
          border: theme.colorScheme.error.withValues(alpha: 0.5),
          foreground: theme.colorScheme.error,
          icon: Icons.warning_amber_outlined,
        );
    }
  }
}

class _SizePalette {
  const _SizePalette({
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
  });

  final Color background;
  final Color border;
  final Color foreground;
  final IconData icon;
}
