import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/models/app_permission.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/utils/user_facing_error_messages.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/settings_list_conflict_dialog.dart';
import '../../providers/building_catalog_provider.dart';
import '../../providers/department_directory_provider.dart';

/// Οθόνη «Τμήματα» (Κατάλογος → Διάφορα): ο κοινός κατάλογος κτιρίων.
///
/// **Ο κατάλογος είναι ο κύριος, τα τμήματα ακολουθούν.** Η διαγραφή ενός
/// κτιρίου αφήνει χωρίς κτίριο όσα τμήματα το είχαν, και η μετονομασία τα
/// μετονομάζει μαζί — αλλιώς λίστα και δεδομένα θα απέκλιναν σιωπηλά, που
/// είναι ακριβώς το πρόβλημα που λύνει ο κατάλογος.
class DepartmentsSettingsView extends ConsumerStatefulWidget {
  const DepartmentsSettingsView({super.key});

  @override
  ConsumerState<DepartmentsSettingsView> createState() =>
      _DepartmentsSettingsViewState();
}

class _DepartmentsSettingsViewState
    extends ConsumerState<DepartmentsSettingsView> {
  bool _busy = false;

  bool get _canManage =>
      PermissionService.instance.can(AppPermission.manageBuildingCatalog);

  /// Κάθε αλλαγή του καταλόγου περνά από εδώ: διαβάζει την αφετηρία μόλις πριν
  /// γράψει (ώστε ο φρουρός να κρίνει φρέσκα δεδομένα), γράφει, και ξεπλένει
  /// τα caches που δείχνουν κτίρια.
  ///
  /// Το [afterSave] τρέχει **μόνο** αν η εγγραφή του καταλόγου πέτυχε: εκεί
  /// ζει η ενημέρωση των τμημάτων, ώστε να μη γίνει ποτέ ενώ ο κατάλογος
  /// έμεινε ανέγγιχτος.
  Future<void> _mutate(
    List<String> Function(List<String> current) change, {
    Future<String?> Function()? afterSave,
    String? successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final storedRaw = await readBuildingCatalogRaw();
      final current = await ref.read(buildingCatalogProvider.future);
      final next = sortBuildings(change(List<String>.from(current)));
      if (!mounted) return;

      final saved = await saveSettingsListWithConflictPrompt(
        context,
        listLabel: 'λίστα κτιρίων',
        save: ({required force}) => writeBuildingCatalog(
          next,
          expected: force ? null : effectiveBuildingCatalogText(storedRaw),
        ),
      );
      if (!saved) {
        _refresh();
        if (!mounted) return;
        _say(
          'Η αποθήκευση ακυρώθηκε — η λίστα ανανεώθηκε με τα τρέχοντα '
          'κτίρια. Ελέγξτε τα και δοκιμάστε ξανά.',
        );
        return;
      }

      final extra = afterSave == null ? null : await afterSave();
      _refresh();
      if (!mounted) return;
      final message = [?successMessage, ?extra].join(' ');
      if (message.isNotEmpty) _say(message);
    } catch (e) {
      if (!mounted) return;
      _say('Αποτυχία: ${humanizeUserFacingError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refresh() {
    ref.invalidate(buildingUsageProvider);
    ref.invalidate(buildingCatalogProvider);
    ref.invalidate(departmentDirectoryProvider);
  }

  void _say(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _add() async {
    final catalog = await ref.read(buildingCatalogProvider.future);
    if (!mounted) return;
    final name = await _askBuildingName(
      title: 'Προσθήκη κτιρίου',
      actionLabel: 'Προσθήκη',
      catalog: catalog,
    );
    if (name == null) return;
    await _mutate(
      (current) => [...current, name],
      successMessage: 'Προστέθηκε το κτίριο «$name».',
    );
  }

  Future<void> _rename(String building) async {
    final catalog = await ref.read(buildingCatalogProvider.future);
    if (!mounted) return;
    final name = await _askBuildingName(
      title: 'Μετονομασία κτιρίου',
      actionLabel: 'Μετονομασία',
      initial: building,
      catalog: catalog,
      allowSelf: building,
    );
    if (name == null || name == building) return;
    await _mutate(
      (current) => [
        for (final b in current)
          if (b == building) name else b,
      ],
      afterSave: () async {
        final db = await DatabaseHelper.instance.database;
        final touched = await DepartmentRepository(
          db,
        ).renameBuildingInDepartments(from: building, to: name);
        return touched == 0
            ? null
            : 'Ενημερώθηκαν $touched ${touched == 1 ? 'τμήμα' : 'τμήματα'}.';
      },
      successMessage: 'Το «$building» έγινε «$name».',
    );
  }

  Future<void> _delete(String building, int usage) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Διαγραφή κτιρίου'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          content: Text(
            usage == 0
                ? 'Να διαγραφεί το κτίριο «$building» από τη λίστα;\n\n'
                      'Δεν το χρησιμοποιεί κανένα τμήμα.'
                : 'Να διαγραφεί το κτίριο «$building» από τη λίστα;\n\n'
                      '$usage ${usage == 1 ? 'τμήμα θα μείνει' : 'τμήματα θα μείνουν'} '
                      'χωρίς κτίριο, και θα εμφανίζονται στον «Έλεγχο '
                      'δεδομένων» των Κανόνων Επικύρωσης μέχρι να τους δοθεί '
                      'καινούριο.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Διαγραφή'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    await _mutate(
      (current) => [
        for (final b in current)
          if (b != building) b,
      ],
      afterSave: () async {
        final db = await DatabaseHelper.instance.database;
        final cleared = await DepartmentRepository(
          db,
        ).clearBuildingFromDepartments(building);
        return cleared == 0
            ? null
            : '$cleared ${cleared == 1 ? 'τμήμα έμεινε' : 'τμήματα έμειναν'} '
                  'χωρίς κτίριο.';
      },
      successMessage: 'Διαγράφηκε το κτίριο «$building».',
    );
  }

  /// Μικρή φόρμα ονόματος με τον έλεγχο διπλότυπου μέσα της.
  ///
  /// Ο έλεγχος αγνοεί αλφάβητο και τόνους: «Β» και «B» είναι το ίδιο κτίριο,
  /// και το να μπουν και τα δύο στη λίστα θα αναπαρήγαγε το πρόβλημα.
  Future<String?> _askBuildingName({
    required String title,
    required String actionLabel,
    required List<String> catalog,
    String? initial,
    String? allowSelf,
  }) {
    final controller = TextEditingController(text: initial ?? '');
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: Text(title),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Όνομα κτιρίου',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final name = (value ?? '').trim();
                  if (name.isEmpty) return 'Δώστε όνομα κτιρίου.';
                  final clash = matchBuildingInCatalog(name, catalog);
                  if (clash == null || clash == allowSelf) return null;
                  return clash == name
                      ? 'Υπάρχει ήδη στη λίστα.'
                      : 'Υπάρχει ήδη ως «$clash» — είναι το ίδιο κτίριο.';
                },
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.of(ctx).pop(controller.text.trim());
                  }
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(ctx).pop(controller.text.trim());
                }
              },
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(buildingCatalogProvider);
    final usageAsync = ref.watch(buildingUsageProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: catalogAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SectionCard(
              icon: Icons.error_outline,
              title: 'Κτίρια',
              child: Text('Αποτυχία φόρτωσης: ${humanizeUserFacingError(e)}'),
            ),
            data: (catalog) => _buildCard(
              catalog,
              usageAsync.asData?.value ?? BuildingUsage.empty,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(List<String> catalog, BuildingUsage usage) {
    final theme = Theme.of(context);
    final withoutBuilding = _departmentsWithoutBuilding(usage);

    return SectionCard(
      icon: Icons.apartment_outlined,
      title: 'Κτίρια',
      trailing: _canManage
          ? FilledButton.tonalIcon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Προσθήκη'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Από αυτή τη λίστα διαλέγεις κτίριο στη φόρμα τμήματος και στη '
            'μεταφορά από τη Λάμπα. Η διαγραφή ενός κτιρίου αφήνει χωρίς '
            'κτίριο τα τμήματά του· η μετονομασία τα ενημερώνει όλα μαζί.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (catalog.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Δεν υπάρχει κανένα κτίριο. Πρόσθεσε ένα για να μπορούν τα '
                'τμήματα να ανατεθούν σε κτίριο.',
              ),
            )
          else
            for (final building in catalog)
              _BuildingRow(
                name: building,
                usage: usage.countFor(building),
                enabled: _canManage && !_busy,
                onRename: () => _rename(building),
                onDelete: () => _delete(building, usage.countFor(building)),
              ),
          if (withoutBuilding != null) ...[
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    withoutBuilding,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Πόσα ενεργά τμήματα δεν έχουν κτίριο — ή `null` όταν δεν λείπει κανένα.
  String? _departmentsWithoutBuilding(BuildingUsage usage) {
    final missing = usage.withoutBuilding;
    if (missing == 0) return null;
    return '$missing ${missing == 1 ? 'τμήμα δεν έχει' : 'τμήματα δεν έχουν'} '
        'κτίριο. Τα βρίσκεις ονομαστικά στον «Έλεγχο δεδομένων» των Κανόνων '
        'Επικύρωσης.';
  }
}

class _BuildingRow extends StatelessWidget {
  const _BuildingRow({
    required this.name,
    required this.usage,
    required this.enabled,
    required this.onRename,
    required this.onDelete,
  });

  final String name;
  final int usage;
  final bool enabled;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
          Text(
            usage == 0
                ? 'κανένα τμήμα'
                : '$usage ${usage == 1 ? 'τμήμα' : 'τμήματα'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: 'Μετονομασία',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: enabled ? onRename : null,
          ),
          IconButton(
            tooltip: 'Διαγραφή',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: enabled ? onDelete : null,
          ),
        ],
      ),
    );
  }
}
