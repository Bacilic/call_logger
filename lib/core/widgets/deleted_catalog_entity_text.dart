import 'package:flutter/material.dart';

import '../utils/history_entity_display_utils.dart';
import 'ellipsis_tooltip_text.dart';

/// Κείμενο με πλαγιά + «(διαγραμμένο)» όταν η συνδεδεμένη οντότητα καταλόγου είναι soft-deleted.
class DeletedCatalogEntityText extends StatelessWidget {
  const DeletedCatalogEntityText({
    super.key,
    required this.text,
    required this.isDeleted,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final bool isDeleted;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final label = historyDeletedDisplayLabel(
      text,
      isDeleted: isDeleted,
      deletedSuffix: kCatalogEntityDeletedSuffix,
    );
    final base = style ?? DefaultTextStyle.of(context).style;
    final textStyle = base.copyWith(
      fontStyle: isDeleted && label != '—' ? FontStyle.italic : null,
    );
    if (overflow == TextOverflow.ellipsis) {
      return EllipsisTooltipText(
        text: label,
        style: textStyle,
        maxLines: maxLines,
      );
    }
    return Text(
      label,
      maxLines: maxLines,
      overflow: overflow,
      style: textStyle,
    );
  }
}
