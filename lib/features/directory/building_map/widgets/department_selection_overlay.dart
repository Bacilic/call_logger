import 'package:flutter/material.dart';

import '../../../../core/models/building_map_floor.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../models/department_model.dart';
import 'building_map_floor_menu_button.dart';

/// Πλέγμα (HUD) επιλογής τμήματος πάνω από τον καμβά· αναζήτηση και ομαδοποίηση.
class DepartmentSelectionOverlay extends StatefulWidget {
  const DepartmentSelectionOverlay({
    super.key,
    required this.activeDepartments,
    required this.floors,
    required this.onClose,
    required this.onSelectDepartment,
  });

  final List<DepartmentModel> activeDepartments;
  final List<BuildingMapFloor> floors;
  final VoidCallback onClose;
  final void Function(int departmentId) onSelectDepartment;

  @override
  State<DepartmentSelectionOverlay> createState() =>
      _DepartmentSelectionOverlayState();
}

class _DepartmentSelectionOverlayState extends State<DepartmentSelectionOverlay> {
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;
  bool _groupByFloor = true;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scrollController = ScrollController();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _searchBlob(DepartmentModel d, Map<int, BuildingMapFloor> floorById) {
    final parts = <String>[d.name, d.groupName ?? '', d.building ?? ''];
    final fid = d.floorId;
    if (fid != null) {
      final fl = floorById[fid];
      if (fl != null) {
        parts.add(buildingMapFloorDisplayLabel(fl));
      } else {
        parts.add('$fid');
      }
    }
    return parts.join(' ');
  }

  List<DepartmentModel> _filtered() {
    final qRaw = _searchController.text;
    final qNorm = SearchTextNormalizer.normalizeForSearch(qRaw);
    final floorById = {for (final f in widget.floors) f.id: f};
    return widget.activeDepartments.where((d) {
      if (d.id == null) return false;
      return SearchTextNormalizer.matchesNormalizedQuery(
        _searchBlob(d, floorById),
        qNorm,
      );
    }).toList();
  }

  List<({String title, List<DepartmentModel> deps})> _sections(
    List<DepartmentModel> filtered,
  ) {
    final floors = widget.floors;
    final floorById = {for (final f in floors) f.id: f};
    if (_groupByFloor) {
      final buckets = <int?, List<DepartmentModel>>{};
      for (final d in filtered) {
        buckets.putIfAbsent(d.floorId, () => []).add(d);
      }
      for (final entry in buckets.entries) {
        entry.value.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      }
      final ids = buckets.keys.whereType<int>().toList()
        ..sort((a, b) {
          final fa = floorById[a];
          final fb = floorById[b];
          final oa = fa?.sortOrder ?? 0;
          final ob = fb?.sortOrder ?? 0;
          if (oa != ob) return oa.compareTo(ob);
          return a.compareTo(b);
        });
      final out = <({String title, List<DepartmentModel> deps})>[];
      for (final id in ids) {
        final f = floorById[id];
        final title =
            f != null ? buildingMapFloorDisplayLabel(f) : 'Όροφος #$id';
        out.add((title: title, deps: buckets[id]!));
      }
      if (buckets.containsKey(null)) {
        out.add((title: 'Λοιπά', deps: buckets[null]!));
      }
      return out;
    }

    final buckets = <String?, List<DepartmentModel>>{};
    for (final d in filtered) {
      final g = d.groupName?.trim();
      final key = (g == null || g.isEmpty) ? null : g;
      buckets.putIfAbsent(key, () => []).add(d);
    }
    for (final entry in buckets.entries) {
      entry.value.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    final keys = buckets.keys.whereType<String>().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final out = <({String title, List<DepartmentModel> deps})>[];
    for (final k in keys) {
      out.add((title: k, deps: buckets[k]!));
    }
    if (buckets.containsKey(null)) {
      out.add((title: 'Λοιπά', deps: buckets[null]!));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered();
    final sections = _sections(filtered);

    return Material(
      color: Colors.black54,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () {},
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 920,
                    maxHeight: 640,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const cols = 5;
                      return Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Επιλογή τμήματος',
                                      style: theme.textTheme.titleLarge,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Κλείσιμο',
                                    onPressed: widget.onClose,
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  labelText: 'Αναζήτηση',
                                  hintText: 'Όνομα, ομάδα, όροφος…',
                                  prefixIcon: Icon(Icons.search),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Ανά Όροφο'),
                                  ),
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Ανά Ομάδα'),
                                  ),
                                ],
                                selected: {_groupByFloor},
                                onSelectionChanged: (s) {
                                  setState(() => _groupByFloor = s.first);
                                },
                              ),
                            ),
                            Expanded(
                              child: filtered.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Δεν βρέθηκαν τμήματα.',
                                        style: theme.textTheme.bodyLarge,
                                      ),
                                    )
                                  : Scrollbar(
                                      controller: _scrollController,
                                      thumbVisibility: true,
                                      child: CustomScrollView(
                                        controller: _scrollController,
                                        primary: false,
                                        slivers: [
                                          for (final sec in sections) ...[
                                            SliverToBoxAdapter(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                  16,
                                                  12,
                                                  16,
                                                  8,
                                                ),
                                                child: Text(
                                                  sec.title,
                                                  style: theme
                                                      .textTheme.titleSmall
                                                      ?.copyWith(
                                                    color: theme
                                                        .colorScheme.primary,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SliverPadding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
                                              sliver: SliverGrid(
                                                gridDelegate:
                                                    SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: cols,
                                                  mainAxisSpacing: 6,
                                                  crossAxisSpacing: 6,
                                                  childAspectRatio: 2.4,
                                                ),
                                                delegate:
                                                    SliverChildBuilderDelegate(
                                                  (context, index) {
                                                    final d = sec.deps[index];
                                                    final mapped = d.isMapped;
                                                    return Opacity(
                                                      opacity: mapped ? 0.52 : 1,
                                                      child: Card(
                                                        margin:
                                                            EdgeInsets.zero,
                                                        child: InkWell(
                                                          onTap: () => widget
                                                              .onSelectDepartment(
                                                            d.id!,
                                                          ),
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 6,
                                                              vertical: 4,
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Text(
                                                                  d.name,
                                                                  maxLines: 2,
                                                                  softWrap: true,
                                                                  style: theme
                                                                      .textTheme
                                                                      .bodyMedium
                                                                      ?.copyWith(
                                                                    fontStyle:
                                                                        mapped
                                                                            ? FontStyle
                                                                                .italic
                                                                            : FontStyle
                                                                                .normal,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  childCount: sec.deps.length,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
