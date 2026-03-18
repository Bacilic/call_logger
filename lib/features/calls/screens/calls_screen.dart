import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../provider/call_entry_provider.dart';
import '../provider/call_header_provider.dart';
import 'widgets/call_header_form.dart';
import 'widgets/call_status_bar.dart';
import 'widgets/recent_calls_list.dart';
import 'widgets/equipment_info_card.dart';
import 'widgets/notes_sticky_field.dart';
import 'widgets/remote_connection_buttons.dart';
import 'widgets/user_info_card.dart';

/// Οθόνη εισαγωγής κλήσης: Εσωτερικό, lookup 3 ψηφία, κάρτα χρήστη, ιστορικό, sticky note, σημειώσεις, Enter = αποθήκευση + focus πίσω.
/// Το focus από shortcut (Quick Capture / Ctrl+Alt+L) γίνεται μέσω root Shortcuts/Actions σε microtask,
/// ώστε να μην συμπέσει με autofocus ή rebuild (βλ. docs/KEYBOARD_AND_FOCUS.md).
class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(callEntryProvider);
    final header = ref.watch(callHeaderProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          return SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CallHeaderForm(),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Wrap(
                    spacing: 16.0,
                    runSpacing: 16.0,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: [
                      if (header.selectedCaller != null)
                        UserInfoCard(user: header.selectedCaller!),
                      if (header.selectedEquipment != null ||
                          header.equipmentText.trim().isNotEmpty)
                        EquipmentInfoCard(
                          equipment: header.selectedEquipment,
                          equipmentCodeText: header.equipmentText,
                        ),
                      if (header.equipmentText.trim().isNotEmpty ||
                          header.selectedEquipment != null)
                        RemoteConnectionButtons(
                          equipment: header.selectedEquipment,
                          equipmentCodeText:
                              header.equipmentText.isNotEmpty
                                  ? header.equipmentText
                                  : (header.selectedEquipment?.code ?? ''),
                        ),
                    ],
                  ),
                ),
                if (header.selectedCaller != null) ...[
                  RecentCallsList(userId: header.selectedCaller!.id!),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: NotesStickyField(entry: entry),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      fit: FlexFit.loose,
                      child: CallStatusBar(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSubmitButton(context, ref, header),
              ],
            ),
          );
        },
      ),
    );
  }
}

Widget _buildSubmitButton(
  BuildContext context,
  WidgetRef ref,
  CallHeaderState header,
) {
  final isPending = ref.watch(callEntryProvider).isPending;
  final elevated = ElevatedButton(
    onPressed: header.canSubmitCall
        ? () async {
            final ok =
                await ref.read(callEntryProvider.notifier).submitCall(ref);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok ? 'Κλήση αποθηκεύτηκε' : 'Αποτυχία αποθήκευσης',
                  ),
                ),
              );
              ref.read(callHeaderProvider.notifier).requestPhoneFocus();
            }
          }
        : null,
    style: ElevatedButton.styleFrom(
      backgroundColor: header.canSubmitCall
          ? Theme.of(context).colorScheme.primary
          : Colors.grey,
      foregroundColor: header.canSubmitCall
          ? Theme.of(context).colorScheme.onPrimary
          : Colors.grey[700],
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      minimumSize: const Size(double.infinity, 48),
    ),
    child: const Text('Καταγραφή Κλήσης'),
  );
  final mainSubmit = header.canSubmitCall
      ? elevated
      : Tooltip(
          message:
              'Συμπληρώστε εσωτερικό αριθμό και πρέπει να βρεθεί ο καλώντας',
          child: elevated,
        );

  final pendingBtn = OutlinedButton.icon(
    icon: const Icon(Icons.task_alt),
    label: const Text('Εκκρεμότητα'),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    ),
    onPressed: () async {
      final ok =
          await ref.read(callEntryProvider.notifier).submitOnlyPending(ref);
      if (context.mounted && ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Η εκκρεμότητα καταχωρήθηκε'),
          ),
        );
      }
    },
  );

  return LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 520 && isPending;
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            mainSubmit,
            const SizedBox(height: 12),
            pendingBtn,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: mainSubmit),
          if (isPending) ...[
            const SizedBox(width: 16),
            Flexible(
              fit: FlexFit.loose,
              child: pendingBtn,
            ),
          ],
        ],
      );
    },
  );
}
