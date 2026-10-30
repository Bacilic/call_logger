import 'package:flutter/material.dart';

import '../../../../../core/utils/search_text_normalizer.dart';
import '../../../models/department_model.dart';

/// Τι διάλεξε ο χρήστης για έναν χώρο: τμήμα **ή** ελεύθερο όνομα.
class RoomIdentity {
  const RoomIdentity.department(DepartmentModel this.department) : name = null;
  const RoomIdentity.freeName(String this.name) : department = null;

  final DepartmentModel? department;
  final String? name;
}

/// Ρωτά τι είναι ο χώρος: τμήμα από τον Κατάλογο, ή ελεύθερο όνομα
/// (διάδρομος, αποθήκη). `null` σε ακύρωση — ο χώρος δεν δημιουργείται.
Future<RoomIdentity?> showFloorPlanRoomIdentityDialog(
  BuildContext context, {
  required List<DepartmentModel> departments,
  required String title,
  int? currentDepartmentId,
  String? currentName,
}) {
  return showDialog<RoomIdentity>(
    context: context,
    builder: (_) => _RoomIdentityDialog(
      departments: departments,
      title: title,
      currentDepartmentId: currentDepartmentId,
      currentName: currentName,
    ),
  );
}

class _RoomIdentityDialog extends StatefulWidget {
  const _RoomIdentityDialog({
    required this.departments,
    required this.title,
    this.currentDepartmentId,
    this.currentName,
  });

  final List<DepartmentModel> departments;
  final String title;
  final int? currentDepartmentId;
  final String? currentName;

  @override
  State<_RoomIdentityDialog> createState() => _RoomIdentityDialogState();
}

class _RoomIdentityDialogState extends State<_RoomIdentityDialog> {
  late bool _freeName = widget.currentName != null;
  final _search = TextEditingController();
  late final _name = TextEditingController(text: widget.currentName ?? '');

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  List<DepartmentModel> get _filtered {
    final q = SearchTextNormalizer.normalizeForSearch(_search.text);
    if (q.isEmpty) return widget.departments;
    return [
      for (final d in widget.departments)
        if (SearchTextNormalizer.normalizeForSearch(d.name).contains(q)) d,
    ];
  }

  void _submitName() {
    final text = _name.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, RoomIdentity.freeName(text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.apartment_outlined),
                  label: Text('Τμήμα'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.edit_outlined),
                  label: Text('Ελεύθερο όνομα'),
                ),
              ],
              selected: {_freeName},
              onSelectionChanged: (v) => setState(() => _freeName = v.first),
            ),
            const SizedBox(height: 12),
            if (_freeName) ...[
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Όνομα χώρου',
                  hintText: 'π.χ. Διάδρομος, Αποθήκη',
                ),
                onSubmitted: (_) => _submitName(),
              ),
            ] else ...[
              TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Αναζήτηση τμήματος',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(child: _departmentList()),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Άκυρο'),
        ),
        if (_freeName)
          FilledButton(onPressed: _submitName, child: const Text('Εντάξει')),
      ],
    );
  }

  Widget _departmentList() {
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(child: Text('Κανένα τμήμα δεν ταιριάζει.'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final d = items[i];
        return ListTile(
          dense: true,
          title: Text(d.name),
          selected: d.id == widget.currentDepartmentId,
          onTap: () => Navigator.pop(context, RoomIdentity.department(d)),
        );
      },
    );
  }
}
