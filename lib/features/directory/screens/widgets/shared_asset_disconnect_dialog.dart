import 'package:flutter/material.dart';

import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../models/department_model.dart';
import '../../services/asset_disconnect_link_probe.dart';
import '../../services/asset_disconnect_models.dart';
import '../../services/asset_disconnect_session.dart';

export '../../services/asset_disconnect_link_probe.dart'
    show AssetHistoryLinksLookup, AssetReferenceDescriptionsLookup;
export '../../services/asset_disconnect_models.dart';
export '../../services/asset_disconnect_session.dart';

/// Sentinel για επιλογή «δημιουργία νέου τμήματος» στο autocomplete.
const _kCreateDepartmentOptionPrefix = '';

bool _isCreateDepartmentOption(String option) =>
    option.startsWith(_kCreateDepartmentOptionPrefix);

String _createDepartmentOptionValue(String name) =>
    '$_kCreateDepartmentOptionPrefix$name';

String _departmentOptionLabel(String option) {
  if (_isCreateDepartmentOption(option)) {
    final name = option.substring(_kCreateDepartmentOptionPrefix.length);
    return 'Δημιουργία νέου τμήματος «$name»';
  }
  return option;
}

/// Ροή αποδέσμευσης κοινόχρηστων τηλεφώνων/εξοπλισμού από τμήμα
/// ή προσωπικών τηλεφώνων χρήστη (αφαίρεση από φόρμα χρήστη).
///
/// Αν ο καλών δώσει [session], ο μετρητής βημάτων και οι γρήγορες επιλογές
/// καλύπτουν ΟΛΗ την ενέργειά του (π.χ. «Βήμα 6 από 24» για δέκα υπαλλήλους).
/// Χωρίς αυτήν, η ροή κρατά δικό της λογαριασμό μόνο για τα δικά της στοιχεία.
Future<SharedAssetDisconnectBatchResult?> showSharedAssetDisconnectFlow({
  required BuildContext context,
  int? sourceDepartmentId,
  String? sourceDepartmentName,
  List<String> phones = const [],
  List<String> equipmentCodes = const [],
  required List<DepartmentModel> availableDepartments,
  SharedAssetDisconnectMode mode = SharedAssetDisconnectMode.sharedAsset,
  String? personalPhoneUserDisplayName,
  bool allowKeepInDepartment = true,
  AssetDisconnectSession? session,
  AssetReferenceDescriptionsLookup? referenceLookup,
  AssetHistoryLinksLookup? historyLookup,
}) async {
  if (phones.isEmpty && equipmentCodes.isEmpty) {
    return const SharedAssetDisconnectBatchResult();
  }

  final items = <AssetDisconnectItem>[
    for (final phone in phones)
      if (phone.trim().isNotEmpty) AssetDisconnectItem.phone(phone),
    for (final code in equipmentCodes)
      if (code.trim().isNotEmpty) AssetDisconnectItem.equipment(code),
  ];
  final activeSession = session ?? AssetDisconnectSession(items: items);

  final keptPhones = <String>[];
  final keptEquipment = <String>[];
  final phoneTransfers = <String, SharedAssetTransferTarget>{};
  final equipmentTransfers = <String, SharedAssetTransferTarget>{};
  final phonesToDelete = <String>[];
  final equipmentToDelete = <String>[];
  final newDepartmentNames = <String>{};

  final canKeepInDepartment =
      allowKeepInDepartment &&
      sourceDepartmentId != null &&
      (sourceDepartmentName?.trim().isNotEmpty ?? false);

  for (final item in items) {
    if (!context.mounted) return null;

    final itemMode = item.isPhone
        ? mode
        : (mode == SharedAssetDisconnectMode.personalEquipment
              ? SharedAssetDisconnectMode.personalEquipment
              : SharedAssetDisconnectMode.sharedAsset);

    SharedAssetDisconnectItemResult? result;
    final standing = activeSession.standingDecisionFor(item.kind);
    if (standing != null &&
        _standingIsApplicable(
          standing,
          canKeepInDepartment: canKeepInDepartment,
        )) {
      result = standing.toItemResult();
    } else {
      final resolution = await _resolveSingleItem(
        context: context,
        item: item,
        sourceDepartmentId: sourceDepartmentId,
        sourceDepartmentName: sourceDepartmentName,
        availableDepartments: availableDepartments,
        mode: itemMode,
        personalPhoneUserDisplayName: personalPhoneUserDisplayName,
        canKeepInDepartment: canKeepInDepartment,
        session: activeSession,
        referenceLookup: referenceLookup,
        historyLookup: historyLookup,
      );
      if (resolution == null) return null;
      final newStanding = resolution.standing;
      if (newStanding != null) {
        activeSession.applyStandingDecision(newStanding);
        result = newStanding.toItemResult();
      } else {
        result = resolution.result;
      }
    }
    if (result == null) return null;

    activeSession.markResolved(item);

    switch (result.choice) {
      case SharedAssetDisconnectChoice.keepInDepartment:
        if (item.isPhone) {
          keptPhones.add(item.value);
        } else {
          keptEquipment.add(item.value);
        }
      case SharedAssetDisconnectChoice.transfer:
        final target = result.transferTarget;
        if (target == null) return null;
        if (item.isPhone) {
          phoneTransfers[item.value] = target;
        } else {
          equipmentTransfers[item.value] = target;
        }
        final newName = target.newDepartmentName?.trim();
        if (newName != null && newName.isNotEmpty) {
          newDepartmentNames.add(newName);
        }
      case SharedAssetDisconnectChoice.delete:
        if (item.isPhone) {
          phonesToDelete.add(item.value);
        } else {
          equipmentToDelete.add(item.value);
        }
    }
  }

  return SharedAssetDisconnectBatchResult(
    phonesToKeep: keptPhones,
    equipmentToKeep: keptEquipment,
    phoneTransfers: phoneTransfers,
    equipmentTransfers: equipmentTransfers,
    phonesToDelete: phonesToDelete,
    equipmentToDelete: equipmentToDelete,
    newDepartmentNamesToCreate: newDepartmentNames,
  );
}

