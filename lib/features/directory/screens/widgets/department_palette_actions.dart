import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/services/lookup_service.dart';
import '../../models/department_model.dart';
import 'department_color_palette.dart';
import 'department_palette_host.dart';
import 'department_palette_store.dart';

/// Προεπιλεγμένο χρώμα τμήματος (ίδιο με default βάσης).
const Color kDepartmentDefaultColor = Color(0xFF1976D2);
const String kDepartmentDefaultColorHex = '#1976D2';

enum _ClearSlotChoice { cancel, paletteOnly, paletteAndDepartments }

enum _FullPaletteChoice { cancel, departmentOnly, replace }

/// Ενέργειες παλέτας: διπλότυπα, καθαρισμός, γέμισμα θέσεων, διάλογοι.
class DepartmentPaletteActions {
  DepartmentPaletteActions._();

  static List<DepartmentModel> departmentsUsingColor(Color color) {
    final hex = colorToDepartmentHex(color);
    return LookupService.instance.departments
        .where((d) => !d.isDeleted && _hexOfDepartment(d) == hex)
        .toList();
  }

  static String? _hexOfDepartment(DepartmentModel d) {
    final c = tryParseDepartmentHex(d.color);
    if (c == null) return null;
    return colorToDepartmentHex(c);
  }

