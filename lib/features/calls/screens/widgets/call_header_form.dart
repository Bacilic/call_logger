import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../provider/call_entry_provider.dart';
import '../../layout/calls_field_groups.dart';
import '../../provider/call_header_provider.dart';
import '../../provider/lookup_provider.dart';
import '../../../../core/providers/call_department_prefill_intent_provider.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/utils/user_homonym_finder.dart';
import '../../../directory/screens/widgets/homonym_warning_dialog.dart';
import 'smart_entity_selector_widget.dart';

/// Ελάχιστο πλάτος γραμμής πεδίων ώστε να χωράει Τηλ. + Καλών. + Τμήμα + Εξοπλισμός + κενά + ×.
/// Πεδία ~120+220+160+150 + 3×12 (κενά) + 4 (πριν trailing) + 40 (κουμπί καθαρισμού) ≈ 750.
const double kCallHeaderRowMinWidth = 790;

/// Κενό μεταξύ πεδίων στη γραμμή [SmartEntitySelectorWidget].
const double _kHeaderFieldGap = 12.0;

/// Κενό πριν τα trailing στοιχεία + ελάχιστο πλάτος κουμπιού «Καθαρισμός όλων».
const double _kHeaderTrailingGap = 4.0;
const double _kHeaderClearAllButtonWidth = 48.0;

/// Χώρος εκτός πεδίων στην ίδια Row: 3 κενά, trailing gap, κουμπί ×.
const double _kHeaderGapsAndIcons =
    _kHeaderFieldGap * 3 +
    _kHeaderTrailingGap +
    _kHeaderClearAllButtonWidth;

/// Αναλογίες πλάτους πεδίων (άθροισμα 96· κανονικοποιούνται στο 1.0).
const double _kHeaderWidthRatioPhone = 0.18;
const double _kHeaderWidthRatioCaller = 0.34;
const double _kHeaderWidthRatioDept = 0.24;
const double _kHeaderWidthRatioEquipment = 0.20;
const double _kHeaderWidthRatioSum =
    _kHeaderWidthRatioPhone +
    _kHeaderWidthRatioCaller +
    _kHeaderWidthRatioDept +
    _kHeaderWidthRatioEquipment;

/// Header φόρμα εισαγωγής κλήσης: Τηλέφωνο, Καλούντας, Τμήμα, Κωδικός Εξοπλισμού.
class CallHeaderForm extends ConsumerStatefulWidget {
  const CallHeaderForm({super.key, this.compactFieldCentering = false});

  /// Συμπτυγμένη όψη: κάθετο κέντρο της γραμμής πεδίων (όχι ολόκληρου μπλοκ με κενό τίτλο).
  final bool compactFieldCentering;

  @override
  ConsumerState<CallHeaderForm> createState() => _CallHeaderFormState();
}

