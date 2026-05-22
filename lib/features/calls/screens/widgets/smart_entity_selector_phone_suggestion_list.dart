import 'package:flutter/material.dart';

import '../../../../core/utils/autocomplete_highlight_scroll.dart';

/// Λίστα πολλαπλών τηλεφώνων (overlay) κάτω από το πεδίο Τηλέφωνο.
class SmartEntityPhoneSuggestionList extends StatelessWidget {
  const SmartEntityPhoneSuggestionList({
    super.key,
    required this.phones,
    required this.onSelected,
    this.highlightedIndex = -1,
    this.scrollController,
    this.maxHeight = 240,
  });

  final List<String> phones;
  final ValueChanged<String> onSelected;
  final int highlightedIndex;
  final ScrollController? scrollController;
  final double maxHeight;

  static const double _itemExtent = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          itemCount: phones.length,
          itemExtent: _itemExtent,
          itemBuilder: (context, index) {
            return ListTile(
              dense: true,
              selected: highlightedIndex == index,
              selectedTileColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
              title: Text(phones[index]),
              onTap: () => onSelected(phones[index]),
            );
          },
        ),
      ),
    );
  }
}
