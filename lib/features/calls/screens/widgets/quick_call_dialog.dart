import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/call_save_exception.dart';
import '../../../../core/errors/task_save_exception.dart';
import '../../../../core/models/remote_tool.dart';
import '../../../../core/widgets/dialog_outside_tap_hint.dart';
import '../../layout/calls_field_groups_provider.dart';
import '../../provider/call_entry_provider.dart';
import '../../provider/call_header_provider.dart';
import '../../provider/remote_paths_provider.dart';
import '../../utils/call_remote_targets.dart';
import 'call_status_bar.dart';
import 'category_autocomplete_field.dart';
import 'notes_sticky_field.dart';
import 'remote_connection_buttons.dart';
import 'smart_entity_selector_widget.dart';

/// Εμφανίζει modal διάλογο γρήγορης καταγραφής με ανεξάρτητο provider scope.
Future<void> showQuickCallDialog(BuildContext context) {
  return showDialogWithOutsideTapHint<void>(
    context: context,
    builder: (dialogContext) => ProviderScope(
      overrides: [
        callSmartEntityProvider.overrideWith(SmartEntitySelectorNotifier.new),
        callEntryProvider.overrideWith(CallEntryNotifier.new),
        callsFieldConfirmationsProvider.overrideWith(
          CallsFieldConfirmationsNotifier.new,
        ),
        callsScreenExpandedLatchProvider.overrideWith(
          CallsScreenExpandedLatchNotifier.new,
        ),
      ],
      child: const QuickCallDialog(),
    ),
  );
}

/// Modal γρήγορης καταγραφής — ξεχωριστό scope, χωρίς επαφή με την κύρια φόρμα.
class QuickCallDialog extends ConsumerStatefulWidget {
  const QuickCallDialog({super.key});

  @override
  ConsumerState<QuickCallDialog> createState() => _QuickCallDialogState();
}

class _QuickCallDialogState extends ConsumerState<QuickCallDialog> {
  final GlobalKey<SmartEntitySelectorWidgetState> _selectorKey =
      GlobalKey<SmartEntitySelectorWidgetState>();

  static const double _kDialogMaxWidth = 920;
  static const double _kFieldGap = 12;
  static const double _kPhoneRatio = 0.18;
  static const double _kCallerRatio = 0.34;
  static const double _kDeptRatio = 0.24;
  static const double _kEquipmentRatio = 0.20;
  static const double _kRatioSum =
      _kPhoneRatio + _kCallerRatio + _kDeptRatio + _kEquipmentRatio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectorKey.currentState?.requestPhoneFocus();
    });
  }

  ({double w1, double w2, double wDept, double w3}) _fieldWidths(double total) {
    final usable = math.max(480.0, total - _kFieldGap * 3);
    return (
      w1: usable * (_kPhoneRatio / _kRatioSum),
      w2: usable * (_kCallerRatio / _kRatioSum),
      wDept: usable * (_kDeptRatio / _kRatioSum),
      w3: usable * (_kEquipmentRatio / _kRatioSum),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final notifier = ref.read(callEntryProvider.notifier);
    try {
      final ok = await notifier.submitCall();
      if (!context.mounted) return;
      if (ok) {
        Navigator.of(context).pop();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Κλήση αποθηκεύτηκε (γρήγορη καταγραφή)'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Αποτυχία αποθήκευσης')),
        );
      }
    } on CallSaveException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on TaskSaveException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = ref.watch(callHeaderProvider);
    final tools = ref.watch(remoteToolsCatalogProvider).value ?? <RemoteTool>[];
    final allToolsAsync = ref.watch(remoteToolsAllCatalogProvider);
    final hideRemoteButtons = allToolsAsync.maybeWhen(
      data: (all) => CallRemoteTargets.shouldHideRemoteConnectionButtons(
        header.selectedEquipment,
        all,
      ),
      orElse: () => false,
    );
    final showRemoteButtons =
        !hideRemoteButtons &&
        (header.equipmentText.trim().isNotEmpty ||
            header.selectedEquipment != null);
    final isSubmitting = ref.watch(
      callEntryProvider.select((s) => s.isSubmitting),
    );
    final theme = Theme.of(context);

    return Dialog(
      key: const ValueKey('quick_call_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kDialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.flash_on, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Γρήγορη καταγραφή κλήσης',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Κλείσιμο',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final widths = _fieldWidths(constraints.maxWidth);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SmartEntitySelectorWidget(
                            key: _selectorKey,
                            provider: callSmartEntityProvider,
                            w1: widths.w1,
                            w2: widths.w2,
                            wDept: widths.wDept,
                            w3: widths.w3,
                            callEntryHooks: SmartEntityCallEntryHooks(
                              syncTimerFromPhoneText: (raw) {
                                final digits = raw.replaceAll(
                                  RegExp(r'[^0-9]'),
                                  '',
                                );
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
                              resetTimerToStandby: () => ref
                                  .read(callEntryProvider.notifier)
                                  .resetTimerToStandby(),
                            ),
                            trailingRowChildren: const [],
                          ),
                        ),
                        if (showRemoteButtons) ...[
                          const SizedBox(height: 12),
                          RemoteConnectionButtons(header: header, tools: tools),
                        ],
                        const SizedBox(height: 12),
                        const NotesStickyField(),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, rowConstraints) {
                            final categoryField = CategoryAutocompleteField(
                              onCategoryChanged: (text, categoryId) {
                                ref
                                    .read(callEntryProvider.notifier)
                                    .setCategory(
                                      text,
                                      categoryId: categoryId,
                                    );
                              },
                            );
                            final submitButton = _SubmitButton(
                              header: header,
                              isSubmitting: isSubmitting,
                              onSubmit: () => _submit(context),
                            );
                            if (rowConstraints.maxWidth < 520) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const CallStatusBar(
                                    axis: CallStatusBarAxis.horizontal,
                                  ),
                                  const SizedBox(height: 8),
                                  categoryField,
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: submitButton,
                                  ),
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const CallStatusBar(
                                  axis: CallStatusBarAxis.horizontal,
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: categoryField),
                                const SizedBox(width: 8),
                                submitButton,
                              ],
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.header,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final CallHeaderState header;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSubmit = header.canSubmitCall && !isSubmitting;
    final button = ElevatedButton.icon(
      onPressed: canSubmit ? onSubmit : null,
      style: canSubmit
          ? ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              backgroundColor: scheme.primary,
              foregroundColor: Colors.white,
            )
          : ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            ),
      icon: isSubmitting
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onPrimary,
              ),
            )
          : const Icon(Icons.save_alt),
      label: const Text('Καταγραφή'),
    );
    return canSubmit
        ? button
        : Tooltip(
            message:
                'Συμπληρώστε τουλάχιστον ένα τηλέφωνο ή έναν καλούντα και περιγραφή θέματος',
            child: button,
          );
  }
}
