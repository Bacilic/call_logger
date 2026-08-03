// Ο διάλογος απόφασης για ΕΝΑ στοιχείο: παραμονή, μεταφορά ή διαγραφή — μαζί
// με τις δύο επιβεβαιώσεις που μπορεί να ακολουθήσουν (κατάργηση, ακύρωση όλων).
//
// Ο βρόχος επιστρέφει στον διάλογο όποτε ο χρήστης υπαναχωρήσει σε ενδιάμεσο
// βήμα, ώστε μια ακυρωμένη μεταφορά να μη μετράει ως απόφαση.

import 'package:flutter/material.dart';

import '../../../../core/widgets/compact_tooltip.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../models/department_model.dart';
import '../../services/asset_disconnect_link_probe.dart';
import '../../services/asset_disconnect_models.dart';
import '../../services/asset_disconnect_session.dart';
import '../../services/asset_disconnect_texts.dart';
import 'asset_disconnect_action_section.dart';
import 'asset_disconnect_quick_actions.dart';
import 'asset_transfer_target_dialog.dart';

/// Έκβαση ενός βήματος: απάντηση για το στοιχείο ή νέα καθολική απόφαση.
class AssetDisconnectItemResolution {
  const AssetDisconnectItemResolution.item(this.result) : standing = null;
  const AssetDisconnectItemResolution.standing(this.standing) : result = null;

  final SharedAssetDisconnectItemResult? result;
  final AssetDisconnectStandingDecision? standing;
}

/// Απάντηση του κύριου διαλόγου: μεμονωμένη επιλογή ή πρόθεση γρήγορης επιλογής.
class _DisconnectDialogAnswer {
  const _DisconnectDialogAnswer.single(this.choice) : quick = null;
  const _DisconnectDialogAnswer.quick(this.quick) : choice = null;

  final SharedAssetDisconnectChoice? choice;
  final AssetDisconnectQuickActionIntent? quick;
}

