import 'package:flutter/material.dart';

import '../../../../core/widgets/compact_tooltip.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../services/department_deletion_inventory.dart';
import '../../services/department_deletion_messages.dart';

/// Επιλογή μετά την προεπισκόπηση διαγραφής τμήματος.
enum DepartmentDeletionChoice { cancel, detailed, quickAll }

/// Τι αποφάσισε ο χρήστης **και** ποια τμήματα άφησε στη λίστα.
///
/// Τα [keptDepartmentIds] μπορεί να είναι λιγότερα από όσα δόθηκαν: ο χρήστης
/// αφαιρεί όσα δεν ήθελε χωρίς να κλείσει τον διάλογο και να ξαναρχίσει.
typedef DepartmentDeletionPreviewResult = ({
  DepartmentDeletionChoice choice,
  List<int> keptDepartmentIds,
});

/// Ύψος της κυλιόμενης ζώνης όταν τα τμήματα είναι πολλά.
///
/// Χωρίς όριο, με 58 επιλεγμένα τμήματα ο διάλογος ξεπερνά την οθόνη και τα
/// κουμπιά φεύγουν από το οπτικό πεδίο.
const double _kMaxListHeight = 420;

/// Οι υποδείξεις των κουμπιών απόφασης είναι μεγάλες προτάσεις — αργούν λίγο
/// να εμφανιστούν ώστε να μην πετάγονται στο πέρασμα του δείκτη, και μένουν
/// αρκετά για να διαβαστούν.
const Duration _kTooltipDelay = Duration(milliseconds: 300);
const Duration _kTooltipDuration = Duration(seconds: 10);

/// Προεπισκόπηση «Τι θα συμβεί» πριν τη διαγραφή τμημάτων.
Future<DepartmentDeletionPreviewResult?> showDepartmentDeletionPreviewDialog({
  required BuildContext context,
  required List<DepartmentDeletionInventory> inventories,
}) {
  return showDialog<DepartmentDeletionPreviewResult>(
    context: context,
    builder: (ctx) =>
        _DepartmentDeletionPreviewDialog(initialInventories: inventories),
  );
}

class _DepartmentDeletionPreviewDialog extends StatefulWidget {
  const _DepartmentDeletionPreviewDialog({required this.initialInventories});

  final List<DepartmentDeletionInventory> initialInventories;

  @override
  State<_DepartmentDeletionPreviewDialog> createState() =>
      _DepartmentDeletionPreviewDialogState();
}

