import 'package:flutter/material.dart';

import '../../../core/widgets/deleted_catalog_entity_text.dart';

/// Συμβατότητα ιστορικού — ίδια εμφάνιση με [DeletedCatalogEntityText].
class HistoryDeletedEntityText extends DeletedCatalogEntityText {
  const HistoryDeletedEntityText({
    super.key,
    required super.text,
    required super.isDeleted,
    super.style,
    super.maxLines = 1,
    super.overflow = TextOverflow.ellipsis,
  });
}
