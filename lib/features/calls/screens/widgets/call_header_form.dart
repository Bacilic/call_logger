import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../provider/call_entry_provider.dart';
import '../../provider/call_header_provider.dart';
import '../../provider/lookup_provider.dart';
import '../../../../core/utils/search_text_normalizer.dart';
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
    final lookupBundle = lookupAsync.value;
    final lookupService = lookupBundle?.service;
    final lookupLoadError = lookupBundle?.loadError;
    final lookupLoadErrorDetails = lookupBundle?.loadErrorDetails;

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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lookupLoadError != null && lookupLoadError.isNotEmpty)
              Material(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _lookupErrorLeadText(
                              context,
                              lookupLoadError,
                              lookupLoadErrorDetails,
                            ),
                            if (lookupLoadErrorDetails != null &&
                                lookupLoadErrorDetails.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              SelectableText(
                                lookupLoadErrorDetails,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(lookupServiceProvider),
                        child: const Text('Επαναδοκιμή'),
                      ),
                    ],
                  ),
                ),
              ),
            SmartEntitySelectorWidget(
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
                if (header.needsAssociation(lookupService))
                  IconButton(
                    icon: Icon(Icons.add, color: header.associationColor(lookupService)),
                    tooltip: header.associationTooltip(lookupService) ?? '',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final currentHeader = ref.read(callHeaderProvider);
                      final notifier = ref.read(callHeaderProvider.notifier);

                      if (currentHeader.needsOrphanDepartmentQuickAdd) {
                        final preview = await notifier.quickAddOrphanToDepartment();
                        if (preview == null) return;
                        if (preview.requiresConfirmation) {
                          if (!context.mounted) return;
                          final approve = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) {
                              return AlertDialog(
                                title: const Text('Σύγκρουση δεδομένων'),
                                content: Text(preview.message),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('Ακύρωση'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('Ναι, Προσθήκη'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (approve != true) return;
                          final applied = await notifier.quickAddOrphanToDepartment(
                            forceSharedOnConflict: true,
                          );
                          if (context.mounted && applied?.successMessage != null) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(applied!.successMessage!)),
                            );
                          }
                          return;
                        }
                        if (context.mounted && preview.successMessage != null) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(preview.successMessage!)),
                          );
                        }
                        return;
                      }

                      final caller = currentHeader.selectedCaller;
                      final departmentText = currentHeader.departmentText
                          .trim();
                      final selectedDepartment = departmentText.isNotEmpty
                          ? lookupService?.findDepartmentByName(departmentText)
                          : null;
                      var updatePrimaryDepartment = false;

                      final oldDeptText = (caller?.departmentName ?? '')
                          .trim();
                      final nextDeptNorm =
                          SearchTextNormalizer.normalizeForSearch(departmentText);
                      final oldDeptNorm =
                          SearchTextNormalizer.normalizeForSearch(oldDeptText);
                      final wantsDeptChange = caller?.id != null &&
                          departmentText.isNotEmpty &&
                          (selectedDepartment?.id != caller?.departmentId) &&
                          (nextDeptNorm.isNotEmpty && nextDeptNorm != oldDeptNorm);

                      if (wantsDeptChange) {
                        final askUpdate = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) {
                            return AlertDialog(
                              title: const Text('Αλλαγή κύριου τμήματος'),
                              content: Text(
                                'Ο χρήστης έχει κύριο τμήμα "${caller!.departmentName ?? 'Χωρίς τμήμα'}". '
                                'Να γίνει νέο κύριο τμήμα του χρήστη το "${selectedDepartment?.name ?? departmentText}";',
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

                      final msg = await notifier.associateCurrentIfNeeded(
                        updatePrimaryDepartment: updatePrimaryDepartment,
                      );
                      if (context.mounted && msg != null) {
                        messenger.showSnackBar(SnackBar(content: Text(msg)));
                      }
                    },
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Κείμενο σφάλματος· στη λέξη «λεπτομέρειες» εμφανίζεται tooltip με τεχνικές λεπτομέρειες.
  Widget _lookupErrorLeadText(
    BuildContext context,
    String message,
    String? details,
  ) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onErrorContainer,
    );
    const key = 'λεπτομέρειες';
    final i = message.indexOf(key);
    if (details == null || details.isEmpty || i < 0) {
      return Text(message, style: style);
    }
    final before = message.substring(0, i);
    final after = message.substring(i + key.length);
    final tip =
        details.length > 2500 ? '${details.substring(0, 2500)}…' : details;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: before),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Tooltip(
              message: tip,
              textStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onInverseSurface,
              ),
              child: Text(
                key,
                style: style?.copyWith(
                  decoration: TextDecoration.underline,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}
