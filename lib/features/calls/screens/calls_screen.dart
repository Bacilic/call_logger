import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../provider/call_entry_provider.dart';
import '../provider/lookup_provider.dart';
import 'widgets/recent_calls_list.dart';
import 'widgets/sticky_note_widget.dart';
import 'widgets/user_info_card.dart';

/// Οθόνη εισαγωγής κλήσης: Εσωτερικό, lookup 3 ψηφία, κάρτα χρήστη, ιστορικό, sticky note, σημειώσεις, Enter = αποθήκευση + focus πίσω.
class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(callEntryProvider);
    final lookupAsync = ref.watch(lookupServiceProvider);
    final lookupService = lookupAsync.value;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: entry.internalController,
                  focusNode: entry.internalFocusNode,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Εσωτερικό',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => ref
                      .read(callEntryProvider.notifier)
                      .setInternalDigits(value, lookupService),
                ),
              ),
            ],
          ),
          if (entry.selectedUser != null) ...[
            UserInfoCard(
              user: entry.selectedUser!,
              equipment: entry.selectedEquipment,
            ),
            if (entry.selectedUser!.notes != null &&
                entry.selectedUser!.notes!.trim().isNotEmpty)
              StickyNoteWidget(notes: entry.selectedUser!.notes!),
            RecentCallsList(userId: entry.selectedUser!.id!),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: entry.notesController,
            decoration: const InputDecoration(
              labelText: 'Σημειώσεις',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 4,
            onChanged: (value) =>
                ref.read(callEntryProvider.notifier).setNotes(value),
            onSubmitted: (_) async {
              final ok = await ref.read(callEntryProvider.notifier).submitCall();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Κλήση αποθηκεύτηκε' : 'Αποτυχία αποθήκευσης',
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
