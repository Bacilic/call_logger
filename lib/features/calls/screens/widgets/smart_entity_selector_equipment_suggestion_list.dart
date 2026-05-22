import 'package:flutter/material.dart';

import '../../../../core/utils/autocomplete_highlight_scroll.dart';
import '../../models/equipment_model.dart';
import 'smart_entity_selector_equipment_models.dart';

/// Αρχική λίστα εξοπλισμού (overlay) — τηλέφωνο / καλών / και τα δύο.
class SmartEntityEquipmentSuggestionList extends StatelessWidget {
  const SmartEntityEquipmentSuggestionList({
    super.key,
    required this.suggestions,
    required this.theme,
    required this.onSelected,
    this.highlightedIndex = -1,
    this.scrollController,
    this.maxHeight = 260,
  });

  final List<SmartEntityEquipmentSuggestion> suggestions;
  final ThemeData theme;
  final ValueChanged<EquipmentModel> onSelected;
  final int highlightedIndex;
  final ScrollController? scrollController;
  final double maxHeight;

  static const double _itemExtent = 56;

  @override
  Widget build(BuildContext context) {
    if (highlightedIndex >= 0 && scrollController != null) {
      syncAutocompleteHighlightedListScroll(
        controller: scrollController!,
        highlightedIndex: highlightedIndex,
        itemExtent: _itemExtent,
        viewportExtent: maxHeight,
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 1,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: suggestions.length,
          itemExtent: _itemExtent,
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];
            return ListTile(
              dense: true,
              selected: highlightedIndex == index,
              selectedTileColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
              title: Text(suggestion.equipment.displayLabel),
              subtitle: Text(
                suggestion.sourceLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () => onSelected(suggestion.equipment),
            );
          },
        ),
      ),
    );
  }
}
