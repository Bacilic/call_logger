final RegExp _scientificSerialPattern = RegExp(
  r'^\s*[+-]?\d+([.,]\d+)?[eE][+-]?\d+\s*$',
);

final RegExp _scientificSerialExponentPattern = RegExp(
  r'[eE]([+-]?\d+)\s*$',
);

/// Ελέγχει αν η τιμή είναι σειριακός σε επιστημονική μορφή (π.χ. 4,928E+11).
bool isScientificSerial(String? raw) {
  if (raw == null) return false;
  return _scientificSerialPattern.hasMatch(raw);
}

/// Επιστρέφει τα ψηφία της ουσίας πριν το «e», χωρίς υποδιαστολή ή πρόσημο.
String scientificSerialCleanDigits(String raw) {
  final trimmed = raw.trim();
  final eIndex = trimmed.toLowerCase().indexOf('e');
  if (eIndex < 0) return '';
  final mantissa = trimmed.substring(0, eIndex);
  return mantissa.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Πιθανό συνολικό μήκος σειριακού: τιμή εκθέτη + 1 (π.χ. E+11 → 12).
int? scientificSerialExpectedLength(String raw) {
  final match = _scientificSerialExponentPattern.firstMatch(raw.trim());
  if (match == null) return null;
  final exponent = int.tryParse(match.group(1)!);
  if (exponent == null) return null;
  return exponent + 1;
}

/// Τοπικές προειδοποιήσεις (μη δεσμευτικές) για νέο σειριακό σε επιστημονική μορφή.
List<String> scientificSerialLocalWarnings({
  required String newSerial,
  required String cleanDigits,
  required int? expectedLength,
  required String rawSerial,
}) {
  final trimmed = newSerial.trim();
  final warnings = <String>[];

  if (trimmed.isEmpty) {
    warnings.add('Ο νέος σειριακός είναι κενός.');
  } else if (trimmed == rawSerial.trim()) {
    warnings.add('Ο νέος σειριακός είναι ίδιος με τον αρχικό (επιστημονική μορφή).');
  }

  if (cleanDigits.isNotEmpty &&
      trimmed.isNotEmpty &&
      !trimmed.contains(cleanDigits)) {
    warnings.add(
      'Τα ψηφία αναζήτησης ($cleanDigits) δεν περιέχονται στον νέο σειριακό.',
    );
  }

  if (trimmed.isNotEmpty && isScientificSerial(trimmed)) {
    warnings.add('Ο νέος σειριακός είναι πάλι σε επιστημονική μορφή.');
  }

  if (expectedLength != null &&
      trimmed.isNotEmpty &&
      (trimmed.length - expectedLength).abs() > 2) {
    warnings.add(
      'Το μήκος του νέου σειριακού (${trimmed.length}) διαφέρει σημαντικά '
      'από το πιθανό ($expectedLength ψηφία).',
    );
  }

  return warnings;
}

const String scientificSerialDuplicateWarning =
    'Ο νέος σειριακός υπάρχει ήδη σε άλλον εξοπλισμό (πιθανό barcode).';
