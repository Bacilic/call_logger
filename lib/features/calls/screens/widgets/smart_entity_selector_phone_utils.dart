/// Ταξινόμηση τηλεφώνων: πρώτα τα πρόσφατα ([recentPhones]), μετά τα υπόλοιπα.
List<String> sortPhonesByRecent(
  List<String> phones,
  List<String> recentPhones,
) {
  if (recentPhones.isEmpty) return phones;
  final recentLower = recentPhones.map((e) => e.trim().toLowerCase()).toList();
  final order = <String>[];
  for (final r in recentLower) {
    for (final p in phones) {
      if (p.trim().toLowerCase() == r) {
        order.add(p);
        break;
      }
    }
  }
  for (final p in phones) {
    if (!order.contains(p)) order.add(p);
  }
  return order;
}
