import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../provider/calls_dashboard_providers.dart';

class EquipmentRecentCallsPanel extends ConsumerWidget {
  const EquipmentRecentCallsPanel({super.key, required this.equipmentCode});

  final String equipmentCode;

  Color _statusColor(BuildContext context, String status) {
    final v = status.toLowerCase();
    if (v == 'pending') return Colors.orange.shade600;
    if (v == 'completed') return Colors.green.shade600;
    return Theme.of(context).colorScheme.outline;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = equipmentCode.trim();
    if (code.isEmpty) return const SizedBox.shrink();
    final asyncCalls = ref.watch(recentCallsByEquipmentProvider(code));
    return asyncCalls.when(
      data: (calls) {
        if (calls.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ιστορικό Εξοπλισμού', style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                for (final c in calls)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            c.time ?? '--:--',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            () {
                              final issueText = (c.issue ?? '').trim();
                              return issueText.isEmpty ? '—' : issueText;
                            }(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
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
            ),
          ),
        );
      },
      loading: () => const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
