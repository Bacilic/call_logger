import 'search_text_normalizer.dart';

/// Όρια ενεργού τμήματος σε πεδίο τηλεφώνων με κόμμα (για autocomplete).
class PhoneFieldSegmentBounds {
  const PhoneFieldSegmentBounds({
    required this.start,
    required this.end,
  });

  final int start;

  /// Αποκλειστικό τέλος τμήματος στο πλήρες κείμενο.
  final int end;

  String segmentIn(String text) {
    final safeEnd = end.clamp(start, text.length);
    return text.substring(start, safeEnd);
  }
}

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

  /// Όρια τμήματος που επεξεργάζεται ο κέρσορας (διαχωρισμός μόνο με κόμμα).
  static PhoneFieldSegmentBounds activeSegmentBounds(String text, int cursor) {
    final c = cursor.clamp(0, text.length);
    var start = 0;
    for (var i = c - 1; i >= 0; i--) {
      if (text[i] == ',') {
        start = i + 1;
        break;
      }
    }
    while (start < text.length && text[start] == ' ') {
      start++;
    }

    var end = text.length;
    for (var i = start; i < text.length; i++) {
      if (text[i] == ',') {
        end = i;
        break;
      }
    }
    return PhoneFieldSegmentBounds(start: start, end: end);
  }

  /// Αντικαθιστά το ενεργό τμήμα με [replacement]· προαιρετικά προσθέτει «, » στο τέλος.
  static ({String text, int cursor}) replaceActiveSegment({
    required String text,
    required int cursor,
    required String replacement,
    bool appendTrailingCommaWhenAtEnd = true,
  }) {
    final bounds = activeSegmentBounds(text, cursor);
    final before = text.substring(0, bounds.start);
    final after = text.substring(bounds.end);
    final suffix =
        appendTrailingCommaWhenAtEnd && after.trim().isEmpty ? ', ' : '';
    final newText = '$before$replacement$suffix$after';
    final newCursor = before.length + replacement.length + suffix.length;
    return (text: newText, cursor: newCursor);
  }

  static String _digitsOnly(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  /// Φιλτράρει [allKnownPhones] για autocomplete ενός τμήματος (όλα τα τηλέφωνα βάσης).
  static Iterable<String> autocompletePhonesForSegment({
    required Iterable<String> allKnownPhones,
    required String segmentQuery,
    int minQueryLength = 2,
  }) {
    final q = segmentQuery.trim();
    if (q.length < minQueryLength) return const [];
    final qDigits = _digitsOnly(q);
    if (qDigits.length >= minQueryLength) {
      return allKnownPhones.where((phone) {
        final phoneDigits = _digitsOnly(phone);
        return phoneDigits.contains(qDigits);
      });
    }
    return allKnownPhones.where(
      (phone) => SearchTextNormalizer.matchesNormalizedQuery(phone, q),
    );
  }
}
