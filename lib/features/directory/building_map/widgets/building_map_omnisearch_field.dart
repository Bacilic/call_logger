import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/omnisearch_service.dart';
import '../controllers/building_map_omnisearch_controller.dart';
import '../providers/building_map_providers.dart';

class BuildingMapOmnisearchField extends ConsumerStatefulWidget {
  const BuildingMapOmnisearchField({
    super.key,
    required this.enabled,
    required this.search,
    required this.controller,
    required this.focusNode,
    required this.onResolveEntity,
  });

  final bool enabled;

  /// Μόνο η αναζήτηση — το πεδίο δεν χρειάζεται τα υπόλοιπα repositories.
  final BuildingMapOmnisearch search;

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Ρητός τύπος: το πεδίο παραδίδει ΜΟΝΟ αποτελέσματα αναζήτησης.
  final Future<void> Function(BuildingMapOmnisearchHit hit) onResolveEntity;

  @override
  ConsumerState<BuildingMapOmnisearchField> createState() =>
      _BuildingMapOmnisearchFieldState();
}

class _BuildingMapOmnisearchFieldState
    extends ConsumerState<BuildingMapOmnisearchField> {
  late final BuildingMapOmnisearchController _omnisearch =
      BuildingMapOmnisearchController(search: widget.search);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant BuildingMapOmnisearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    if (oldWidget.search != widget.search) {
      _omnisearch.search = widget.search;
    }
  }

  @override
  void dispose() {
    _omnisearch.dispose();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  /// Μόνο καθαρισμός της επισήμανσης στον χάρτη· η αναζήτηση ζει στο
  /// [RawAutocomplete.optionsBuilder] ώστε το αποτέλεσμα να αντιστοιχεί πάντα
  /// στο κείμενο που ρωτήθηκε.
  void _onTextChanged() {
    if (widget.controller.text.trim().isNotEmpty) return;
    ref.read(buildingMapSearchRevealedDepartmentIdProvider.notifier).clear();
    ref.read(buildingMapSearchUnresolvedNoticeProvider.notifier).clear();
  }

  Future<Iterable<BuildingMapOmnisearchHit>> _optionsFor(String text) async {
    if (!widget.enabled) return const [];
    final hits = await _omnisearch.query(text);
    // Null = το αίτημα ξεπεράστηκε· το RawAutocomplete απορρίπτει ούτως ή άλλως
    // τα αποτελέσματα παλιότερης πληκτρολόγησης.
    return hits ?? const [];
  }

  /// Enter ή κουμπί αναζήτησης: χωρίς αναμονή, και με ένα μόνο αποτέλεσμα
  /// πηγαίνει κατευθείαν στην οντότητα.
  Future<void> _searchImmediate(
    String query,
    VoidCallback onNoDirectJump,
  ) async {
    if (!widget.enabled) return;
    final hits = await _omnisearch.queryImmediate(query);
    if (!mounted || hits == null) return;
    if (hits.length == 1) {
      await widget.onResolveEntity(hits.single);
      return;
    }
    onNoDirectJump();
  }

  IconData _iconForHit(BuildingMapOmnisearchHit hit) {
    switch (hit.kind) {
      case BuildingMapOmnisearchEntityKind.department:
        return Icons.apartment;
      case BuildingMapOmnisearchEntityKind.user:
        return Icons.person;
      case BuildingMapOmnisearchEntityKind.equipment:
        return Icons.computer;
    }
  }

  String _kindLabel(BuildingMapOmnisearchHit hit) {
    switch (hit.kind) {
      case BuildingMapOmnisearchEntityKind.department:
        return 'Τμήμα';
      case BuildingMapOmnisearchEntityKind.user:
        return 'Υπάλληλος';
      case BuildingMapOmnisearchEntityKind.equipment:
        return 'Εξοπλισμός';
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<BuildingMapOmnisearchHit>(
      textEditingController: widget.controller,
      focusNode: widget.focusNode,
      optionsBuilder: (value) => _optionsFor(value.text),
      displayStringForOption: (hit) => hit.title,
      onSelected: (hit) async {
        await widget.onResolveEntity(hit);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          onSubmitted: (value) => _searchImmediate(value, onSubmit),
          decoration: InputDecoration(
            labelText: 'Έξυπνη αναζήτηση (Τμήμα/Υπάλληλος/Εξοπλισμός)',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.travel_explore),
            suffixIcon: ValueListenableBuilder<bool>(
              valueListenable: _omnisearch.isSearching,
              builder: (context, searching, _) {
                if (searching) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return IconButton(
                  tooltip: 'Αναζήτηση',
                  onPressed: widget.enabled
                      ? () => _searchImmediate(controller.text, () {})
                      : null,
                  icon: const Icon(Icons.search),
                );
              },
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList(growable: false);
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320, minWidth: 360),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final hit = list[index];
                  final theme = Theme.of(context);
                  final mapLabel = hit.mapDisplayLabel;
                  return ListTile(
                    dense: true,
                    leading: Icon(_iconForHit(hit), size: 18),
                    title: Text(
                      hit.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hit.subtitle != null)
                          Text(
                            hit.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (mapLabel != null)
                          Padding(
                            padding: EdgeInsets.only(
                              top: hit.subtitle != null ? 2 : 0,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.map_outlined,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Στον χάρτη: $mapLabel',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (hit.subtitle == null && mapLabel == null)
                          Text(
                            _kindLabel(hit),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    onTap: () => onSelected(hit),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
