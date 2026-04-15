import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../provider/calls_dashboard_providers.dart';

class GlobalRecentCallsList extends ConsumerWidget {
  const GlobalRecentCallsList({super.key});

  String _displayOrDash(String? text) {
    final value = (text ?? '').trim();
    return value.isEmpty ? '—' : value;
  }

  Color _statusColor(BuildContext context, String status) {
    final v = status.toLowerCase();
    if (v == 'pending') return Colors.orange.shade700;
    if (v == 'completed') return Colors.green.shade700;
    return Theme.of(context).colorScheme.outline;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isVisible = ref.watch(showGlobalCallsToggleProvider);

    Widget content;
    if (!isVisible) {
      content = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Η προβολή είναι προσωρινά κρυφή.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      final asyncCalls = ref.watch(globalRecentCallsProvider);
      content = asyncCalls.when(
        data: (calls) {
          if (calls.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Δεν υπάρχουν πρόσφατες κλήσεις.'),
            );
          }
          return Column(
            children: [
              for (final c in calls)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          c.time ?? '--:--',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text(
                          _displayOrDash(c.phoneText),
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _displayOrDash(c.callerText),
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 95,
                        child: Text(
                          _displayOrDash(c.departmentText),
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(
                            context,
                            c.status ?? '',
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          (c.status ?? '—').toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _statusColor(context, c.status ?? ''),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Αποτυχία φόρτωσης ιστορικού.'),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Τελευταίες 7 Κλήσεις',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Switch(
                  value: isVisible,
                  onChanged: (value) => ref
                      .read(showGlobalCallsToggleProvider.notifier)
                      .setVisible(value),
                ),
              ],
            ),
            Text(
              'Ώρα   Τηλέφωνο   Καλών   Τμήμα   Κατάσταση',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            content,
          ],
        ),
      ),
    );
  }
}