/// Μια καθολική απόφαση δεν εφαρμόζεται σιωπηλά όπου δεν έχει νόημα: η
/// «παραμονή» χρειάζεται τμήμα-πηγή, η «μεταφορά» χρειάζεται στόχο.
bool _standingIsApplicable(
  AssetDisconnectStandingDecision decision, {
  required bool canKeepInDepartment,
}) {
  switch (decision.choice) {
    case SharedAssetDisconnectChoice.keepInDepartment:
      return canKeepInDepartment;
    case SharedAssetDisconnectChoice.transfer:
      return decision.transferTarget != null;
    case SharedAssetDisconnectChoice.delete:
      return true;
  }
}

String _disconnectDialogTitle({
  required bool isPhone,
  required SharedAssetDisconnectMode mode,
}) {
  if (isPhone && mode == SharedAssetDisconnectMode.personalPhone) {
    return 'Αποδέσμευση προσωπικού τηλεφώνου';
  }
  if (!isPhone && mode == SharedAssetDisconnectMode.personalEquipment) {
    return 'Αποδέσμευση προσωπικού εξοπλισμού';
  }
  return isPhone
      ? 'Αποδέσμευση κοινόχρηστου τηλεφώνου'
      : 'Αποδέσμευση κοινόχρηστου εξοπλισμού';
}

String _personalEmployeeQuotedLabel({
  String? personalPhoneUserDisplayName,
  String? sourceDepartmentName,
}) {
  final user = personalPhoneUserDisplayName?.trim();
  if (user == null || user.isEmpty) return '';
  final dept = sourceDepartmentName?.trim();
  if (dept == null || dept.isEmpty) return ' «$user»';
  return ' «$user ($dept)»';
}

