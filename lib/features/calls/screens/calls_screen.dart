import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/spell_check.dart';
import '../provider/call_entry_provider.dart';
import '../provider/call_header_provider.dart';
import 'widgets/call_header_form.dart';
import 'widgets/call_status_bar.dart';
import 'widgets/recent_calls_list.dart';
import 'widgets/sticky_note_widget.dart';
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
                if (header.selectedCaller != null) ...[
                  UserInfoCard(
                    user: header.selectedCaller!,
                    equipment: header.selectedEquipment,
                    equipmentCodeText: header.equipmentText,
                  ),
                  if (header.selectedCaller!.notes != null &&
                      header.selectedCaller!.notes!.trim().isNotEmpty)
                    StickyNoteWidget(notes: header.selectedCaller!.notes!),
                  RecentCallsList(userId: header.selectedCaller!.id!),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _NotesTextField(entry: entry),
                    ),
                    const SizedBox(width: 16),
                    const CallStatusBar(),
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
  final button = SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: header.canSubmitCall
          ? () async {
              final ok = await ref.read(callEntryProvider.notifier).submitCall(ref);
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
    ),
  );
  if (header.canSubmitCall) {
    return button;
  }
  return Tooltip(
    message: 'Συμπληρώστε εσωτερικό αριθμό και πρέπει να βρεθεί ο καλώντας',
    child: button,
  );
}

/// Πεδίο σημειώσεων με δικό του controller (εκτός state για αποφυγή διαρροής μνήμης).
class _NotesTextField extends ConsumerStatefulWidget {
  const _NotesTextField({required this.entry});

  final CallEntryState entry;

  @override
  ConsumerState<_NotesTextField> createState() => _NotesTextFieldState();
}

class _NotesTextFieldState extends ConsumerState<_NotesTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.entry.notes);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(callEntryProvider);
    if (entry.notes.isEmpty && _controller.text.isNotEmpty) {
      _controller.text = '';
    }
    return TextField(
      controller: _controller,
      decoration: const InputDecoration(
        labelText: 'Σημειώσεις',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      maxLines: 3,
      spellCheckConfiguration: platformSpellCheckConfiguration,
      onChanged: (value) =>
          ref.read(callEntryProvider.notifier).setNotes(value),
    );
  }
}