class _DepartmentDeletionPreviewDialogState
    extends State<_DepartmentDeletionPreviewDialog> {
  late List<DepartmentDeletionInventory> _kept;

  @override
  void initState() {
    super.initState();
    _kept = List<DepartmentDeletionInventory>.from(widget.initialInventories);
  }

  void _remove(int departmentId) {
    setState(() {
      _kept = _kept.where((i) => i.departmentId != departmentId).toList();
    });
  }

  void _pop(DepartmentDeletionChoice choice) {
    Navigator.of(context).pop((
      choice: choice,
      keptDepartmentIds: [for (final i in _kept) i.departmentId],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAnyDependencies = _kept.any((i) => !i.isEmpty);
    final showsEmployeesWarning = _kept.any((i) => i.hasEmployees);
    // Η σύνοψη ξαναϋπολογίζεται σε κάθε αφαίρεση: σύνοψη που δεν ακολουθεί τη
    // λίστα λέει ψέματα ακριβώς τη στιγμή που ο χρήστης αποφασίζει διαγραφή.
    final totals = DepartmentDeletionTotals.from(_kept);
    // Μόνο τα κοινόχρηστα ρωτιούνται ανά οντότητα — ό,τι ανήκει σε υπάλληλο
    // ακολουθεί την απόφαση για τον υπάλληλο.
    final sharedAssetCount =
        totals.sharedPhoneCount + totals.sharedEquipmentCount;
    final rows = buildDepartmentDeletionPreviewRows(_kept);
    final canRemove = _kept.length > 1;

    return DraggableDialogShell(
      title: const Text('Τι θα συμβεί'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Σύνοψη και προειδοποίηση μένουν σταθερές: με πολλά τμήματα ο
              // χρήστης πρέπει να ξέρει το μέγεθος της πράξης χωρίς να κυλήσει.
              //
              // Όταν κανένα τμήμα δεν έχει εξαρτήματα, η σύνοψη θα επαναλάμβανε
              // τη γραμμή «Ν τμήματα χωρίς εξαρτήματα» — παραλείπεται.
              if (_kept.length > 1 && hasAnyDependencies) ...[
                _TotalsHeader(
                  totals: totals,
                  initiallySelected: widget.initialInventories.length,
                ),
                const SizedBox(height: 10),
              ],
              if (showsEmployeesWarning) ...[
                _EmployeesWarningBanner(
                  colorScheme: theme.colorScheme,
                  textTheme: theme.textTheme,
                ),
                const SizedBox(height: 10),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _kMaxListHeight),
                  // Τεμπέλικη λίστα: χτίζονται μόνο οι ορατές γραμμές, όχι και
                  // οι 58. Γι' αυτό αντέχει κουμπί σε κάθε κάρτα.
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _PreviewRow(
                      row: rows[index],
                      onRemove: canRemove ? _remove : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _pop(DepartmentDeletionChoice.cancel),
            child: const Text('Ακύρωση'),
          ),
          if (hasAnyDependencies) ...[
            CompactTooltip(
              message: departmentDeletionDetailedTooltip(
                assetCount: sharedAssetCount,
                employeeCount: totals.employeeCount,
              ),
              waitDuration: _kTooltipDelay,
              showDuration: _kTooltipDuration,
              child: TextButton(
                onPressed: () => _pop(DepartmentDeletionChoice.detailed),
                child: const Text('Αναλυτικά (ανά οντότητα)'),
              ),
            ),
            CompactTooltip(
              message: departmentDeletionQuickTransferTooltip(
                assetCount: sharedAssetCount,
              ),
              waitDuration: _kTooltipDelay,
              showDuration: _kTooltipDuration,
              child: FilledButton(
                onPressed: () => _pop(DepartmentDeletionChoice.quickAll),
                child: const Text('Μεταφορά όλων σε ένα τμήμα…'),
              ),
            ),
          ] else
            CompactTooltip(
              message: departmentDeletionPlainDeleteTooltip(
                departmentCount: _kept.length,
              ),
              waitDuration: _kTooltipDelay,
              showDuration: _kTooltipDuration,
              child: FilledButton(
                onPressed: () => _pop(DepartmentDeletionChoice.detailed),
                child: const Text('Διαγραφή'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Μία γραμμή της προεπισκόπησης: επικεφαλίδα ζώνης, κάρτα τμήματος, ή η
/// πτυσσόμενη ομάδα των άδειων τμημάτων.
sealed class DepartmentDeletionPreviewRow {
  const DepartmentDeletionPreviewRow();
}

class ZoneHeaderRow extends DepartmentDeletionPreviewRow {
  const ZoneHeaderRow(this.title);
  final String title;
}

class InventoryCardRow extends DepartmentDeletionPreviewRow {
  const InventoryCardRow(this.inventory);
  final DepartmentDeletionInventory inventory;
}

class EmptyDepartmentsRow extends DepartmentDeletionPreviewRow {
  const EmptyDepartmentsRow({required this.title, required this.names});
  final String title;
  final List<String> names;
}

/// Ξεδιπλώνει τις ζώνες σε επίπεδη λίστα γραμμών για την τεμπέλικη λίστα.
///
/// Τα άδεια τμήματα μαζεύονται σε **μία** γραμμή: δεν ζητούν καμία απόφαση,
/// οπότε δεν αξίζουν κάρτα το καθένα.
List<DepartmentDeletionPreviewRow> buildDepartmentDeletionPreviewRows(
  List<DepartmentDeletionInventory> inventories,
) {
  final zones = DepartmentDeletionZones.from(inventories);
  final showHeaders = zones.showsZoneHeaders;
  final rows = <DepartmentDeletionPreviewRow>[];

  if (zones.withEmployees.isNotEmpty) {
    if (showHeaders) rows.add(ZoneHeaderRow(zones.withEmployeesHeader));
    rows.addAll(zones.withEmployees.map(InventoryCardRow.new));
  }
  if (zones.sharedOnly.isNotEmpty) {
    if (showHeaders) rows.add(ZoneHeaderRow(zones.sharedOnlyHeader));
    rows.addAll(zones.sharedOnly.map(InventoryCardRow.new));
  }
  final emptyHeader = zones.emptyHeader;
  if (emptyHeader != null) {
    rows.add(
      EmptyDepartmentsRow(
        title: emptyHeader,
        names: [
          for (final inv in zones.empty)
            inv.departmentName.trim().isEmpty ? '—' : inv.departmentName.trim(),
        ],
      ),
    );
  }
  return rows;
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.row, this.onRemove});

  final DepartmentDeletionPreviewRow row;

  /// `null` όταν δεν επιτρέπεται αφαίρεση (μένει ένα μόνο τμήμα).
  final void Function(int departmentId)? onRemove;

  @override
  Widget build(BuildContext context) {
    return switch (row) {
      ZoneHeaderRow(:final title) => _ZoneHeader(title: title),
      InventoryCardRow(:final inventory) => _DepartmentInventoryCard(
        inventory: inventory,
        onRemove: onRemove,
      ),
      EmptyDepartmentsRow(:final title, :final names) => _EmptyDepartmentsGroup(
        title: title,
        names: names,
      ),
    };
  }
}

class _ZoneHeader extends StatelessWidget {
  const _ZoneHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Τα άδεια τμήματα σε μία πτυσσόμενη γραμμή — τα ονόματα υπάρχουν, απλώς δεν
/// καταλαμβάνουν την οθόνη μέχρι να ζητηθούν.
class _EmptyDepartmentsGroup extends StatelessWidget {
  const _EmptyDepartmentsGroup({required this.title, required this.names});

  final String title;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        dense: true,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              names.join(', '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Σταθερή σύνοψη: το μέγεθος της πράξης με μια ματιά.
class _TotalsHeader extends StatelessWidget {
  const _TotalsHeader({required this.totals, required this.initiallySelected});

  final DepartmentDeletionTotals totals;

  /// Πόσα τμήματα είχε επιλέξει ο χρήστης πριν αφαιρέσει από τη λίστα.
  final int initiallySelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final following = totals.followingAssetsLine;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              totals.headline(initiallySelected: initiallySelected),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (following != null) ...[
              const SizedBox(height: 4),
              Text(
                following,
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

class _DepartmentInventoryCard extends StatelessWidget {
  const _DepartmentInventoryCard({required this.inventory, this.onRemove});

  final DepartmentDeletionInventory inventory;
  final void Function(int departmentId)? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summaryLines = inventory.buildSummaryLines();
    final name = inventory.departmentName.trim().isEmpty
        ? '—'
        : inventory.departmentName.trim();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Αφαίρεση από τη λίστα — το τμήμα δεν διαγράφεται',
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => onRemove!(inventory.departmentId),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (inventory.isEmpty)
              Text(
                'Δεν υπάρχουν εξαρτήματα',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              for (final line in summaryLines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(line, style: theme.textTheme.bodyMedium),
                ),
              if (inventory.hasEmployees) ...[
                const SizedBox(height: 6),
                Text(
                  _formatEmployeeNames(inventory.employeeNames),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String _formatEmployeeNames(List<String> names) {
  const maxVisible = 5;
  if (names.length <= maxVisible) {
    return names.join(', ');
  }
  final visible = names.take(maxVisible).join(', ');
  final remaining = names.length - maxVisible;
  return '$visible (+$remaining ακόμη)';
}

class _EmployeesWarningBanner extends StatelessWidget {
  const _EmployeesWarningBanner({
    required this.colorScheme,
    required this.textTheme,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          'Θα σας ζητηθεί πού μεταφέρεται κάθε υπάλληλος πριν διαγραφεί το '
          'τμήμα.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