/// Κείμενο σώματος διαλόγου αποδέσμευσης (τεσταρίσιμο).
@visibleForTesting
String disconnectDialogContent({
  required bool isPhone,
  required String value,
  required SharedAssetDisconnectMode mode,
  String? sourceDepartmentName,
  String? personalPhoneUserDisplayName,
}) {
  if (isPhone && mode == SharedAssetDisconnectMode.personalPhone) {
    final userPart = _personalEmployeeQuotedLabel(
      personalPhoneUserDisplayName: personalPhoneUserDisplayName,
      sourceDepartmentName: sourceDepartmentName,
    );
    return 'Ο αριθμός $value πρόκειται να αποσυνδεθεί από τον υπάλληλο$userPart.\n\nΕπιλέξτε ενέργεια:';
  }
  if (!isPhone && mode == SharedAssetDisconnectMode.personalEquipment) {
    final userPart = _personalEmployeeQuotedLabel(
      personalPhoneUserDisplayName: personalPhoneUserDisplayName,
      sourceDepartmentName: sourceDepartmentName,
    );
    return 'Ο εξοπλισμός $value πρόκειται να αποσυνδεθεί από τον υπάλληλο$userPart.\n\nΕπιλέξτε ενέργεια:';
  }
  final dept = sourceDepartmentName?.trim() ?? '';
  return isPhone
      ? 'Το κοινόχρηστο τηλέφωνο $value πρόκειται να αποδεσμευτεί από το τμήμα «$dept».\n\nΕπιλέξτε ενέργεια:'
      : 'Ο κοινόχρηστος εξοπλισμός $value πρόκειται να αποδεσμευτεί από το τμήμα «$dept».\n\nΕπιλέξτε ενέργεια:';
}

/// Κείμενο επιβεβαίωσης κατάργησης με απαρίθμηση συνδέσεων (τεσταρίσιμο).
@visibleForTesting
String formatAssetReferenceDeleteMessage({
  required bool isPhone,
  required String value,
  required List<String> descriptions,
}) {
  if (descriptions.isEmpty) {
    return isPhone
        ? 'Ο αριθμός $value δεν συνδέεται με άλλες εγγραφές. Να καταργηθεί;'
        : 'Ο εξοπλισμός $value δεν συνδέεται με άλλες εγγραφές. Να καταργηθεί;';
  }

  final buf = StringBuffer(
    isPhone
        ? 'Ο αριθμός $value συνδέεται με:'
        : 'Ο εξοπλισμός $value συνδέεται με:',
  );
  final visibleCount = descriptions.length > 5 ? 5 : descriptions.length;
  for (var i = 0; i < visibleCount; i++) {
    buf.write('\n• ${descriptions[i]}');
  }
  if (descriptions.length > 5) {
    buf.write('\n…και ${descriptions.length - 5} ακόμα');
  }
  buf.write('\nΝα καταργηθεί;');
  return buf.toString();
}

String _keepInDepartmentLabel(
  SharedAssetDisconnectMode mode, {
  String? sourceDepartmentName,
}) {
  final dept = sourceDepartmentName?.trim() ?? '';
  if (dept.isNotEmpty) {
    return 'Παραμονή στο $dept';
  }
  if (mode == SharedAssetDisconnectMode.personalEquipment) {
    return 'Παραμονή στο τμήμα του υπαλλήλου';
  }
  return 'Παραμονή στο ίδιο τμήμα';
}

/// Πρόθεση γρήγορης επιλογής — η επιβεβαίωσή της γίνεται έξω από τον διάλογο.
enum _QuickActionIntent {
  deleteEverything,
  deletePhones,
  deleteEquipment,
  keepEverything,
  transferEverything,
}

/// Απάντηση του κύριου διαλόγου: μεμονωμένη επιλογή ή πρόθεση γρήγορης επιλογής.
class _DisconnectDialogAnswer {
  const _DisconnectDialogAnswer.single(this.choice) : quick = null;
  const _DisconnectDialogAnswer.quick(this.quick) : choice = null;

  final SharedAssetDisconnectChoice? choice;
  final _QuickActionIntent? quick;
}

/// Έκβαση ενός βήματος: απάντηση για το στοιχείο ή νέα καθολική απόφαση.
class _ItemResolution {
  const _ItemResolution.item(this.result) : standing = null;
  const _ItemResolution.standing(this.standing) : result = null;

