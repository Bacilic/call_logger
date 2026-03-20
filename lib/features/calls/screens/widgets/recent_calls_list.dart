import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../provider/call_entry_provider.dart';

/// Λίστα τελευταίων 3 κλήσεων για τον επιλεγμένο καλούντα (calls.caller_id).
class RecentCallsList extends ConsumerWidget {
  const RecentCallsList({super.key, required this.callerId});

  final int callerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCalls = ref.watch(recentCallsProvider(callerId));
    return asyncCalls.when(
      data: (calls) {
        if (calls.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Πρόσφατο ιστορικό',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ...calls.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.date ?? ''} ${c.time ?? ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            c.issue ?? '—',
                            style: theme.textTheme.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
