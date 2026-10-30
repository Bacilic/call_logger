import 'package:flutter/material.dart';

import '../../../../../core/models/floor_plan_placement.dart';
import '../../../../../core/utils/search_text_normalizer.dart';
import '../floor_plan_objects.dart';
import 'floor_plan_symbol_painter.dart';

/// Το πάνελ «Τοποθέτηση»: υπάλληλοι, τηλέφωνα και εξοπλισμός του Καταλόγου,
/// έτοιμοι να συρθούν στον χάρτη (ή κλικ εδώ και κλικ στον χάρτη).
///
/// Από προεπιλογή δείχνει όσους ανήκουν σε τμήματα **αυτού του ορόφου**· ο
/// διακόπτης τα ανοίγει όλα. Δίπλα σε όποιον έχει ήδη θέση φαίνεται ● και
/// σε ποιον όροφο.
class FloorPlanPlacementPanel extends StatefulWidget {
  const FloorPlanPlacementPanel({
    super.key,
    required this.entries,
    required this.placements,
    required this.floorDepartmentIds,
    required this.departmentName,
    required this.floorLabel,
    required this.armed,
    required this.onArm,
  });

  final List<FloorPlanCatalogEntry> entries;

  /// Οι θέσεις όλων των ορόφων.
  final List<FloorPlanPlacement> placements;

  /// Τα τμήματα που ανήκουν στον όροφο που σχεδιάζεται.
  final Set<int> floorDepartmentIds;
  final String? Function(int departmentId) departmentName;
  final String Function(int floorId) floorLabel;

  /// Η εγγραφή που περιμένει κλικ στον χάρτη· `null` όταν καμία.
  final FloorPlanCatalogEntry? armed;
  final void Function(FloorPlanCatalogEntry? entry) onArm;

  @override
  State<FloorPlanPlacementPanel> createState() =>
      _FloorPlanPlacementPanelState();
}

class _FloorPlanPlacementPanelState extends State<FloorPlanPlacementPanel> {
  FloorPlanPlacementType _type = FloorPlanPlacementType.user;
  final _search = TextEditingController();
  bool _floorOnly = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<FloorPlanCatalogEntry> get _visible {
    final query = SearchTextNormalizer.normalizeForSearch(_search.text.trim());
    return [
      for (final e in widget.entries)
        if (e.type == _type &&
            (!_floorOnly ||
                e.departmentIds.any(widget.floorDepartmentIds.contains)) &&
            (query.isEmpty ||
                SearchTextNormalizer.normalizeForSearch(e.label)
                    .contains(query)))
          e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final floorsOf = <(FloorPlanPlacementType, int), List<int>>{};
    for (final p in widget.placements) {
      (floorsOf[(p.type, p.entityId)] ??= []).add(p.floorId);
    }
    final visible = _visible;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Τοποθέτηση', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<FloorPlanPlacementType>(
            showSelectedIcon: false,
            // Μικρότερα γράμματα, ώστε κάθε καρτέλα να χωρά σε μία γραμμή.
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            segments: const [
              ButtonSegment(
                value: FloorPlanPlacementType.user,
                label: Text('Υπάλληλοι'),
              ),
              ButtonSegment(
                value: FloorPlanPlacementType.phone,
                label: Text('Τηλέφωνα'),
              ),
              ButtonSegment(
                value: FloorPlanPlacementType.equipment,
                label: Text('Εξοπλισμός'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Αναζήτηση',
            ),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Μόνο τμήματα του ορόφου'),
            value: _floorOnly,
            onChanged: (v) => setState(() => _floorOnly = v),
          ),
          if (widget.armed case final armed?)
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                dense: true,
                title: Text('Κλικ στον χάρτη για «${armed.label}»'),
                trailing: IconButton(
                  tooltip: 'Ακύρωση',
                  onPressed: () => widget.onArm(null),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          const Divider(height: 8),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      _floorOnly
                          ? 'Κανείς σε τμήματα αυτού του ορόφου.\n'
                                'Κλείστε τον διακόπτη για όλο τον Κατάλογο.'
                          : 'Κανένα αποτέλεσμα.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) =>
                        _row(visible[i], floorsOf[visible[i].key] ?? const []),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            'Σύρετε στον χάρτη, ή κλικ εδώ και κλικ στον χάρτη.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _row(FloorPlanCatalogEntry entry, List<int> floors) {
    final symbol = floorPlanPlacementSymbol(entry.type);
    final departments = [
      for (final id in entry.departmentIds) ?widget.departmentName(id),
    ]..sort();
    final placedAt = {for (final f in floors) widget.floorLabel(f)}.toList()
      ..sort();
    final tile = ListTile(
      dense: true,
      selected: widget.armed?.key == entry.key,
      leading: FloorPlanSymbolIcon(symbol, size: 28),
      title: Text(entry.label),
      subtitle: departments.isEmpty ? null : Text(departments.join(', ')),
      trailing: placedAt.isEmpty
          ? null
          : Tooltip(
              message: 'Έχει θέση: ${placedAt.join(', ')}',
              child: const Icon(Icons.circle, size: 12, color: Colors.green),
            ),
      onTap: () => widget.onArm(entry),
    );
    return Draggable<FloorPlanCatalogEntry>(
      data: entry,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: FloorPlanSymbolIcon(symbol, size: 36),
        ),
      ),
      child: tile,
    );
  }
}