  final SharedAssetDisconnectItemResult? result;
  final AssetDisconnectStandingDecision? standing;
}

Future<_ItemResolution?> _resolveSingleItem({
  required BuildContext context,
  required AssetDisconnectItem item,
  int? sourceDepartmentId,
  String? sourceDepartmentName,
  required List<DepartmentModel> availableDepartments,
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
        title: Text(_disconnectDialogTitle(isPhone: isPhone, mode: mode)),
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
                  _ActionSection(
                    header: assetDisconnectSingleActionsHeader(
                      isPhone: isPhone,
                    ),
                    tinted: false,
                    actions: [
                      if (canKeepInDepartment)
                        _ActionEntry(
                          icon: Icons.check_circle_outline,
                          label: _keepInDepartmentLabel(
                            mode,
                            sourceDepartmentName: sourceDepartmentName,
                          ),
                          onTap: () => Navigator.of(ctx).pop(
                            const _DisconnectDialogAnswer.single(
                              SharedAssetDisconnectChoice.keepInDepartment,
                            ),
                          ),
                        ),
                      _ActionEntry(
                        icon: Icons.drive_file_move_outlined,
                        label: 'Μεταφορά σε άλλο τμήμα',
                        onTap: () => Navigator.of(ctx).pop(
                          const _DisconnectDialogAnswer.single(
                            SharedAssetDisconnectChoice.transfer,
                          ),
                        ),
                      ),
                      _ActionEntry(
                        icon: Icons.delete_outline,
                        label: 'Διαγραφή',
                        danger: true,
                        onTap: () => Navigator.of(ctx).pop(
                          const _DisconnectDialogAnswer.single(
                            SharedAssetDisconnectChoice.delete,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _QuickActionsSection(
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
      final cancelAll = await _confirmCancelAll(
        context: context,
        session: session,
      );
      if (!context.mounted) return null;
      if (cancelAll == true) return null;
      continue;
    }

    final intent = answer.quick;
    if (intent != null) {
      final standing = await _resolveQuickAction(
        context: context,
        intent: intent,
        session: session,
        availableDepartments: availableDepartments,
        sourceDepartmentId: sourceDepartmentId,
        sourceDepartmentName: sourceDepartmentName,
        historyLookup: historyLookup,
      );
      if (!context.mounted) return null;
      if (standing == null) continue;
      return _ItemResolution.standing(standing);
    }

    switch (answer.choice!) {
      case SharedAssetDisconnectChoice.keepInDepartment:
        return const _ItemResolution.item(
          SharedAssetDisconnectItemResult.keep(),
        );
      case SharedAssetDisconnectChoice.transfer:
        final target = await _showTransferDialog(
          context: context,
          isPhone: isPhone,
          value: item.value,
          sourceDepartmentId: sourceDepartmentId,
          availableDepartments: availableDepartments,
        );
        if (!context.mounted) return null;
        if (target == null) continue;
        return _ItemResolution.item(
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
        return const _ItemResolution.item(
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

/// Μία ενέργεια μέσα σε ενότητα ενεργειών.
class _ActionEntry {
  const _ActionEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// Ενότητα ενεργειών με δική της επικεφαλίδα, ώστε να μη μπερδεύεται το
/// «για αυτό το στοιχείο» με το «για όλα».
class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.header,
    required this.actions,
    required this.tinted,
    this.footnote,
  });

  final String header;
  final List<_ActionEntry> actions;
  final bool tinted;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = footnote?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(header, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: tinted ? theme.colorScheme.surfaceContainerHighest : null,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++)
                _ActionTile(
                  entry: actions[i],
                  showDivider: i < actions.length - 1,
                ),
            ],
          ),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            note,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.entry, required this.showDivider});

  final _ActionEntry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = entry.danger ? theme.colorScheme.error : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              )
            : null,
      ),
      child: InkWell(
        onTap: entry.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                entry.icon,
                size: 18,
                color: color ?? theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.label,
                  style: theme.textTheme.bodyMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Οι καθολικές επιλογές για όσα στοιχεία απομένουν.
class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection({
    required this.session,
    required this.canKeepInDepartment,
    required this.onIntent,
  });

  final AssetDisconnectSession session;
  final bool canKeepInDepartment;
  final ValueChanged<_QuickActionIntent> onIntent;

  @override
  Widget build(BuildContext context) {
    final remaining = session.remainingSteps;
    if (remaining < 2) return const SizedBox.shrink();

    final phoneCount = session.remainingPhoneCount;
    final equipmentCount = session.remainingEquipmentCount;
    final mixed = phoneCount > 0 && equipmentCount > 0;

    // «Παραμονή για όλα» μόνο όταν τα υπόλοιπα είναι όντως στο ίδιο τμήμα:
    // ένα τηλέφωνο των Αδειών δεν «παραμένει» στην Ψυχιατρική.
    final commonDept = session.commonRemainingDepartmentName;
    final canKeepEverything = canKeepInDepartment && commonDept != null;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _ActionSection(
        header: assetDisconnectQuickActionsHeader(
          remainingSteps: remaining,
          isAtFirstStep: session.isAtFirstStep,
        ),
        tinted: true,
        footnote: canKeepEverything
            ? null
            : _mixedDepartmentsFootnote(session, canKeepInDepartment),
        actions: [
          _ActionEntry(
            icon: Icons.delete_sweep_outlined,
            label: 'Διαγραφή όλων ($remaining)',
            danger: true,
            onTap: () => onIntent(_QuickActionIntent.deleteEverything),
          ),
          if (mixed)
            _ActionEntry(
              icon: Icons.phone_disabled_outlined,
              label: 'Διαγραφή όλων των τηλεφώνων ($phoneCount)',
              danger: true,
              onTap: () => onIntent(_QuickActionIntent.deletePhones),
            ),
          if (mixed)
            _ActionEntry(
              icon: Icons.devices_other_outlined,
              label: 'Διαγραφή όλου του εξοπλισμού ($equipmentCount)',
              danger: true,
              onTap: () => onIntent(_QuickActionIntent.deleteEquipment),
            ),
          if (canKeepEverything)
            _ActionEntry(
              icon: Icons.check_circle_outline,
              label: 'Παραμονή στο $commonDept — όλα ($remaining)',
              onTap: () => onIntent(_QuickActionIntent.keepEverything),
            ),
          _ActionEntry(
            icon: Icons.drive_file_move_outlined,
            label: 'Μεταφορά όλων σε ένα τμήμα ($remaining)',
            onTap: () => onIntent(_QuickActionIntent.transferEverything),
          ),
        ],
      ),
    );
  }

  String? _mixedDepartmentsFootnote(
    AssetDisconnectSession session,
    bool canKeepInDepartment,
  ) {
    if (!canKeepInDepartment) return null;
    final deptCount = session.remainingDepartmentCount;
    if (deptCount < 2) return null;
    return 'Τα στοιχεία ανήκουν σε $deptCount τμήματα, οπότε δεν μπορούν να '
        '«παραμείνουν» κάπου όλα μαζί. Στη μεταφορά μπορείτε να διαλέξετε '
        'και ένα από αυτά τα τμήματα.';
  }
}

/// Περιεχόμενο επιβεβαίωσης: κάθε στοιχείο σε δική του γραμμή με τι είναι,
/// ποιανού είναι, από πού, και τι ιστορικό κρατά.
///
/// Δείχνονται ΟΛΑ τα στοιχεία — μια κομμένη λίστα με «…και 2 ακόμα» κρύβει
/// ακριβώς αυτά που ο χρήστης θέλει να ελέγξει.
class _BulkPreviewContent extends StatelessWidget {
  const _BulkPreviewContent({
    required this.headline,
    required this.items,
    required this.histories,
    required this.showUndoReminder,
  });

  final String headline;
  final List<AssetDisconnectItem> items;
  final List<AssetHistoryLinks> histories;
  final bool showUndoReminder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(headline),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _BulkPreviewRow(
                      item: items[i],
                      history: i < histories.length ? histories[i] : null,
                      showDivider: i < items.length - 1,
                    ),
                ],
              ),
            ),
            if (showUndoReminder) ...[
              const SizedBox(height: 10),
              Text(
                assetDisconnectUndoReminder,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BulkPreviewRow extends StatelessWidget {
  const _BulkPreviewRow({
    required this.item,
    required this.history,
    required this.showDivider,
  });

  final AssetDisconnectItem item;
  final AssetHistoryLinks? history;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final historyLabel = assetDisconnectHistoryLabel(history);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.isPhone ? Icons.phone_outlined : Icons.devices_other_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: item.value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: ' · ${assetDisconnectItemOwnerLabel(item)}',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (historyLabel.isNotEmpty)
                    TextSpan(
                      text: ' · $historyLabel',
                      style: TextStyle(color: theme.colorScheme.tertiary),
                    ),
                ],
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ονομασία τμήματος-στόχου για το μήνυμα προεπισκόπησης.
String? _transferTargetName(
  SharedAssetTransferTarget target,
  List<DepartmentModel> availableDepartments,
) {
  final newName = target.newDepartmentName?.trim();
  if (newName != null && newName.isNotEmpty) return newName;
  final id = target.departmentId;
  if (id == null) return null;
  for (final dept in availableDepartments) {
    if (dept.id == id) return dept.name.trim();
  }
  return null;
}

Future<AssetDisconnectStandingDecision?> _resolveQuickAction({
  required BuildContext context,
  required _QuickActionIntent intent,
  required AssetDisconnectSession session,
  required List<DepartmentModel> availableDepartments,
  int? sourceDepartmentId,
  String? sourceDepartmentName,
  AssetHistoryLinksLookup? historyLookup,
}) async {
  final remaining = session.remainingItems;

  final List<AssetDisconnectItem> affected;
  final SharedAssetDisconnectChoice choice;
  switch (intent) {
    case _QuickActionIntent.deleteEverything:
      affected = remaining;
      choice = SharedAssetDisconnectChoice.delete;
    case _QuickActionIntent.deletePhones:
      affected = remaining.where((i) => i.isPhone).toList();
      choice = SharedAssetDisconnectChoice.delete;
    case _QuickActionIntent.deleteEquipment:
      affected = remaining.where((i) => !i.isPhone).toList();
      choice = SharedAssetDisconnectChoice.delete;
    case _QuickActionIntent.keepEverything:
      affected = remaining;
      choice = SharedAssetDisconnectChoice.keepInDepartment;
    case _QuickActionIntent.transferEverything:
      affected = remaining;
      choice = SharedAssetDisconnectChoice.transfer;
  }
  if (affected.isEmpty) return null;

  SharedAssetTransferTarget? target;
  if (choice == SharedAssetDisconnectChoice.transfer) {
    target = await showAssetTransferTargetPicker(
      context: context,
      headerLabel: 'Μεταφορά ${affected.length} στοιχείων σε ένα τμήμα',
      availableDepartments: availableDepartments,
      // Στη μαζική μεταφορά ΔΕΝ αποκλείεται κανένα τμήμα: όταν τα στοιχεία
      // ανήκουν σε πολλά τμήματα, «μεταφορά εκεί που ήδη ανήκει» είναι ο
      // μόνος τρόπος να μείνει κάτι στη θέση του.
      sourceDepartmentId: null,
    );
    if (!context.mounted || target == null) return null;
  }

  // Το ιστορικό κάθε στοιχείου ξεχωριστά: ο κάτοχος δεν μετράει ως «σύνδεση»,
  // γιατί τον έχουν σχεδόν όλα και η προειδοποίηση θα ίσχυε πάντα.
  final histories = choice == SharedAssetDisconnectChoice.delete
      ? await assetHistoryLinksFor(affected, lookup: historyLookup)
      : const <AssetHistoryLinks>[];
  if (!context.mounted) return null;

  final headline = assetDisconnectBulkPreviewHeadline(
    choice: choice,
    items: affected,
    transferDepartmentName: target == null
        ? null
        : _transferTargetName(target, availableDepartments),
  );

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(
        assetDisconnectBulkTitle(choice: choice, itemCount: affected.length),
      ),
      content: _BulkPreviewContent(
        headline: headline,
        items: affected,
        histories: histories,
        showUndoReminder: choice == SharedAssetDisconnectChoice.delete,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Ναι, εφαρμογή σε όλα'),
        ),
      ],
    ),
  );
  if (confirmed != true) return null;

  switch (intent) {
    case _QuickActionIntent.deleteEverything:
      return const AssetDisconnectStandingDecision.deleteEverything();
    case _QuickActionIntent.deletePhones:
      return const AssetDisconnectStandingDecision.deletePhones();
    case _QuickActionIntent.deleteEquipment:
      return const AssetDisconnectStandingDecision.deleteEquipment();
    case _QuickActionIntent.keepEverything:
      return const AssetDisconnectStandingDecision.keepEverything();
    case _QuickActionIntent.transferEverything:
      return AssetDisconnectStandingDecision.transferEverything(target);
  }
}

