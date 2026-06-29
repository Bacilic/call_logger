import 'name_parser.dart';
import 'search_text_normalizer.dart';

/// Κλειδί ταύτισης ονοματεπώνυμου για διάλογο αλλαγής και διπλότυπα.
class UserIdentityNormalizer {
  UserIdentityNormalizer._();

  static String identityKeyForPerson(String? firstName, String? lastName) {
    final raw =
        '${(firstName ?? '').trim()} ${(lastName ?? '').trim()}'.trim();
    if (raw.isEmpty) return '';
    return SearchTextNormalizer.normalizeForSearch(raw);
  }

  /// Κλειδί ταύτισης μόνο για το πεδίο όνομα (first_name).
  static String firstNameKey(String? firstName) =>
      identityKeyForPerson(firstName, '');

  /// Κλειδί ταύτισης μόνο για το πεδίο επώνυμο (last_name).
  static String lastNameKey(String? lastName) =>
      identityKeyForPerson('', lastName);

  /// Σύνολο κλειδιών ταύτισης από ελεύθερο κείμενο ονόματος (και οι δύο διατάξεις).
  static Set<String> matchingIdentityKeysFromFreeText(String? freeText) {
    final keys = <String>{};
    for (final parsed in NameParserUtility.parseBothOrders(freeText ?? '')) {
      final fullKey = identityKeyForPerson(parsed.firstName, parsed.lastName);
      if (fullKey.isNotEmpty) keys.add(fullKey);
      if (parsed.firstName.isNotEmpty) {
        final firstKey = firstNameKey(parsed.firstName);
        if (firstKey.isNotEmpty) keys.add(firstKey);
      }
      if (parsed.lastName.isNotEmpty) {
        final lastKey = lastNameKey(parsed.lastName);
        if (lastKey.isNotEmpty) keys.add(lastKey);
      }
    }
    return keys;
  }

  /// Ελέγχει αν structured person ταιριάζει με οποιοδήποτε κλειδί από [sourceKeys].
  static bool personMatchesIdentityKeys({
    required String? personFirstName,
    required String? personLastName,
    required Set<String> sourceKeys,
  }) {
    if (sourceKeys.isEmpty) return false;
    final personKey = identityKeyForPerson(personFirstName, personLastName);
    if (personKey.isNotEmpty && sourceKeys.contains(personKey)) return true;

    final firstKey = firstNameKey(personFirstName);
    if (firstKey.isNotEmpty && sourceKeys.contains(firstKey)) return true;

    final lastKey = lastNameKey(personLastName);
    if (lastKey.isNotEmpty && sourceKeys.contains(lastKey)) return true;

    return false;
  }
}
