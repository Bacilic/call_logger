import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/changelog_entry.dart';
import '../providers/app_version_provider.dart';
import '../providers/changelog_provider.dart';
import '../version_display.dart';
import '../../updates/update_dialogs.dart';
import '../../updates/update_providers.dart';

/// Παράθυρο με ιστορικό αλλαγών ανά έκδοση και ημερομηνία (ελληνική μορφή).
class ChangelogDialog extends ConsumerWidget {
  const ChangelogDialog({super.key});

  static const double _maxWidth = 720;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changelogAsync = ref.watch(changelogProvider);
    final versionAsync = ref.watch(appVersionProvider);
    final updateResult = ref.watch(updateCheckProvider).asData?.value;
    final updateManifest = updateResult?.updateAvailable == true
        ? updateResult?.manifest
        : null;
    // Εκκρεμής (ήδη προετοιμασμένη) ενημέρωση σε αναμονή επανεκκίνησης.
    final pendingUpdate =
        ref.watch(pendingUpdateProvider).asData?.value ?? false;
    final screenH = MediaQuery.sizeOf(context).height;

    final titleVersion = versionAsync.maybeWhen(
      data: changelogSubtitleAppLine,
      orElse: () => 'Καταγραφή Κλήσεων',
    );

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _maxWidth,
          maxHeight: screenH * 0.7,
        ),
        child: SizedBox(
          width: math.min(
            _maxWidth,
            math.max(280.0, MediaQuery.sizeOf(context).width - 32),
          ),
          height: screenH * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ιστορικό Αλλαγών',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      titleVersion,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: changelogAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: SelectableText(
                      'Αποτυχία φόρτωσης ιστορικού: $e',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  data: (entries) => entries.isEmpty
                      ? Center(
                          child: Text(
                            'Δεν υπάρχουν καταχωρήσεις.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final e = entries[index];
                            return _VersionExpansionTile(
                              entry: e,
                              initiallyExpanded: index == 0,
                            );
                          },
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (pendingUpdate) ...[
                      FilledButton.icon(
                        key: const Key('changelog_restart_button'),
                        icon: const Icon(Icons.restart_alt),
                        onPressed: () {
                          final rootNav =
                              Navigator.of(context, rootNavigator: true);
                          rootNav.pop();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final ctx = rootNav.context;
                            if (!ctx.mounted) return;
                            launchPendingUpdateNow(ctx);
                          });
                        },
                        label: const Text('Επανεκκίνηση'),
                      ),
                      const SizedBox(width: 8),
                    ] else if (updateManifest != null) ...[
                      FilledButton(
                        key: const Key('changelog_update_button'),
                        onPressed: () {
                          final manifest = updateManifest;
                          final rootNav =
                              Navigator.of(context, rootNavigator: true);
                          rootNav.pop();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final ctx = rootNav.context;
                            if (!ctx.mounted) return;
                            runUpdatePrepareFlow(ctx, manifest);
                          });
                        },
                        child: const Text('Ενημέρωση'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Κλείσιμο'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionExpansionTile extends StatelessWidget {
  const _VersionExpansionTile({
    required this.entry,
    required this.initiallyExpanded,
  });

  final ChangelogEntry entry;
  final bool initiallyExpanded;

  String _formatDateHeader(BuildContext context) {
    try {
      final dt = DateTime.parse(entry.date);
      return DateFormat.yMMMMd('el_GR').format(dt);
    } catch (_) {
      return entry.date;
    }
  }

  String _headerTitle(BuildContext context) {
    if (entry.isUnreleased) {
      return ChangelogEntry.unreleasedDisplayTitle;
    }
    if (entry.date.isEmpty) {
      return 'v${entry.version}';
    }
    return 'v${entry.version} — ${_formatDateHeader(context)}';
  }

  @override
  Widget build(BuildContext context) {
    final header = _headerTitle(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(header, style: Theme.of(context).textTheme.titleSmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (entry.added.isNotEmpty)
            _CategoryBlock(
              label: 'Προστέθηκε',
              icon: Icons.add_circle_outline,
              items: entry.added,
            ),
          if (entry.improvements.isNotEmpty)
            _CategoryBlock(
              label: 'Μικροβελτιώσεις',
              icon: Icons.auto_fix_high_outlined,
              items: entry.improvements,
            ),
          if (entry.changed.isNotEmpty)
            _CategoryBlock(
              label: 'Άλλαξε',
              icon: Icons.tune,
              items: entry.changed,
            ),
          if (entry.fixed.isNotEmpty)
            _CategoryBlock(
              label: 'Διορθώθηκε',
              icon: Icons.bug_report_outlined,
              items: entry.fixed,
            ),
        ],
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.label,
    required this.icon,
    required this.items,
  });

  final String label;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in items)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: Theme.of(context).textTheme.bodyMedium),
                  Expanded(
                    child: Text(
                      line,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