Future<bool?> _confirmCancelAll({
  required BuildContext context,
  required AssetDisconnectSession session,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Ακύρωση όλων;'),
      content: Text(
        assetDisconnectCancelMessage(
          resolvedSteps: session.resolvedSteps,
          cancelScopeDescription: session.cancelScopeDescription,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Συνέχεια'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Ακύρωση όλων'),
        ),
      ],
    ),
  );
}

Future<SharedAssetTransferTarget?> _showTransferDialog({
  required BuildContext context,
  required bool isPhone,
  required String value,
  int? sourceDepartmentId,
  required List<DepartmentModel> availableDepartments,
}) async {
  final depts =
      availableDepartments
          .where(
            (d) =>
                d.id != null &&
                (sourceDepartmentId == null || d.id != sourceDepartmentId) &&
                !d.isDeleted &&
                d.name.trim().isNotEmpty,
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  return showDialog<SharedAssetTransferTarget>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SharedAssetTransferDialog(
      isPhone: isPhone,
      value: value,
      departments: depts,
    ),
  );
}

/// Δημόσιος επιλογέας τμήματος προορισμού (υπάρχον ή νέο), για επαναχρησιμοποίηση.
Future<SharedAssetTransferTarget?> showAssetTransferTargetPicker({
  required BuildContext context,
  required String headerLabel,
  required List<DepartmentModel> availableDepartments,
  int? sourceDepartmentId,
}) async {
  final depts =
      availableDepartments
          .where(
            (d) =>
                d.id != null &&
                (sourceDepartmentId == null || d.id != sourceDepartmentId) &&
                !d.isDeleted &&
                d.name.trim().isNotEmpty,
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  return showDialog<SharedAssetTransferTarget>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SharedAssetTransferDialog(
      isPhone: true,
      value: '',
      departments: depts,
      headerLabel: headerLabel,
    ),
  );
}

