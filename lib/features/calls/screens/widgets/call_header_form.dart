import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../provider/call_entry_provider.dart';
import '../../provider/call_header_provider.dart';
import '../../provider/lookup_provider.dart';
import 'smart_entity_selector_widget.dart';

/// Ελάχιστο πλάτος γραμμής πεδίων ώστε να χωράει Τηλ. + Καλών. + Τμήμα + Εξοπλισμός + × + +.
/// Υπολογισμός: w1(120) + 12 + w2(220) + 12 + wDept(160) + 12 + w3(130) + 4 + 40 + 40 = 750.
const double kCallHeaderRowMinWidth = 790;

/// Header φόρμα εισαγωγής κλήσης: Τηλέφωνο, Καλούντας, Τμήμα, Κωδικός Εξοπλισμού.
class CallHeaderForm extends ConsumerStatefulWidget {
  const CallHeaderForm({super.key});

  @override
  ConsumerState<CallHeaderForm> createState() => _CallHeaderFormState();
}

class _CallHeaderFormState extends ConsumerState<CallHeaderForm> {
  final GlobalKey<SmartEntitySelectorWidgetState> _selectorKey =
      GlobalKey<SmartEntitySelectorWidgetState>();

  @override
  Widget build(BuildContext context) {
    final header = ref.watch(callHeaderProvider);
    final lookupAsync = ref.watch(lookupServiceProvider);
    final lookupService = lookupAsync.value;

    final hasAnyContent = ref.watch(
      callHeaderProvider.select((s) => s.hasAnyContent),
    );
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final mw = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        // Διαθέσιμο πλάτος μείον κενά και κουμπιά ×/+ ώστε η γραμμή να χωράει πάντα (όχι overflow).
        const gapsAndIcons = 12.0 + 12.0 + 12.0 + 4.0 + 40.0 + 40.0; // 120
        final available = (mw - gapsAndIcons).clamp(200.0, double.infinity);
        // Αναλογία 18:34:24:20 (άθροισμα 96%) ώστε το σύνολο να μην ξεπερνά το available.
        final w1 = (available * 0.18).clamp(0.0, 170.0);
        final w2 = (available * 0.34).clamp(0.0, 300.0);
        final wDept = (available * 0.24).clamp(0.0, 240.0);
        final w3 = (available * 0.20).clamp(0.0, 185.0);

        return SmartEntitySelectorWidget(
          key: _selectorKey,
          provider: callSmartEntityProvider,
          w1: w1,
          w2: w2,
          wDept: wDept,
          w3: w3,
          callEntryHooks: SmartEntityCallEntryHooks(
            syncTimerFromPhoneText: (raw) {
              final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
              final n = ref.read(callEntryProvider.notifier);
              if (digits.isNotEmpty) {
                n.startTimerOnce();
              } else {
                n.resetTimerToStandby();
              }
            },
            startTimerOnceIfNotRunningWhenAutofill: () {
              final n = ref.read(callEntryProvider.notifier);
              if (!n.isTimerRunning) {
                n.startTimerOnce();
              }
            },
            resetTimerToStandby: () =>
                ref.read(callEntryProvider.notifier).resetTimerToStandby(),
          ),
          trailingRowChildren: [
            const SizedBox(width: 4),
            IgnorePointer(
              ignoring: !hasAnyContent,
              child: AnimatedOpacity(
                opacity: hasAnyContent ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: AnimatedScale(
                  scale: hasAnyContent ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: IconButton(
                    icon: Icon(Icons.clear, color: theme.colorScheme.error),
                    tooltip: 'Καθαρισμός όλων των πεδίων',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    onPressed: () =>
                        _selectorKey.currentState?.performClearAllFields(),
                  ),
                ),
              ),
            ),
            if (header.needsAssociation)
              IconButton(
                icon: Icon(Icons.add, color: header.associationColor),
                tooltip: header.associationTooltip ?? '',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final currentHeader = ref.read(callHeaderProvider);
                  final caller = currentHeader.selectedCaller;
                  final departmentText = currentHeader.departmentText.trim();
                  final selectedDepartment = departmentText.isNotEmpty
                      ? lookupService?.findDepartmentByName(departmentText)
                      : null;
                  var updatePrimaryDepartment = false;

                  if (caller?.id != null &&
                      selectedDepartment?.id != null &&
                      selectedDepartment!.id != caller!.departmentId) {
                    final askUpdate = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) {
                        return AlertDialog(
                          title: const Text('Αλλαγή κύριου τμήματος'),
                          content: Text(
                            'Ο χρήστης έχει κύριο τμήμα "${caller.departmentName ?? 'Χωρίς τμήμα'}". '
                            'Να γίνει νέο κύριο τμήμα του χρήστη το "${selectedDepartment.name}";',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('Όχι'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: const Text('Ναι'),
                            ),
                          ],
                        );
                      },
                    );
                    updatePrimaryDepartment = askUpdate ?? false;
                  }

                  final notifier = ref.read(callHeaderProvider.notifier);
                  final msg = await notifier.associateCurrentIfNeeded(
                    updatePrimaryDepartment: updatePrimaryDepartment,
                  );
                  if (context.mounted && msg != null) {
                    messenger.showSnackBar(SnackBar(content: Text(msg)));
                  }
                },
              ),
          ],
        );
      },
    );
  }
}