/// Ρωτά για ένα στοιχείο μέχρι να προκύψει απόφαση. Επιστρέφει null όταν ο
/// χρήστης ακυρώσει ολόκληρη τη ροή.
Future<AssetDisconnectItemResolution?> resolveAssetDisconnectItem({
  required BuildContext context,
  required AssetDisconnectItem item,
  int? sourceDepartmentId,
  String? sourceDepartmentName,
  required List<DepartmentModel> availableDepartments,
  List<String> blockedDepartmentNames = const [],
  required SharedAssetDisconnectMode mode,
  String? personalPhoneUserDisplayName,
  required bool canKeepInDepartment,
  required AssetDisconnectSession session,
  AssetReferenceDescriptionsLookup? referenceLookup,
  AssetHistoryLinksLookup? historyLookup,
}) async {
  final isPhone = item.isPhone;

  while (true) {
    if (!context.mounted) return null;
    final answer = await showDialog<_DisconnectDialogAnswer>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialogShell(
        title: Text(disconnectDialogTitle(isPhone: isPhone, mode: mode)),
        builder: (titleHandle) => AlertDialog(
          title: _DisconnectDialogTitleRow(
            titleHandle: titleHandle,
            session: session,
          ),
          // Όλες οι ενέργειες ζουν στο σώμα, σε δύο ονομασμένες ενότητες:
          // «για αυτό το στοιχείο» και «για όλα». Στη γραμμή κουμπιών μένει
          // μόνο η Ακύρωση, ώστε να μη συγχέεται το ατομικό με το καθολικό.
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    disconnectDialogContent(
                      isPhone: isPhone,
                      value: item.value,
                      mode: mode,
                      sourceDepartmentName: sourceDepartmentName,
                      personalPhoneUserDisplayName:
                          personalPhoneUserDisplayName,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AssetDisconnectActionSection(
                    header: assetDisconnectSingleActionsHeader(
                      isPhone: isPhone,
                    ),
                    tinted: false,
                    actions: [
                      if (canKeepInDepartment)
                        AssetDisconnectActionEntry(
                          icon: Icons.check_circle_outline,
                          label: keepInDepartmentLabel(
                            mode,
                            sourceDepartmentName: sourceDepartmentName,
                          ),
                          tooltip: keepInDepartmentTooltip(
                            mode,
                            sourceDepartmentName: sourceDepartmentName,
                          ),
                          onTap: () => Navigator.of(ctx).pop(
                            const _DisconnectDialogAnswer.single(
                              SharedAssetDisconnectChoice.keepInDepartment,
                            ),
                          ),
                        ),
                      AssetDisconnectActionEntry(
                        icon: Icons.drive_file_move_outlined,
                        label: 'Μεταφορά σε άλλο τμήμα',
                        tooltip: transferSingleTooltip(),
                        onTap: () => Navigator.of(ctx).pop(
                          const _DisconnectDialogAnswer.single(
                            SharedAssetDisconnectChoice.transfer,
                          ),
                        ),
                      ),
                      AssetDisconnectActionEntry(
                        icon: Icons.delete_outline,
                        label: 'Διαγραφή',
                        danger: true,
                        tooltip: deleteSingleTooltip(isPhone: isPhone),
                        onTap: () => Navigator.of(ctx).pop(
                          const _DisconnectDialogAnswer.single(
                            SharedAssetDisconnectChoice.delete,
                          ),
                        ),
                      ),
                    ],
                  ),
                  AssetDisconnectQuickActionsSection(
                    session: session,
                    canKeepInDepartment: canKeepInDepartment,
                    onIntent: (intent) => Navigator.of(
                      ctx,
                    ).pop(_DisconnectDialogAnswer.quick(intent)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Ακύρωση'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return null;

    if (answer == null) {
      if (!session.needsCancelConfirmation) return null;
      final stop = await _confirmStop(context: context, session: session);
      if (!context.mounted) return null;
      if (stop == null) continue;
      session.markStop(stop);
      return null;
    }

    final intent = answer.quick;
    if (intent != null) {
      final standing = await resolveAssetDisconnectQuickAction(
        context: context,
        intent: intent,
        session: session,
        availableDepartments: availableDepartments,
        blockedDepartmentNames: blockedDepartmentNames,
        historyLookup: historyLookup,
      );
      if (!context.mounted) return null;
      if (standing == null) continue;
      return AssetDisconnectItemResolution.standing(standing);
    }

    switch (answer.choice!) {
      case SharedAssetDisconnectChoice.keepInDepartment:
        return const AssetDisconnectItemResolution.item(
          SharedAssetDisconnectItemResult.keep(),
        );
      case SharedAssetDisconnectChoice.transfer:
        final target = await showAssetTransferDialogForItem(
          context: context,
          isPhone: isPhone,
          value: item.value,
          sourceDepartmentId: sourceDepartmentId,
          availableDepartments: availableDepartments,
          blockedDepartmentNames: blockedDepartmentNames,
        );
        if (!context.mounted) return null;
        if (target == null) continue;
        return AssetDisconnectItemResolution.item(
          SharedAssetDisconnectItemResult.transfer(target),
        );
      case SharedAssetDisconnectChoice.delete:
        final confirmed = await _confirmDelete(
          context: context,
          isPhone: isPhone,
          value: item.value,
          referenceLookup: referenceLookup,
        );
        if (!context.mounted) return null;
        if (confirmed != true) continue;
        return const AssetDisconnectItemResolution.item(
          SharedAssetDisconnectItemResult.delete(),
        );
    }
  }
}

/// Ένδειξη «Βήμα 6 από 24» δίπλα στον τίτλο (μόνο όταν τα βήματα είναι >1).
class _DisconnectDialogTitleRow extends StatelessWidget {
  const _DisconnectDialogTitleRow({
    required this.titleHandle,
    required this.session,
  });

  final Widget titleHandle;
  final AssetDisconnectSession session;

  @override
  Widget build(BuildContext context) {
    if (!session.showsStepCounter) return titleHandle;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: titleHandle),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            assetDisconnectStepLabel(
              currentStep: session.currentStep,
              totalSteps: session.totalSteps,
              contextLabel: session.contextLabel,
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      ],
    );
  }
}

/// Επιβεβαίωση κατάργησης, με τις συνδέσεις που κρατούν το στοιχείο.
///
/// Μετακινείται από τον τίτλο ώστε να φαίνονται τα δεδομένα από πίσω.
Future<bool?> _confirmDelete({
  required BuildContext context,
  required bool isPhone,
  required String value,
  AssetReferenceDescriptionsLookup? referenceLookup,
}) async {
  final probe = referenceLookup ?? assetReferenceDescriptions;
  final descriptions = await probe(isPhone: isPhone, value: value);

  if (!context.mounted) return null;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialogShell(
      title: Text(isPhone ? 'Διαγραφή τηλεφώνου' : 'Διαγραφή εξοπλισμού'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: Text(
          formatAssetReferenceDeleteMessage(
            isPhone: isPhone,
            value: value,
            descriptions: descriptions,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Όχι'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ναι, κατάργηση'),
          ),
        ],
      ),
    ),
  );
}

/// Επιβεβαίωση εγκατάλειψης της ροής. `null` = ο χρήστης συνεχίζει.
///
/// Με δουλειά που μπορεί να κρατηθεί εμφανίζεται **τρίτη έξοδος**: έτσι η
/// απόφαση παίρνεται σε έναν διάλογο αντί για δύο διαδοχικούς, και το κείμενο
/// δεν υπόσχεται απώλεια που δεν θα συμβεί.
Future<AssetDisconnectStopKind?> _confirmStop({
  required BuildContext context,
  required AssetDisconnectSession session,
}) {
  final completed = session.completedWork?.call();

  return showDialog<AssetDisconnectStopKind>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(completed == null ? 'Ακύρωση όλων;' : 'Διακοπή διαδικασίας;'),
      content: Text(
        completed == null
            ? assetDisconnectCancelMessage(
                resolvedSteps: session.resolvedSteps,
                cancelScopeDescription: session.cancelScopeDescription,
              )
            : completed.summary,
      ),
      // Τι κάνει κάθε κουμπί ζει στην υπόδειξή του: λίστα επεξηγήσεων μέσα στο
      // σώμα φούσκωνε τον διάλογο σε όλο το πλάτος της οθόνης.
      actions: [
        CompactTooltip(
          message: assetDisconnectContinueHint,
          child: TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Συνέχεια'),
          ),
        ),
        if (completed != null)
          CompactTooltip(
            message: completed.applyHint,
            child: TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(AssetDisconnectStopKind.applyCompleted),
              child: const Text('Εφαρμογή απαντήσεων'),
            ),
          ),
        CompactTooltip(
          message: assetDisconnectCancelAllHint,
          child: FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(AssetDisconnectStopKind.cancelAll),
            child: const Text('Ακύρωση όλων'),
          ),
        ),
      ],
    ),
  );
}