class _SharedAssetTransferDialog extends StatefulWidget {
  const _SharedAssetTransferDialog({
    required this.isPhone,
    required this.value,
    required this.departments,
    this.headerLabel,
  });

  final bool isPhone;
  final String value;
  final List<DepartmentModel> departments;
  final String? headerLabel;

  @override
  State<_SharedAssetTransferDialog> createState() =>
      _SharedAssetTransferDialogState();
}

class _SharedAssetTransferDialogState
    extends State<_SharedAssetTransferDialog> {
  final _departmentController = TextEditingController();
  final _departmentFocus = FocusNode();

  List<String> get _departmentNames => widget.departments
      .map((d) => d.name.trim())
      .where((n) => n.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    _departmentController.addListener(_onDepartmentTextChanged);
  }

  void _onDepartmentTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _departmentController.removeListener(_onDepartmentTextChanged);
    _departmentController.dispose();
    _departmentFocus.dispose();
    super.dispose();
  }

  DepartmentModel? _matchDepartment(String text) {
    final q = SearchTextNormalizer.normalizeForSearch(text.trim());
    if (q.isEmpty) return null;
    for (final d in widget.departments) {
      if (SearchTextNormalizer.normalizeForSearch(d.name) == q) return d;
    }
    return null;
  }

  Iterable<String> _departmentOptions(String query) {
    final q = SearchTextNormalizer.normalizeForSearch(query);
    final matches = q.isEmpty
        ? List<String>.from(_departmentNames)
        : _departmentNames
              .where(
                (name) => SearchTextNormalizer.matchesNormalizedQuery(name, q),
              )
              .toList();
    final typed = query.trim();
    if (typed.isNotEmpty && _matchDepartment(typed) == null) {
      matches.add(_createDepartmentOptionValue(typed));
    }
    return matches;
  }

  Future<bool> _confirmCreateDepartment(String newName) async {
    final String content;
    final customHeader = widget.headerLabel;
    if (customHeader != null) {
      content = 'Θα δημιουργηθεί νέο τμήμα: $newName.';
    } else if (widget.isPhone) {
      content =
          'Θα δημιουργηθεί νέο τμήμα: $newName με κοινόχρηστο τηλέφωνο: ${widget.value}.';
    } else {
      content =
          'Θα δημιουργηθεί νέο τμήμα: $newName με κοινόχρηστο εξοπλισμό: ${widget.value}.';
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (confirmCtx) => AlertDialog(
        title: const Text('Δημιουργία νέου τμήματος'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmCtx).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(confirmCtx).pop(true),
            child: const Text('Επιβεβαίωση'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _submitNewDepartment(String newName) async {
    if (!await _confirmCreateDepartment(newName)) return;
    if (!mounted) return;
    Navigator.of(context).pop(SharedAssetTransferTarget.createNew(newName));
  }

  Future<void> _submit() async {
    final text = _departmentController.text.trim();
    if (text.isEmpty) return;
    final matched = _matchDepartment(text);
    if (matched?.id != null) {
      Navigator.of(
        context,
      ).pop(SharedAssetTransferTarget.existing(matched!.id!));
      return;
    }
    await _submitNewDepartment(text);
  }

  Future<void> _onDepartmentOptionSelected(String selection) async {
    final text = _isCreateDepartmentOption(selection)
        ? selection.substring(_kCreateDepartmentOptionPrefix.length)
        : selection;
    _departmentController.text = text;
    _departmentController.selection = TextSelection.collapsed(
      offset: text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Μεταφορά κοινόχρηστου'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.headerLabel ??
                  (widget.isPhone
                      ? 'Τηλέφωνο: ${widget.value}'
                      : 'Εξοπλισμός: ${widget.value}'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            RawAutocomplete<String>(
              textEditingController: _departmentController,
              focusNode: _departmentFocus,
              displayStringForOption: _departmentOptionLabel,
              optionsBuilder: (textEditingValue) =>
                  _departmentOptions(textEditingValue.text),
              onSelected: (selection) => _onDepartmentOptionSelected(selection),
              fieldViewBuilder: (context, controller, focusNode, _) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Τμήμα προορισμού',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _submit(),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final opts = options.toList();
                if (opts.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 400,
                        maxHeight: 220,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: opts.length,
                        itemBuilder: (context, index) {
                          final option = opts[index];
                          final isCreate = _isCreateDepartmentOption(option);
                          return ListTile(
                            dense: true,
                            leading: isCreate
                                ? Icon(
                                    Icons.add_circle_outline,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                            title: Text(
                              _departmentOptionLabel(option),
                              style: isCreate
                                  ? TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    )
                                  : null,
                            ),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: _departmentController.text.trim().isEmpty ? null : _submit,
          child: const Text('Μεταφορά'),
        ),
      ],
    );
  }
}

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
    builder: (ctx) => AlertDialog(
      title: Text(isPhone ? 'Διαγραφή τηλεφώνου' : 'Διαγραφή εξοπλισμού'),
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
  );
}
