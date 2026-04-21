import 'package:flutter/widgets.dart';

/// Κρατά την επιλεγμένη γραμμή ορατή σε dropdown `Autocomplete` (βέλη πληκτρολογίου).
void syncAutocompleteHighlightedListScroll({
  required ScrollController controller,
  required int highlightedIndex,
  required double itemExtent,
  required double viewportExtent,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!controller.hasClients) return;
    final currentOffset = controller.offset;
    final firstVisible = (currentOffset / itemExtent).floor();
    final lastVisible =
        ((currentOffset + viewportExtent - itemExtent) / itemExtent).floor();
    double targetOffset = currentOffset;
    if (highlightedIndex < firstVisible) {
      targetOffset = highlightedIndex * itemExtent;
    } else if (highlightedIndex > lastVisible) {
      targetOffset = (highlightedIndex + 1) * itemExtent - viewportExtent;
    }
    final maxExtent = controller.position.maxScrollExtent;
    targetOffset = targetOffset.clamp(0.0, maxExtent);
    if ((targetOffset - currentOffset).abs() > 0.5) {
      controller.jumpTo(targetOffset);
    }
  });
}
