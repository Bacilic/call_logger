/// Εμφάνιση οντοτήτων soft-deleted (ιστορικό, κλήσεις, εκκρεμότητες).
const String kCatalogEntityDeletedSuffix = ' (διαγραμμένο)';

@Deprecated('Use kCatalogEntityDeletedSuffix')
const String kHistoryUserDeletedSuffix = kCatalogEntityDeletedSuffix;

@Deprecated('Use kCatalogEntityDeletedSuffix')
const String kHistoryCategoryDeletedSuffix = kCatalogEntityDeletedSuffix;

@Deprecated('Use kCatalogEntityDeletedSuffix')
const String kHistoryEquipmentDeletedSuffix = kCatalogEntityDeletedSuffix;

bool historyEntityIsDeleted(dynamic value) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return false;
}

/// Κείμενο λίστας με προαιρετικό επίθημα — χωρίς στυλ (audit, copy).
String historyDeletedDisplayLabel(
  String base, {
  required bool isDeleted,
  required String deletedSuffix,
}) {
  final t = base.trim();
  if (t.isEmpty || t == '—' || t == '-') {
    return t.isEmpty ? '—' : t;
  }
  if (!isDeleted) return t;
  if (t.endsWith(deletedSuffix)) return t;
  return '$t$deletedSuffix';
}
