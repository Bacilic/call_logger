import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/directory_repository.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import '../../screens/widgets/department_color_palette.dart';
import '../../../floor_map/services/floor_color_assignment_service.dart';
import '../controllers/building_map_controller.dart';
import '../providers/building_map_providers.dart';
import 'building_map_fill_color_dialog.dart';

/// Ύψος γραμμής εργαλείων (checkbox κ.λπ.) + διάκενο πριν την επεκτεινόμενη λίστα.
const double _kFloorDeptToolbarBlockHeight = 48 + 6;

/// Προσεγγιστικό ύψος μιας γραμμής τμήματος (compact εικονίδια, isDense).
const double _kApproxFloorDeptRowHeight = 44;

/// Εκτίμηση αν η λίστα θα χρειαζόταν κύλιση χωρίς πεδίο αναζήτησης (ίδια περιοχή με τη μπάρα κύλισης).
bool _floorDeptListWouldScrollWithoutSearch({
  required int departmentCount,
  required double contentMaxHeight,
}) {
  if (departmentCount <= 0) return false;
  final listViewport = contentMaxHeight - _kFloorDeptToolbarBlockHeight;
  if (listViewport <= 0) return true;
  return departmentCount * _kApproxFloorDeptRowHeight > listViewport;
}

/// Λειτουργία διαλόγου: μόνο προβολή/απόκρυψη, ή πλήρης διαχείριση (όνομα, χρώμα,
/// μαζική αφαίρεση από χάρτη).
enum BuildingMapFloorDepartmentsDialogMode { view, edit }

/// Κουμπί εργαλειοθήκης «Τμήματα ορόφου» με badge αριθμού κρυμμένων για το τρέχον
/// φύλλο και αλλαγή εικονιδίου. Απενεργοποιείται όταν δεν υπάρχει επιλεγμένο φύλλο.
class BuildingMapFloorDepartmentsButton extends ConsumerWidget {
  const BuildingMapFloorDepartmentsButton({
    super.key,
    required this.mode,
    this.floorTitle,
  });

  final BuildingMapFloorDepartmentsDialogMode mode;
  /// Προαιρετικός τίτλος που εμφανίζεται στον διάλογο (π.χ. ετικέτα φύλλου). Αν είναι
  /// null, εμφανίζεται «Φύλλο #id».
  final String? floorTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheetId = ref.watch(buildingMapSelectedSheetIdProvider);
    final deptState = ref.watch(departmentDirectoryProvider);
    int hiddenCount = 0;
    int totalOnSheet = 0;
    if (sheetId != null) {
      final sheetStr = sheetId.toString();
      for (final d in deptState.allDepartments) {
        if (d.isDeleted) continue;
        if ((d.mapFloor ?? '') != sheetStr) continue;
        totalOnSheet++;
        if (d.isHiddenOnMap) hiddenCount++;
      }
    }
    final hasHidden = hiddenCount > 0;
    final enabled = sheetId != null && totalOnSheet > 0;
    final icon = Icon(
      hasHidden
          ? Icons.visibility_off_outlined
          : Icons.visibility_outlined,
    );

    final button = IconButton(
      tooltip: hasHidden
          ? 'Τμήματα ορόφου ($hiddenCount κρυμμένα)'
          : 'Τμήματα ορόφου',
      onPressed: !enabled
          ? null
          : () async {
              await showBuildingMapFloorDepartmentsDialog(
                context,
                ref: ref,
                currentSheetId: sheetId,
                mode: mode,
                floorTitle: floorTitle ?? 'Φύλλο #$sheetId',
              );
            },
      icon: hasHidden
          ? Badge.count(
              count: hiddenCount,
              child: icon,
            )
          : icon,
    );
    return button;
  }
}

