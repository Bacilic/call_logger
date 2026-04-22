import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/directory_repository.dart';
import '../../../../core/utils/search_debouncer.dart';
import '../providers/building_map_providers.dart';

class BuildingMapOmnisearchField extends ConsumerStatefulWidget {
  const BuildingMapOmnisearchField({
    super.key,
    required this.enabled,
    required this.repo,
    required this.controller,
    required this.focusNode,
    required this.onResolveEntity,
  });

  final bool enabled;
  final DirectoryRepository repo;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function(dynamic entity) onResolveEntity;

  @override
  ConsumerState<BuildingMapOmnisearchField> createState() =>
      _BuildingMapOmnisearchFieldState();
}

class _BuildingMapOmnisearchFieldState extends ConsumerState<BuildingMapOmnisearchField> {
  final SearchDebouncer _debouncer = SearchDebouncer();
  bool _loading = false;
  List<BuildingMapOmnisearchHit> _hits = const [];

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
  }

  @override
  void dispose() {
    _debouncer.dispose();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    _debouncer.run(widget.controller.text, (q, isCurrent) async {
      await _performSearch(q, isCurrent);
    });
  }

  Future<void> _performSearch(
    String query,
    bool Function() isCurrent, {
    bool directFocusWhenSingle = false,
  }) async {
    final trimmed = query.trim();
    if (!widget.enabled) return;
    if (trimmed.isEmpty) {
      if (!mounted) return;
      ref
          .read(buildingMapSearchRevealedDepartmentIdProvider.notifier)
          .clear();
      setState(() {
        _hits = const [];
        _loading = false;
      });
      return;
    }

    if (mounted && !_loading) {
      setState(() => _loading = true);
    }
    final hits = await widget.repo.searchBuildingMapOmnisearch(trimmed);
    if (!mounted || !isCurrent()) return;

    setState(() {
      _hits = hits;
      _loading = false;
    });
    if (directFocusWhenSingle && hits.length == 1) {
      await widget.onResolveEntity(hits.first);
    }
  }

  Future<void> _searchImmediate(String query) async {
    await _debouncer.runImmediate(query, (q, isCurrent) async {
      await _performSearch(q, isCurrent, directFocusWhenSingle: true);
    });
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
      optionsBuilder: (value) {
        final q = value.text.trim();
        if (!widget.enabled || q.isEmpty) return const Iterable.empty();
        return _hits;
      },
      displayStringForOption: (hit) => hit.title,
      onSelected: (hit) async {
        await widget.onResolveEntity(hit);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          onSubmitted: (value) async {
            await _searchImmediate(value);
            onSubmit();
          },
          decoration: InputDecoration(
            labelText: 'Έξυπνη αναζήτηση (Τμήμα/Υπάλληλος/Εξοπλισμός)',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.travel_explore),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Αναζήτηση',
                    onPressed: widget.enabled
                        ? () async {
                            await _searchImmediate(controller.text);
                          }
                        : null,
                    icon: const Icon(Icons.search),
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
                  return ListTile(
                    dense: true,
                    leading: Icon(_iconForHit(hit), size: 18),
                    title: Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_kindLabel(hit)}${hit.subtitle == null ? '' : ' • ${hit.subtitle}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