  static void showDuplicateSnackBar(BuildContext context, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Το χρώμα ${colorToDepartmentHex(color)} υπάρχει ήδη στην παλέτα.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Αποθήκευση σε custom θέση με έλεγχο διπλοτύπων.
  static Future<bool> assignToSlot(
    BuildContext context,
    int slotIndex,
    Color color, {
    int? exceptSlotForDuplicate,
  }) async {
    final store = DepartmentPaletteStore.instance;
    await store.ensureLoaded();
    if (store.colorExistsInPalette(
      color,
      exceptSlotIndex: exceptSlotForDuplicate,
    )) {
      if (context.mounted) showDuplicateSnackBar(context, color);
      return false;
    }
    await store.setCustomSlot(slotIndex, color);
    return true;
  }

  /// Μετά από επιλογέα (προεπισκόπηση): γέμισμα κενής θέσης ή διάλογος πλήρους παλέτας.
  static Future<Color?> applyPickedColorForPreview(
    BuildContext context, {
    required Color picked,
    required Color previousColor,
    DepartmentPaletteHost? host,
  }) async {
    final store = DepartmentPaletteStore.instance;
    await store.ensureLoaded();

    final existingSlot = store.indexOfCustomColor(previousColor);
    if (existingSlot != null) {
      if (!context.mounted) return null;
      if (!await assignToSlot(
        context,
        existingSlot,
        picked,
        exceptSlotForDuplicate: existingSlot,
      )) {
        return null;
      }
      return picked;
    }

    final empty = store.firstEmptySlotIndex;
    if (empty != null) {
      if (!context.mounted) return null;
      if (!await assignToSlot(context, empty, picked)) return null;
      return picked;
    }

    if (store.colorExistsInPalette(picked)) {
      if (context.mounted) showDuplicateSnackBar(context, picked);
      return null;
    }

    if (!context.mounted) return null;
    return _resolveWhenPaletteFull(context, picked: picked, host: host);
  }

  /// Γέμισμα κενής θέσης από κλικ σε κενό τετράγωνο.
  static Future<bool> assignPickedToEmptySlot(
    BuildContext context,
    int slotIndex,
    Color picked,
  ) async {
    return assignToSlot(context, slotIndex, picked);
  }

  /// Καθαρισμός γεμάτης θέσης (παρατεταμένο πάτημα).
  static Future<void> requestClearCustomSlot(
    BuildContext context,
    int slotIndex, {
    DepartmentPaletteHost? host,
  }) async {
    final store = DepartmentPaletteStore.instance;
    await store.ensureLoaded();
    final slotColor = store.customSlots[slotIndex];
    if (slotColor == null) return;

    final affected = departmentsUsingColor(slotColor);
    if (affected.isNotEmpty && context.mounted) {
      final choice = await _showClearInUseDialog(
        context,
        slotColor: slotColor,
        departments: affected,
      );
      if (choice == _ClearSlotChoice.cancel || !context.mounted) return;
      await store.clearCustomSlot(slotIndex);
      if (choice == _ClearSlotChoice.paletteAndDepartments) {
        await _setDepartmentsColor(
          affected,
          kDepartmentDefaultColorHex,
          host: host,
        );
        _notifyEditingDepartmentIfAffected(
          host,
          affected,
          kDepartmentDefaultColorHex,
        );
      }
      return;
    }

    await store.clearCustomSlot(slotIndex);
  }

  static Future<Color?> _resolveWhenPaletteFull(
    BuildContext context, {
    required Color picked,
    DepartmentPaletteHost? host,
  }) async {
    final choice = await showDialog<_FullPaletteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Πλήρης παλέτα'),
        content: const Text(
          'Και τα 8 προσαρμοσμένα χρώματα είναι συμπληρωμένα.\n\n'
          'Θέλετε:',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _FullPaletteChoice.cancel),
            child: const Text('Άκυρο'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, _FullPaletteChoice.departmentOnly),
            child: const Text('Αλλαγή μόνο στο τμήμα'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _FullPaletteChoice.replace),
            child: const Text('Αντικατάσταση'),
          ),
        ],
      ),
    );

    if (choice == null || choice == _FullPaletteChoice.cancel) return null;
    if (choice == _FullPaletteChoice.departmentOnly) return picked;

    if (!context.mounted) return null;
    final slot = await _showPickSlotToReplaceDialog(context, picked: picked);
    if (!context.mounted || slot == null) return null;
    if (!await assignToSlot(
      context,
      slot,
      picked,
      exceptSlotForDuplicate: slot,
    )) {
      return null;
    }
    return picked;
  }

  static Future<_ClearSlotChoice?> _showClearInUseDialog(
    BuildContext context, {
    required Color slotColor,
    required List<DepartmentModel> departments,
  }) {
    final hex = colorToDepartmentHex(slotColor);
    final names = departments.map((d) => '«${d.name}»').join(', ');
    final deptLabel = departments.length == 1
        ? 'στο τμήμα $names'
        : 'στα τμήματα $names';

    return showDialog<_ClearSlotChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Χρώμα σε χρήση'),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: slotColor,
                border: Border.all(
                  color: Theme.of(ctx).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Το χρώμα $hex χρησιμοποιείται $deptLabel.\n\n'
                'Να παραμείνει στα τμήματα ή να αλλάξει και εκεί;',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ClearSlotChoice.cancel),
            child: const Text('Άκυρο'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ClearSlotChoice.paletteOnly),
            child: const Text('Αλλαγή μόνο στην παλέτα'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, _ClearSlotChoice.paletteAndDepartments),
            child: const Text('Αλλαγή και στα τμήματα'),
          ),
        ],
      ),
    );
  }

  static Future<int?> _showPickSlotToReplaceDialog(
    BuildContext context, {
    required Color picked,
  }) async {
    final store = DepartmentPaletteStore.instance;
    await store.ensureLoaded();
    if (!context.mounted) return null;
    final slots = store.customSlots;

    return showDialog<int>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
        title: const Text('Αντικατάσταση χρώματος'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Νέο χρώμα: ${colorToDepartmentHex(picked)}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              const Text('Επιλέξτε ποια θέση να αντικατασταθεί:'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < DepartmentPaletteStore.customSlotCount; i++)
                    if (slots[i] != null)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(ctx, i),
                          borderRadius: BorderRadius.circular(4),
                          child: Tooltip(
                            message: colorToDepartmentHex(slots[i]!),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: slots[i],
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Άκυρο'),
          ),
        ],
        );
      },
    );
  }

  static Future<void> _setDepartmentsColor(
    List<DepartmentModel> departments,
    String hex, {
    DepartmentPaletteHost? host,
  }) async {
    final notifier = host?.directoryNotifier;
    if (notifier != null) {
      for (final d in departments) {
        if (d.id == null) continue;
        await notifier.updateDepartment(d.copyWith(color: hex));
      }
      return;
    }

    final db = await DatabaseHelper.instance.database;
    final dir = DepartmentRepository(db);
    for (final d in departments) {
      if (d.id == null) continue;
      final map = Map<String, dynamic>.from(d.toMap());
      map['color'] = hex;
      await dir.updateDepartment(d.id!, map);
    }
    await LookupService.instance.loadFromDatabase(forceRefresh: true);
  }

  static void _notifyEditingDepartmentIfAffected(
    DepartmentPaletteHost? host,
    List<DepartmentModel> affected,
    String hex,
  ) {
    final editId = host?.editingDepartmentId;
    if (editId == null) return;
    if (!affected.any((d) => d.id == editId)) return;
    host?.onEditingDepartmentColorChanged?.call(hex);
  }
}