class _CallHeaderFormState extends ConsumerState<CallHeaderForm> {
  final GlobalKey<SmartEntitySelectorWidgetState> _selectorKey =
      GlobalKey<SmartEntitySelectorWidgetState>();

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(callDepartmentPrefillIntentProvider, (previous, next) {
      if (next == null || next.trim().isEmpty) return;
      ref.read(callDepartmentPrefillIntentProvider.notifier).clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final lookup = ref.read(lookupServiceProvider).value?.service;
        final dept = lookup?.findDepartmentByName(next.trim());
        final notifier = ref.read(callHeaderProvider.notifier);
        if (dept != null) {
          notifier.selectDepartment(dept);
        } else {
          notifier.updateDepartmentText(next.trim());
        }
      });
    });

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

    Future<void> onAddAssociationPressed() async {
      final messenger = ScaffoldMessenger.of(context);
      final currentHeader = ref.read(callHeaderProvider);
      final notifier = ref.read(callHeaderProvider.notifier);
      if (currentHeader.needsOrphanDepartmentQuickAddResolved(lookupService)) {
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
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Ακύρωση'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
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
      final departmentText = currentHeader.departmentText.trim();
      final selectedDepartment = departmentText.isNotEmpty
          ? lookupService?.findDepartmentByName(departmentText)
          : null;
      var updatePrimaryDepartment = false;

      final oldDeptText = (caller?.departmentName ?? '').trim();
      final nextDeptNorm = SearchTextNormalizer.normalizeForSearch(
        departmentText,
      );
      final oldDeptNorm = SearchTextNormalizer.normalizeForSearch(oldDeptText);
      final wantsDeptChange =
          caller?.id != null &&
          departmentText.isNotEmpty &&
          (nextDeptNorm.isNotEmpty && nextDeptNorm != oldDeptNorm) &&
          (selectedDepartment?.id != caller?.departmentId ||
              (caller?.departmentId == null && selectedDepartment == null));

      if (wantsDeptChange) {
        if (oldDeptText.isEmpty) {
          updatePrimaryDepartment = true;
        } else {
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
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Όχι'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Ναι'),
                ),
              ],
            );
          },
        );
        updatePrimaryDepartment = askUpdate ?? false;
        }
      }

      if (currentHeader.needsNewCallerCreation && lookupService != null) {
        final homonym = UserHomonymFinder.findHomonymFromCallerText(
          users: lookupService.users,
          callerDisplayText: currentHeader.normalizedCallerDisplayText,
        );
        if (homonym != null) {
          if (!context.mounted) return;
          final parsed = UserHomonymFinder.parseCallerText(
            currentHeader.normalizedCallerDisplayText,
          );
          final displayName = UserHomonymFinder.displayNameFor(
            parsed.firstName,
            parsed.lastName,
          );
          final choice = await showDialog<bool>(
            context: context,
            barrierDismissible: true,
            builder: (dialogContext) => HomonymWarningDialog(
              userDisplayName: displayName,
              existingRecordDepartmentName:
                  homonym.departmentName?.trim() ?? '',
            ),
          );
          if (choice != true) return;
        }
      }

      final msg = await notifier.associateCurrentIfNeeded(
        updatePrimaryDepartment: updatePrimaryDepartment,
      );
      if (context.mounted && msg != null) {
        messenger.showSnackBar(SnackBar(content: Text(msg)));
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final mw = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        // Διαθέσιμο πλάτος μείον κενά και κουμπί × — το άθροισμα πεδίων + _kHeaderGapsAndIcons ≤ mw.
        final available = (mw - _kHeaderGapsAndIcons).clamp(0.0, double.infinity);
        var w1 = available * _kHeaderWidthRatioPhone / _kHeaderWidthRatioSum;
        var w2 = available * _kHeaderWidthRatioCaller / _kHeaderWidthRatioSum;
        var wDept = available * _kHeaderWidthRatioDept / _kHeaderWidthRatioSum;
        var w3 = available * _kHeaderWidthRatioEquipment / _kHeaderWidthRatioSum;
        // Ασφάλεια αριθμητικής ακρίβειας: ποτέ overflow στη Row (υπολογισμός υπολοίπου στο τελευταίο πεδίο).
        final fieldsSum = w1 + w2 + wDept + w3;
        if (fieldsSum > available && fieldsSum > 0) {
          final scale = available / fieldsSum;
          w1 *= scale;
          w2 *= scale;
          wDept *= scale;
          w3 *= scale;
        }
        w3 = (available - w1 - w2 - wDept).clamp(0.0, double.infinity);
        final equipmentColumnOffset =
            w1 + _kHeaderFieldGap + w2 + _kHeaderFieldGap + wDept + _kHeaderFieldGap;
        final titleText = CallsScreenTitleResolver.resolve(header);
        final showTitleRow = !widget.compactFieldCentering ||
            titleText.isNotEmpty ||
            header.needsAssociation(lookupService);

        final formCore = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTitleRow) ...[
              SizedBox(
                height: 34,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        titleText,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (header.needsAssociation(lookupService))
                      Positioned(
                        left: equipmentColumnOffset,
                        width: w3,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Tooltip(
                            message:
                                header.associationTooltip(lookupService) ?? '',
                            child: TextButton(
                              onPressed: onAddAssociationPressed,
                              style: TextButton.styleFrom(
                                foregroundColor: header.associationColor(
                                  lookupService,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                'Προσθήκη',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: header.associationColor(lookupService),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
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
                const SizedBox(width: _kHeaderTrailingGap),
                SizedBox(
                  width: _kHeaderClearAllButtonWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                    // Αόρατος placeholder ίδιου ύψους με τη γραμμή ετικέτας (label)
                    // των πεδίων, ώστε το κόκκινο × να κατέβει στο κέντρο του
                    // TextField και να ευθυγραμμιστεί με τα × των πεδίων.
                    // Κείμενο = ένα κενό: κρατά το ύψος γραμμής χωρίς να αυξάνει
                    // το πλάτος (αλλιώς προκαλείται overflow στη Row).
                    Opacity(
                      opacity: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(Icons.circle, size: 16),
                          Text(' ', style: theme.textTheme.labelMedium),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    IgnorePointer(
                      ignoring: !hasAnyContent,
                      child: AnimatedOpacity(
                        opacity: hasAnyContent ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: AnimatedScale(
                          scale: hasAnyContent ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          child: IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: theme.colorScheme.error,
                            ),
                            tooltip: 'Καθαρισμός όλων των πεδίων',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            onPressed: () => _selectorKey.currentState
                                ?.performClearAllFields(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ],
            ),
          ],
        );

        if (widget.compactFieldCentering) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              formCore,
              const Spacer(),
            ],
          );
        }

        return formCore;
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
    final tip = details.length > 2500
        ? '${details.substring(0, 2500)}…'
        : details;
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