/// Διάλογος «Τμήματα ορόφου». Εμφανίζει μόνο όσα τμήματα είναι χαρτογραφημένα
/// στο [currentSheetId]. Ρίχνει άμεσα αλλαγές μέσω [DirectoryRepository].
Future<void> showBuildingMapFloorDepartmentsDialog(
  BuildContext context, {
  required WidgetRef ref,
  required int currentSheetId,
  required BuildingMapFloorDepartmentsDialogMode mode,
  required String floorTitle,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _BuildingMapFloorDepartmentsDialog(
      parentRef: ref,
      currentSheetId: currentSheetId,
      mode: mode,
      floorTitle: floorTitle,
    ),
  );
}

class _BuildingMapFloorDepartmentsDialog extends ConsumerStatefulWidget {
  const _BuildingMapFloorDepartmentsDialog({
    required this.parentRef,
    required this.currentSheetId,
    required this.mode,
    required this.floorTitle,
  });

  final WidgetRef parentRef;
  final int currentSheetId;
  final BuildingMapFloorDepartmentsDialogMode mode;
  final String floorTitle;

  @override
  ConsumerState<_BuildingMapFloorDepartmentsDialog> createState() =>
      _BuildingMapFloorDepartmentsDialogState();
}

class _BuildingMapFloorDepartmentsDialogState
    extends ConsumerState<_BuildingMapFloorDepartmentsDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _floorDeptListScrollController =
      ScrollController();
  final Set<int> _selected = <int>{};
  int? _renamingId;
  TextEditingController? _renameCtrl;
  FocusNode? _renameFocus;

  bool get _isEdit =>
      widget.mode == BuildingMapFloorDepartmentsDialogMode.edit;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _floorDeptListScrollController.dispose();
    _renameCtrl?.dispose();
    _renameFocus?.dispose();
    super.dispose();
  }

  List<DepartmentModel> _departmentsForSheet() {
    final all = ref.watch(departmentDirectoryProvider).allDepartments;
    final sheetStr = widget.currentSheetId.toString();
    final list = all
        .where(
          (d) =>
              !d.isDeleted &&
              (d.mapFloor ?? '') == sheetStr &&
              d.id != null,
        )
        .toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return list;
  }

  List<DepartmentModel> _filtered(
    List<DepartmentModel> list, {
    String? queryText,
  }) {
    final raw = queryText ?? _searchCtrl.text;
    final qNorm = SearchTextNormalizer.normalizeForSearch(raw);
    if (qNorm.isEmpty) return list;
    return list
        .where(
          (d) => SearchTextNormalizer.matchesNormalizedQuery(
            '${d.name} ${d.groupName ?? ''} ${d.building ?? ''}',
            qNorm,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _setHidden(DepartmentModel d, bool hidden) async {
    if (d.id == null) return;
    final db = await DatabaseHelper.instance.database;
    await DirectoryRepository(db).updateDepartment(d.id!, {
      'map_hidden': hidden ? 1 : 0,
    });
    await ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    if (mounted) setState(() {});
  }

  Future<void> _setHiddenBulk(Iterable<int> ids, bool hidden) async {
    if (ids.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final repo = DirectoryRepository(db);
    for (final id in ids) {
      await repo.updateDepartment(id, {'map_hidden': hidden ? 1 : 0});
    }
    await ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    if (mounted) setState(() {});
  }

  Future<void> _changeColor(DepartmentModel d) async {
    if (d.id == null) return;
    final initial =
        tryParseDepartmentHex(d.color) ?? const Color(0xFF1976D2);
    final picked =
        await showBuildingMapFillColorPicker(context, initialColor: initial);
    if (!mounted || picked == null) return;
    await ref
        .read(buildingMapControllerProvider)
        .applyDepartmentMapFillColor(
          context: context,
          dept: d,
          floorId: widget.currentSheetId,
          newColor: picked,
        );
    if (mounted) setState(() {});
  }

  void _beginRename(DepartmentModel d) {
    if (d.id == null) return;
    _renameCtrl?.dispose();
    _renameFocus?.dispose();
    _renamingId = d.id;
    _renameCtrl = TextEditingController(text: d.displayName);
    _renameFocus = FocusNode();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _renameFocus?.requestFocus();
      _renameCtrl?.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _renameCtrl?.text.length ?? 0,
      );
    });
  }

  Future<void> _commitRename(DepartmentModel d) async {
    final ctrl = _renameCtrl;
    if (ctrl == null || d.id == null) return;
    final edited = ctrl.text;
    await ref
        .read(buildingMapControllerProvider)
        .saveDepartmentMapDisplayName(
          context: context,
          departmentId: d.id!,
          canonicalDepartmentName: d.name,
          editedText: edited,
        );
    _cancelRename();
  }

  void _cancelRename() {
    _renameCtrl?.dispose();
    _renameFocus?.dispose();
    _renameCtrl = null;
    _renameFocus = null;
    _renamingId = null;
    if (mounted) setState(() {});
  }

  Future<void> _bulkRemoveFromMap(List<DepartmentModel> selected) async {
    if (selected.isEmpty) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αφαίρεση από τον χάρτη'),
        content: Text(
          'Να αφαιρεθούν ${selected.length} τμήματα από αυτό το φύλλο κατόψης; '
          'Η γεωμετρία και το χρώμα χάρτη θα μηδενιστούν (οι υπόλοιπες πληροφορίες τμήματος διατηρούνται).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Αφαίρεση'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final db = await DatabaseHelper.instance.database;
    final repo = DirectoryRepository(db);
    final fid = widget.currentSheetId;
    for (final d in selected) {
      if (d.id == null) continue;
      final removedColor = tryParseDepartmentHex(d.color);
      await repo.updateDepartment(
        d.id!,
        DirectoryRepository.clearedBuildingMapPlacementColumns(
          clearFloorId: true,
          clearDepartmentHex: true,
        ),
      );
      if (removedColor != null) {
        FloorColorAssignmentService.instance.removeColorFromFloor(
          fid,
          removedColor,
        );
      }
    }
    await ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    if (!mounted) return;
    _selected.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Αφαιρέθηκαν ${selected.length} τμήματα από αυτό το φύλλο.',
        ),
      ),
    );
  }

  Widget _buildRow(DepartmentModel d) {
    final theme = Theme.of(context);
    final hidden = d.isHiddenOnMap;
    final color = tryParseDepartmentHex(d.color);
    final isRenaming = _isEdit && _renamingId == d.id;

    Widget nameWidget;
    if (isRenaming && _renameCtrl != null && _renameFocus != null) {
      nameWidget = TextField(
        controller: _renameCtrl,
        focusNode: _renameFocus,
        style: theme.textTheme.bodyMedium,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          hintText: 'Κενό = επαναφορά στο όνομα τμήματος',
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _commitRename(d),
      );
    } else {
      final hasCustom =
          (d.mapCustomName?.trim().isNotEmpty ?? false);
      nameWidget = Tooltip(
        message: hasCustom ? 'Επωνυμία χάρτη: ${d.displayName}\nΌνομα τμήματος: ${d.name}' : d.name,
        child: Text(
          d.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontStyle: hasCustom ? FontStyle.italic : FontStyle.normal,
            color: hidden
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
          ),
        ),
      );
    }

    final selectable = _isEdit && !isRenaming;
    final checked = _selected.contains(d.id);

    return Container(
      decoration: BoxDecoration(
        color: hidden ? theme.colorScheme.surfaceContainerLow : null,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          if (selectable)
            Checkbox(
              visualDensity: VisualDensity.compact,
              value: checked,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(d.id!);
                  } else {
                    _selected.remove(d.id);
                  }
                });
              },
            )
          else
            const SizedBox(width: 40),
          IconButton(
            tooltip: hidden ? 'Εμφάνιση στον χάρτη' : 'Απόκρυψη από τον χάρτη',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: hidden
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
            onPressed: () => _setHidden(d, !hidden),
          ),
          Expanded(child: nameWidget),
          if (_isEdit && !isRenaming)
            IconButton(
              tooltip: 'Μετονομασία επωνυμίας χάρτη',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _beginRename(d),
            ),
          if (_isEdit && isRenaming) ...[
            IconButton(
              tooltip: 'Επιβεβαίωση',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.check),
              onPressed: () => _commitRename(d),
            ),
            IconButton(
              tooltip: 'Άκυρο',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close),
              onPressed: _cancelRename,
            ),
          ],
          const SizedBox(width: 4),
          Tooltip(
            message: _isEdit
                ? 'Αλλαγή χρώματος περιοχής'
                : (color != null
                    ? colorToDepartmentHex(color)
                    : 'Χωρίς χρώμα'),
            child: InkWell(
              onTap: _isEdit ? () => _changeColor(d) : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color ?? theme.colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: color == null
                    ? Icon(
                        Icons.help_outline,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = _departmentsForSheet();
    final hiddenCount = all.where((d) => d.isHiddenOnMap).length;

    final allVisible = all.isNotEmpty && all.every((d) => !d.isHiddenOnMap);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Τμήματα ορόφου – ${widget.floorTitle}',
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Κλείσιμο',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 520,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showSearch = _floorDeptListWouldScrollWithoutSearch(
              departmentCount: all.length,
              contentMaxHeight: constraints.maxHeight,
            );
            final filtered = _filtered(
              all,
              queryText: showSearch ? null : '',
            );
            final filteredIds = filtered
                .where((d) => d.id != null)
                .map((d) => d.id!)
                .toList(growable: false);
            final allFilteredSelected = filteredIds.isNotEmpty &&
                filteredIds.every((id) => _selected.contains(id));
            final bool? selectionMasterValue = filteredIds.isEmpty
                ? false
                : (allFilteredSelected
                    ? true
                    : (filteredIds.every((id) => !_selected.contains(id))
                        ? false
                        : null));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSearch) ...[
                  TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Αναζήτηση',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    if (_isEdit)
                      Tooltip(
                        message: filteredIds.isEmpty
                            ? 'Επιλογή τμημάτων'
                            : (allFilteredSelected
                                ? 'Αποεπιλογή όλων στη λίστα'
                                : 'Επιλογή όλων στη λίστα'),
                        child: Checkbox(
                          tristate: true,
                          visualDensity: VisualDensity.compact,
                          value: selectionMasterValue,
                          onChanged: filteredIds.isEmpty
                              ? null
                              : (_) {
                                  setState(() {
                                    if (allFilteredSelected) {
                                      for (final id in filteredIds) {
                                        _selected.remove(id);
                                      }
                                    } else {
                                      for (final id in filteredIds) {
                                        _selected.add(id);
                                      }
                                    }
                                  });
                                },
                        ),
                      ),
                    Tooltip(
                      message: allVisible
                          ? 'Απόκρυψη όλων από τον χάρτη'
                          : 'Εμφάνιση όλων στον χάρτη',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: all.isEmpty
                            ? null
                            : () async {
                                final targetHidden = allVisible;
                                await _setHiddenBulk(
                                  all.map((d) => d.id!),
                                  targetHidden,
                                );
                              },
                        icon: Icon(
                          allVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: all.isEmpty
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Text(
                      all.isEmpty
                          ? 'Κανένα τμήμα στο φύλλο'
                          : '${all.length} τμήματα · $hiddenCount κρυμμένα',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    if (_isEdit)
                      TextButton.icon(
                        onPressed: _selected.isEmpty
                            ? null
                            : () {
                                final picked = all
                                    .where((d) => _selected.contains(d.id))
                                    .toList(growable: false);
                                _bulkRemoveFromMap(picked);
                              },
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: Text(
                          _selected.isEmpty
                              ? 'Αφαίρεση από χάρτη'
                              : 'Αφαίρεση ${_selected.length} από χάρτη',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            all.isEmpty
                                ? 'Δεν υπάρχουν τμήματα χαρτογραφημένα σε αυτό το φύλλο.'
                                : 'Κανένα αποτέλεσμα για την αναζήτηση.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      : Scrollbar(
                          controller: _floorDeptListScrollController,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _floorDeptListScrollController,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => _buildRow(filtered[i]),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Κλείσιμο'),
        ),
      ],
    );
  }
}
