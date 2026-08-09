import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_search_filter_selection.dart';
import '../../../core/database/old_database/lamp_unlinked_entities.dart';

/// Κουμπί «Φίλτρα» της αναζήτησης Λάμπας, με δύο ενότητες.
///
/// Το φίλτρο δεν κόβει αποτελέσματα — **ορίζει τι ψάχνουμε**: με ενεργές
/// ασύνδετες ο εξοπλισμός κρύβεται, και η αναζήτηση (ακόμη και κενή)
/// επιστρέφει μόνο οντότητες των επιλεγμένων ειδών.
class LampSearchFiltersButton extends StatefulWidget {
  const LampSearchFiltersButton({
    super.key,
    required this.selection,
    required this.loadCounts,
    required this.onChanged,
  });

  final LampSearchFilterSelection selection;

  /// Πλήθη για το μενού: με ενεργή αναζήτηση τα ταιριάσματά της, αλλιώς τα
  /// συνολικά της βάσης.
  final Future<LampFilterMenuCounts> Function() loadCounts;

  final ValueChanged<LampSearchFilterSelection> onChanged;

  @override
  State<LampSearchFiltersButton> createState() =>
      _LampSearchFiltersButtonState();
}

class _LampSearchFiltersButtonState extends State<LampSearchFiltersButton> {
  final MenuController _menuController = MenuController();
  LampFilterMenuCounts _counts = const LampFilterMenuCounts();

  Future<void> _openMenu() async {
    final counts = await widget.loadCounts();
    if (!mounted) return;
    setState(() => _counts = counts);
    _menuController.open();
  }

  void _toggleAllUnlinked() {
    final all = LampUnlinkedEntityKind.values.toSet();
    final allSelected = widget.selection.unlinkedKinds.length == all.length;
    widget.onChanged(
      widget.selection.copyWith(
        unlinkedKinds: allSelected ? <LampUnlinkedEntityKind>{} : all,
        // Χωρίς είδη, η υπο-επιλογή «μόνο οι κενές» δεν έχει σε τι να ισχύσει.
        onlyEmptyUnlinked: allSelected ? false : null,
      ),
    );
  }

  void _toggleKind(LampUnlinkedEntityKind kind) {
    final next = Set<LampUnlinkedEntityKind>.from(
      widget.selection.unlinkedKinds,
    );
    next.contains(kind) ? next.remove(kind) : next.add(kind);
    widget.onChanged(
      widget.selection.copyWith(
        unlinkedKinds: next,
        onlyEmptyUnlinked: next.isEmpty ? false : null,
      ),
    );
  }

  void _toggleGap(LampEquipmentGapKind gap) {
    final next = Set<LampEquipmentGapKind>.from(widget.selection.equipmentGaps);
    next.contains(gap) ? next.remove(gap) : next.add(gap);
    widget.onChanged(widget.selection.copyWith(equipmentGaps: next));
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.selection;
    final allUnlinkedSelected =
        selection.unlinkedKinds.length == LampUnlinkedEntityKind.values.length;

    return MenuAnchor(
      controller: _menuController,
      menuChildren: [
        _sectionTitle(context, 'Χωρίς συνδεδεμένο εξοπλισμό'),
        CheckboxMenuButton(
          key: const Key('lamp_filter_all'),
          value: allUnlinkedSelected,
          closeOnActivate: false,
          onChanged: (_) => _toggleAllUnlinked(),
          child: const Text('Όλες'),
        ),
        for (final kind in LampUnlinkedEntityKind.values)
          CheckboxMenuButton(
            key: Key('lamp_filter_${kind.name}'),
            value: selection.unlinkedKinds.contains(kind),
            closeOnActivate: false,
            // Είδος χωρίς ταιριάσματα δεν προσφέρει τίποτα — εκτός αν είναι
            // ήδη επιλεγμένο, οπότε πρέπει να μπορεί να ξε-επιλεγεί.
            onChanged:
                (_counts.byKind[kind] ?? 0) > 0 ||
                    selection.unlinkedKinds.contains(kind)
                ? (_) => _toggleKind(kind)
                : null,
            child: _labelWithCount(
              context,
              _capitalize(kind.pluralLabel),
              _counts.byKind[kind] ?? 0,
            ),
          ),
        CheckboxMenuButton(
          key: const Key('lamp_filter_only_empty'),
          value: selection.onlyEmptyUnlinked,
          closeOnActivate: false,
          onChanged: selection.hasUnlinked
              ? (_) => widget.onChanged(
                  selection.copyWith(
                    onlyEmptyUnlinked: !selection.onlyEmptyUnlinked,
                  ),
                )
              : null,
          child: _labelWithCount(
            context,
            '…μόνο οι κενές',
            _counts.emptyRecords,
          ),
        ),
        const Divider(height: 8),
        _sectionTitle(context, 'Εξοπλισμός με κενά'),
        for (final gap in LampEquipmentGapKind.values)
          CheckboxMenuButton(
            key: Key('lamp_filter_gap_${gap.name}'),
            value: selection.equipmentGaps.contains(gap),
            closeOnActivate: false,
            onChanged: (_) => _toggleGap(gap),
            child: _labelWithCount(
              context,
              gap.label,
              _counts.equipmentGaps[gap] ?? 0,
            ),
          ),
      ],
      builder: (context, controller, child) {
        final count = selection.activeSectionCount;
        final label = count == 0 ? 'Φίλτρα' : 'Φίλτρα · $count';
        void toggle() => controller.isOpen ? controller.close() : _openMenu();
        return count == 0
            ? OutlinedButton.icon(
                key: const Key('lamp_filters_button'),
                onPressed: toggle,
                icon: const Icon(Icons.filter_list),
                label: Text(label),
              )
            : FilledButton.tonalIcon(
                key: const Key('lamp_filters_button'),
                onPressed: toggle,
                icon: const Icon(Icons.filter_list),
                label: Text(label),
              );
      },
    );
  }

  static Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static Widget _labelWithCount(BuildContext context, String label, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 12),
        Text(
          '$count',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _capitalize(String raw) =>
      raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
}
