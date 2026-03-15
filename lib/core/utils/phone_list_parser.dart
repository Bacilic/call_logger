class PhoneListParser {
  PhoneListParser._();

  /// Διαχωρίζει λίστα τηλεφώνων με delimiters: κόμμα, κενό, παύλα.
  static List<String> splitPhones(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return const [];
    final seen = <String>{};
    final result = <String>[];
    for (final item in text.split(RegExp(r'[,\s-]+'))) {
      final value = item.trim();
      if (value.isEmpty) continue;
      if (seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }

  /// Συνενώνει τηλέφωνα σε canonical αποθήκευση "a, b, c".
  static String joinPhones(Iterable<String> phones) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in phones) {
      final value = item.trim();
      if (value.isEmpty) continue;
      if (seen.add(value)) {
        result.add(value);
      }
    }
    return result.join(', ');
  }

  /// Επιστρέφει true όταν η λίστα [raw] περιέχει ΑΚΡΙΒΩΣ το [phone] ως token.
  static bool containsPhone(String? raw, String? phone) {
    final target = phone?.trim() ?? '';
    if (target.isEmpty) return false;
    return splitPhones(raw).contains(target);
  }
}
