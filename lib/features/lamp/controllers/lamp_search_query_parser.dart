import '../../../core/utils/search_text_normalizer.dart';

/// Στοχευμένος όρος αναζήτησης (κλειδί → στήλες + τιμή).
class LampScopedSearchTerm {
  const LampScopedSearchTerm({
    required this.normalizedKey,
    required this.columns,
    required this.value,
  });

  final String normalizedKey;
  final List<String> columns;
  final String value;
}

/// Αποτέλεσμα ανάλυσης καθολικής αναζήτησης.
class LampSearchParseResult {
  const LampSearchParseResult({
    required this.scopedTerms,
    required this.freeText,
  });

  final List<LampScopedSearchTerm> scopedTerms;
  final String freeText;

  bool get hasScopedTerms => scopedTerms.isNotEmpty;
}

/// Parser σύνταξης «κλειδί:τιμή» για την καθολική αναζήτηση Λάμπας.
class LampSearchQueryParser {
  LampSearchQueryParser._();

  static final RegExp _nextKeyPattern = RegExp(r'\s+([^\s:"]+)\s*:');

  /// Κανονικές ετικέτες κλειδιών για autocomplete (χωρίς συνώνυμα).
  static final List<String> canonicalKeys = <String>[
    'κωδικός',
    'περιγραφή',
    'σειριακός',
    'παγίο',
    'κατάσταση',
    'εγγύηση',
    'παραλαβή',
    'σχόλια',
    'master',
    'μοντέλο',
    'κατηγορία',
    'υποκατηγορία',
    'κατασκευαστής',
    'χαρακτηριστικά',
    'αναλώσιμα',
    'ip',
    'mac',
    'vlan',
    'κόμβος',
    'hostname',
    'υπάλληλος',
    'email',
    'τηλέφωνο',
    'τμήμα',
    'οργανισμός',
    'κτίριο',
    'όροφος',
    'σύμβαση',
    'προμηθευτής',
    'ανάθεση',
    'διακήρυξη',
    'σύμβαση-κατηγορία',
  ];

  static final Map<String, List<String>> _columnsByNormalizedKey =
      _buildKeyColumnMap();

  /// Πεδία φίλτρων UI που καθρεφτίζονται από στοχευμένους όρους.
  static const Map<String, String> _mirrorFieldIdsByNormalizedKey =
      <String, String>{
    'τηλεφωνο': 'phone',
    'κωδικος': 'code',
    'υπαλληλος': 'owner',
    'ονομα': 'owner',
    'ιδιοκτητης': 'owner',
    'τμημα': 'office',
    'σειριακος': 'serial',
    'sn': 'serial',
    'serial': 'serial',
  };

  static Map<String, List<String>> _buildKeyColumnMap() {
    final map = <String, List<String>>{};
    void register(List<String> aliases, List<String> columns) {
      for (final alias in aliases) {
        map[SearchTextNormalizer.normalizeDictionaryForm(alias)] = columns;
      }
    }

    register(
      <String>['κωδικός', 'κωδικος'],
      <String>['code'],
    );
    register(
      <String>['περιγραφή', 'περιγραφη'],
      <String>['description'],
    );
    register(
      <String>['σειριακός', 'σειριακος', 'sn', 'serial'],
      <String>['serial_no'],
    );
    register(
      <String>['παγίο', 'παγιο'],
      <String>['asset_no'],
    );
    register(
      <String>['κατάσταση', 'κατασταση'],
      <String>['state_name', 'state_original_text'],
    );
    register(
      <String>['εγγύηση', 'εγγυηση'],
      <String>['end_of_guarantee_date'],
    );
    register(
      <String>['παραλαβή', 'παραλαβη'],
      <String>['receiving_date'],
    );
    register(
      <String>['σχόλια', 'σχολια'],
      <String>['equipment_comments'],
    );
    register(
      <String>['master'],
      <String>['set_master', 'set_master_original_text'],
    );
    register(
      <String>['μοντέλο', 'μοντελο'],
      <String>['model_name', 'model_original_text'],
    );
    register(
      <String>['κατηγορία', 'κατηγορια'],
      <String>['category_name'],
    );
    register(
      <String>['υποκατηγορία', 'υποκατηγορια'],
      <String>['subcategory_name'],
    );
    register(
      <String>['κατασκευαστής', 'κατασκευαστης'],
      <String>['manufacturer_name'],
    );
    register(
      <String>['χαρακτηριστικά', 'χαρακτηριστικα'],
      <String>['model_attributes', 'equipment_attributes'],
    );
    register(
      <String>['αναλώσιμα', 'αναλωσιμα'],
      <String>['consumables'],
    );
    register(
      <String>['ip'],
      <String>['ip_address'],
    );
    register(
      <String>['mac'],
      <String>['network_mac'],
    );
    register(
      <String>['vlan'],
      <String>['network_vlan'],
    );
    register(
      <String>['κόμβος', 'κομβος'],
      <String>['network_node'],
    );
    register(
      <String>['hostname', 'υπολογιστής', 'υπολογιστης'],
      <String>['network_name'],
    );
    register(
      <String>['υπάλληλος', 'υπαλληλος', 'όνομα', 'ονομα', 'ιδιοκτήτης', 'ιδιοκτητης'],
      <String>['last_name', 'first_name', 'owner_original_text'],
    );
    register(
      <String>['email'],
      <String>['owner_email', 'office_email'],
    );
    register(
      <String>['τηλέφωνο', 'τηλεφωνο'],
      <String>['owner_phones', 'office_phones'],
    );
    register(
      <String>['τμήμα', 'τμημα'],
      <String>['office_name', 'department_name', 'office_original_text'],
    );
    register(
      <String>['οργανισμός', 'οργανισμος'],
      <String>['organization_name'],
    );
    register(
      <String>['κτίριο', 'κτιριο'],
      <String>['building'],
    );
    register(
      <String>['όροφος', 'οροφος'],
      <String>['level'],
    );
    register(
      <String>['σύμβαση', 'συμβαση'],
      <String>['contract_name', 'contract_original_text'],
    );
    register(
      <String>['προμηθευτής', 'προμηθευτης'],
      <String>['supplier_name'],
    );
    register(
      <String>['ανάθεση', 'αναθεση'],
      <String>['contract_award'],
    );
    register(
      <String>['διακήρυξη', 'διακηρυξη'],
      <String>['contract_declaration'],
    );
    register(
      <String>['σύμβαση-κατηγορία', 'συμβαση-κατηγορια'],
      <String>['contract_category_name'],
    );

    return map;
  }

  static LampSearchParseResult parse(String input) {
    final scopedTerms = <LampScopedSearchTerm>[];
    final freeTextParts = <String>[];
    var index = 0;
    final length = input.length;

    while (index < length) {
      while (index < length && input[index].trim().isEmpty) {
        index++;
      }
      if (index >= length) break;

      final segmentStart = index;
      final colonIndex = _findKeyColon(input, index);
      if (colonIndex == -1) {
        final wordEnd = _findWordEnd(input, index);
        freeTextParts.add(input.substring(index, wordEnd));
        index = wordEnd;
        continue;
      }

      final rawKey = input.substring(index, colonIndex).trim();
      final normalizedKey =
          SearchTextNormalizer.normalizeDictionaryForm(rawKey);
      var valueStart = colonIndex + 1;
      while (valueStart < length && input[valueStart] == ' ') {
        valueStart++;
      }

      late final String rawValue;
      late final int valueEnd;
      if (valueStart < length && input[valueStart] == '"') {
        final closeQuote = _findClosingQuote(input, valueStart + 1);
        if (closeQuote == -1) {
          freeTextParts.add(input.substring(segmentStart).trim());
          break;
        }
        rawValue = input.substring(valueStart + 1, closeQuote);
        valueEnd = closeQuote + 1;
      } else {
        valueEnd = _findUnquotedValueEnd(input, valueStart);
        rawValue = input.substring(valueStart, valueEnd).trim();
      }

      final columns = _columnsByNormalizedKey[normalizedKey];
      if (columns == null || rawValue.isEmpty) {
        freeTextParts.add(input.substring(segmentStart, valueEnd).trim());
      } else {
        scopedTerms.add(
          LampScopedSearchTerm(
            normalizedKey: normalizedKey,
            columns: columns,
            value: rawValue,
          ),
        );
      }
      index = valueEnd;
    }

    return LampSearchParseResult(
      scopedTerms: scopedTerms,
      freeText: freeTextParts.join(' ').trim(),
    );
  }

  static String? mirrorFieldIdForKey(String rawKey) {
    final normalized = SearchTextNormalizer.normalizeDictionaryForm(rawKey);
    return _mirrorFieldIdsByNormalizedKey[normalized];
  }

  static String? mirrorFieldIdForNormalizedKey(String normalizedKey) {
    return _mirrorFieldIdsByNormalizedKey[normalizedKey];
  }

  static List<String> suggestKeys(String prefix) {
    final normalizedPrefix =
        SearchTextNormalizer.normalizeDictionaryForm(prefix);
    final matches = canonicalKeys
        .where(
          (key) => SearchTextNormalizer.normalizeDictionaryForm(key)
              .startsWith(normalizedPrefix),
        )
        .toList();
    matches.sort(
      (a, b) => SearchTextNormalizer.normalizeDictionaryForm(a).compareTo(
        SearchTextNormalizer.normalizeDictionaryForm(b),
      ),
    );
    return matches;
  }

  static int _findKeyColon(String input, int start) {
    for (var i = start; i < input.length; i++) {
      final char = input[i];
      if (char == ':') return i;
      if (char.trim().isEmpty) return -1;
    }
    return -1;
  }

  static int _findWordEnd(String input, int start) {
    for (var i = start; i < input.length; i++) {
      if (input[i].trim().isEmpty) return i;
    }
    return input.length;
  }

  static int _findClosingQuote(String input, int start) {
    for (var i = start; i < input.length; i++) {
      if (input[i] == '"') return i;
    }
    return -1;
  }

  static int _findUnquotedValueEnd(String input, int start) {
    if (start >= input.length) return start;
    final remainder = input.substring(start);
    final nextKeyMatch = _nextKeyPattern.firstMatch(remainder);
    final firstSpace = remainder.indexOf(' ');

    if (nextKeyMatch != null) {
      final endAtKey = start + nextKeyMatch.start;
      if (firstSpace == -1) return endAtKey;
      return endAtKey <= start + firstSpace ? endAtKey : start + firstSpace;
    }

    if (firstSpace == -1) return input.length;
    return start + firstSpace;
  }
}
