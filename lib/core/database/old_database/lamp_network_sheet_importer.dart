/// Εμπλουτισμός εξοπλισμού Λάμπας με IP / όνομα δικτύου από το φύλλο «network».
///
/// Καθαρή λογική χωρίς εξαρτήσεις βάσης ή Excel ώστε να ελέγχεται αυτόνομα:
/// ο `OldExcelImporter` μετατρέπει το φύλλο σε [LampNetworkRow] και εφαρμόζει
/// το [LampNetworkEnrichmentPlan] που παράγεται εδώ.
///
/// Στρατηγική (βλ. Data Base/old_base/lamp_ip_integration_handoff.md):
/// - Ρητός κωδικός: αν η γραμμή έχει τιμή στη στήλη `equipment_code`
///   (χειροκίνητη επιβεβαίωση), αυτή προηγείται όλων — έτσι οι χειροκίνητες
///   αντιστοιχίσεις επιβιώνουν σε κάθε επανεισαγωγή του Excel.
/// - Στρώμα Α: hostname τύπου εξοπλισμού (PC/PR/SW/LAPTOP/PRINT/HP + αριθμός)
///   → ντετερμινιστική ζεύξη με `equipment.code`, με ενισχυτή μοντέλου.
/// - Ονόματα χρήστη/περιγραφικά: ΚΑΜΙΑ αυτόματη εγγραφή — μόνο εγγραφή στην
///   ουρά `data_issues` με τυχόν υποψηφίους από αναζήτηση κειμένου.
library;

/// Είδη προβλημάτων που παράγει ο εμπλουτισμός δικτύου (πίνακας data_issues).
const String kLampNetworkIssueNoHostname = 'network_no_hostname';
const String kLampNetworkIssueCodeNotFound = 'network_code_not_found';
const String kLampNetworkIssueDuplicateHostname = 'network_duplicate_hostname';
const String kLampNetworkIssueHostnameUnmatched = 'network_hostname_unmatched';
const String kLampNetworkIssueIpInComments = 'network_ip_in_comments';
const String kLampNetworkIssueModelMismatch = 'network_model_mismatch';

/// Μία γραμμή του φύλλου «network» (ίδιες στήλες με το ip_normalized.csv).
class LampNetworkRow {
  const LampNetworkRow({
    this.positionCode = '',
    this.ip = '',
    this.equipmentCode = '',
    this.equipmentText = '',
    this.mac = '',
    this.vlan = '',
    this.hostname = '',
    this.workgroup = '',
    this.internet = '',
    this.comments = '',
  });

  /// «Κωδικός» πηγής: αναγνωριστικό ΘΕΣΗΣ δικτύου — ΟΧΙ κωδικός εξοπλισμού.
  final String positionCode;
  final String ip;

  /// Ρητός κωδικός εξοπλισμού Λάμπας (στήλη `equipment_code`) — συμπληρώνεται
  /// χειροκίνητα ή από προηγούμενη αυτόματη αντιστοίχιση· προηγείται όλων.
  final String equipmentCode;
  final String equipmentText;
  final String mac;
  final String vlan;
  final String hostname;
  final String workgroup;
  final String internet;
  final String comments;

  bool get isEmpty =>
      positionCode.trim().isEmpty &&
      ip.trim().isEmpty &&
      equipmentCode.trim().isEmpty &&
      equipmentText.trim().isEmpty &&
      mac.trim().isEmpty &&
      vlan.trim().isEmpty &&
      hostname.trim().isEmpty &&
      workgroup.trim().isEmpty &&
      internet.trim().isEmpty &&
      comments.trim().isEmpty;

  int? get positionCodeAsInt => int.tryParse(positionCode.trim());

  int? get equipmentCodeAsInt => int.tryParse(equipmentCode.trim());

  /// Ανασύνθεση της γραμμής (σειρά στηλών φύλλου network) για raw_value.
  String get rawLine => <String>[
    positionCode,
    ip,
    equipmentCode,
    equipmentText,
    mac,
    vlan,
    hostname,
    workgroup,
    internet,
    comments,
  ].join(';');

  /// Ανθρώπινη σύνοψη για μηνύματα ουράς (μόνο τα μη κενά πεδία).
  String get summary {
    final parts = <String>[
      if (ip.trim().isNotEmpty) 'IP=${ip.trim()}',
      if (hostname.trim().isNotEmpty) 'hostname=${hostname.trim()}',
      if (equipmentText.trim().isNotEmpty) 'εξοπλισμός=${equipmentText.trim()}',
      if (mac.trim().isNotEmpty) 'MAC=${mac.trim()}',
      if (vlan.trim().isNotEmpty) 'VLAN=${vlan.trim()}',
      if (workgroup.trim().isNotEmpty) 'ομάδα=${workgroup.trim()}',
      if (comments.trim().isNotEmpty) 'σχόλια=${comments.trim()}',
    ];
    return parts.join(' · ');
  }
}

/// Στοιχεία εγγραφής εξοπλισμού Λάμπας που χρειάζεται ο εμπλουτισμός.
class LampNetworkEquipmentInfo {
  const LampNetworkEquipmentInfo({
    this.description = '',
    this.modelText = '',
    this.ownerText = '',
    this.comments = '',
    this.attributes = '',
  });

  final String description;
  final String modelText;
  final String ownerText;
  final String comments;
  final String attributes;
}

/// Αυτόματη εγγραφή προς εφαρμογή στη στήλη ip_address/network_name.
class LampNetworkUpdate {
  const LampNetworkUpdate({
    required this.code,
    required this.ip,
    required this.networkName,
    required this.networkSource,
    this.node,
    this.vlan,
    this.mac,
    this.description,
    this.comments,
  });

  final int code;
  final String? ip;
  final String? networkName;

  /// Σφραγίδα προέλευσης: πώς προέκυψε η τιμή (απαίτηση ιχνηλασιμότητας).
  final String networkSource;

  /// Κωδικός θέσης δικτύου (κόμβος) της πηγής.
  final String? node;
  final String? vlan;
  final String? mac;

  /// Το πεδίο «Εξοπλισμός» της παλιάς βάσης δικτύου (μοντέλο/κατασκευαστής).
  final String? description;
  final String? comments;
}

/// Εγγραφή ουράς data_issues για αμφίβολη/αναντιστοίχιστη γραμμή.
class LampNetworkIssue {
  const LampNetworkIssue({
    required this.issueType,
    required this.rowNumber,
    required this.rawValue,
    required this.message,
  });

  final String issueType;
  final int? rowNumber;
  final String rawValue;
  final String message;
}

class LampNetworkEnrichmentPlan {
  const LampNetworkEnrichmentPlan({
    required this.updates,
    required this.issues,
  });

  final List<LampNetworkUpdate> updates;
  final List<LampNetworkIssue> issues;
}

final RegExp _equipmentHostnamePattern = RegExp(
  r'^(PC|PR|SW|LAPTOP|PRINT|HP)0*(\d+)$',
  caseSensitive: false,
);

final RegExp _ipv4Pattern = RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}');

/// Αριθμητικό μέρος hostname τύπου εξοπλισμού (`PC3846` → 3846)·
/// `null` για ονόματα χρήστη/περιγραφικά/κενά.
int? lampNetworkHostnameCode(String hostname) {
  final match = _equipmentHostnamePattern.firstMatch(hostname.trim());
  if (match == null) return null;
  return int.tryParse(match.group(2)!);
}

const Map<String, String> _greekAccentMap = <String, String>{
  'Ά': 'Α', 'Έ': 'Ε', 'Ή': 'Η', 'Ί': 'Ι', 'Ό': 'Ο', 'Ύ': 'Υ', 'Ώ': 'Ω',
  'Ϊ': 'Ι', 'Ϋ': 'Υ', 'ΐ': 'Ι', 'ΰ': 'Υ', 'ς': 'Σ',
};

String _stripAccentsUpper(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toUpperCase().runes) {
    final char = String.fromCharCode(rune);
    // Αφαίρεση combining marks (π.χ. από toUpperCase σε ΐ/ΰ).
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    buffer.write(_greekAccentMap[char] ?? char);
  }
  return buffer.toString();
}

/// Κανονικοποίηση αναζήτησης: κεφαλαία, χωρίς τόνους, ενιαία κενά.
String lampNetworkSearchNormalize(String value) {
  return _stripAccentsUpper(value).replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// «Συμπίεση» για σύγκριση μοντέλων: μόνο γράμματα/ψηφία — αντέχει σε
/// χαμένα κενά της πηγής (π.χ. «TURBOXFlexworkMi3414»).
String lampNetworkSquash(String value) {
  return _stripAccentsUpper(value).replaceAll(RegExp(r'[^A-ZΑ-Ω0-9]'), '');
}

/// Ενισχυτής μοντέλου: συμφωνία όταν η μία «συμπιεσμένη» τιμή περιέχει την
/// άλλη. Κενές τιμές θεωρούνται ελλιπή στοιχεία, όχι ασυμφωνία.
bool lampNetworkModelsAgree(String networkModel, String lampModelText) {
  final network = lampNetworkSquash(networkModel);
  final lamp = lampNetworkSquash(lampModelText);
  if (network.isEmpty || lamp.isEmpty) return true;
  return lamp.contains(network) || network.contains(lamp);
}

const Map<String, List<String>> _headerAliases = <String, List<String>>{
  'positionCode': <String>['NODECODE', 'ΚΩΔΙΚΟΣ'],
  'ip': <String>['IP', 'IPΔΙΕΥΘΥΝΣΗ'],
  'equipmentCode': <String>['EQUIPMENTCODE', 'ΚΩΔΙΚΟΣΕΞΟΠΛΙΣΜΟΥ'],
  'equipmentText': <String>['EQUIPMENTDESCRIPTION', 'ΕΞΟΠΛΙΣΜΟΣ'],
  'mac': <String>['MAC', 'ΦΥΣΙΚΗΔΙΕΥΘΥΝΣΗMAC', 'ΦΥΣΙΚΗΔΙΕΥΘΥΝΣΗ'],
  'vlan': <String>['VLAN', 'ΟΝΟΜΑVLAN'],
  'hostname': <String>['HOSTNAME', 'ΟΝΟΜΑΣΤΟΔΙΚΤΥΟ'],
  'workgroup': <String>['WORKGROUP', 'ΟΜΑΔΑΕΡΓΑΣΙΑΣ'],
  'internet': <String>['INTERNET', 'ΠΡΟΣΒΑΣΗΣΤΟINTERNET'],
  'comments': <String>['COMMENTS', 'ΣΧΟΛΙΑ'],
};

/// Αντιστοίχιση κεφαλίδων του φύλλου «network» σε πεδία [LampNetworkRow].
/// Κλειδιά αποτελέσματος: positionCode, ip, equipmentText, mac, vlan,
/// hostname, workgroup, internet, comments.
Map<String, int> lampNetworkHeaderIndexes(List<String?> headerCells) {
  final result = <String, int>{};
  for (var i = 0; i < headerCells.length; i++) {
    final normalized = lampNetworkSquash(headerCells[i] ?? '');
    if (normalized.isEmpty) continue;
    for (final entry in _headerAliases.entries) {
      if (result.containsKey(entry.key)) continue;
      if (entry.value.contains(normalized)) {
        result[entry.key] = i;
        break;
      }
    }
  }
  return result;
}

class _PendingUpdate {
  _PendingUpdate({
    required this.row,
    required this.ip,
    required this.hostname,
    required this.modelMismatch,
    required this.explicitCode,
  });

  LampNetworkRow row;
  String ip;
  String hostname;
  final bool modelMismatch;

  /// `true` όταν η ζεύξη προήλθε από τη στήλη `equipment_code` (ρητή /
  /// χειροκίνητα επιβεβαιωμένη) και όχι από ευρετική hostname.
  final bool explicitCode;
}

/// Παράγει το πλάνο εμπλουτισμού: αυτόματες εγγραφές (Στρώμα Α) και εγγραφές
/// ουράς για ό,τι δεν αντιστοιχίζεται με ασφάλεια. Δεν αγγίζει βάση.
LampNetworkEnrichmentPlan planLampNetworkEnrichment({
  required List<LampNetworkRow> rows,
  required Map<int, LampNetworkEquipmentInfo> equipmentByCode,
}) {
  final updates = <LampNetworkUpdate>[];
  final issues = <LampNetworkIssue>[];

  final hostnameCounts = <String, int>{};
  for (final row in rows) {
    final normalized = lampNetworkSearchNormalize(row.hostname);
    if (normalized.isEmpty) continue;
    hostnameCounts[normalized] = (hostnameCounts[normalized] ?? 0) + 1;
  }

  // Κείμενο αναζήτησης ανά εξοπλισμό για υποψηφίους Στρώματος Β.
  final searchTextByCode = <int, String>{
    for (final entry in equipmentByCode.entries)
      entry.key: lampNetworkSearchNormalize(
        '${entry.value.description} | ${entry.value.comments} | '
        '${entry.value.ownerText} | ${entry.value.attributes}',
      ),
  };

  List<int> candidatesFor(String hostname) {
    final normalized = lampNetworkSearchNormalize(hostname);
    if (normalized.length < 4) return const <int>[];
    final matches = <int>[];
    for (final entry in searchTextByCode.entries) {
      if (entry.value.contains(normalized)) {
        matches.add(entry.key);
        if (matches.length >= 5) break;
      }
    }
    return matches;
  }

  final pendingByCode = <int, _PendingUpdate>{};

  for (final row in rows) {
    if (row.isEmpty) continue;
    final hostname = row.hostname.trim();
    final ip = row.ip.trim();

    // Ρητός κωδικός εξοπλισμού: προηγείται κάθε ευρετικής — χωρίς ενισχυτή
    // μοντέλου (η τιμή θεωρείται επιβεβαιωμένη από άνθρωπο ή προηγούμενη
    // αντιστοίχιση).
    final explicitCode = row.equipmentCodeAsInt;
    if (explicitCode != null) {
      if (!equipmentByCode.containsKey(explicitCode)) {
        issues.add(
          LampNetworkIssue(
            issueType: kLampNetworkIssueCodeNotFound,
            rowNumber: row.positionCodeAsInt,
            rawValue: row.rawLine,
            message:
                'Η στήλη equipment_code δείχνει σε κωδικό $explicitCode που '
                'δεν υπάρχει στη Λάμπα. ${row.summary}',
          ),
        );
        continue;
      }
      final existing = pendingByCode[explicitCode];
      if (existing != null) {
        if (existing.ip.isEmpty && ip.isNotEmpty) {
          existing.ip = ip;
          existing.row = row;
        }
        continue;
      }
      pendingByCode[explicitCode] = _PendingUpdate(
        row: row,
        ip: ip,
        hostname: hostname,
        modelMismatch: false,
        explicitCode: true,
      );
      continue;
    }

    if (hostname.isEmpty) {
      issues.add(
        LampNetworkIssue(
          issueType: kLampNetworkIssueNoHostname,
          rowNumber: row.positionCodeAsInt,
          rawValue: row.rawLine,
          message:
              'Δίκτυο χωρίς όνομα υπολογιστή — δεν αντιστοιχίζεται αυτόματα. '
              '${row.summary}. Χειροκίνητα: αναζήτησε την IP στην παλιά '
              'εφαρμογή δικτύου.',
        ),
      );
      continue;
    }

    final code = lampNetworkHostnameCode(hostname);
    if (code != null) {
      final info = equipmentByCode[code];
      if (info == null) {
        issues.add(
          LampNetworkIssue(
            issueType: kLampNetworkIssueCodeNotFound,
            rowNumber: row.positionCodeAsInt,
            rawValue: row.rawLine,
            message:
                'Το hostname «$hostname» δείχνει σε κωδικό $code που δεν '
                'υπάρχει στη Λάμπα. ${row.summary}',
          ),
        );
        continue;
      }
      final existing = pendingByCode[code];
      if (existing != null) {
        // Διπλό hostname τύπου εξοπλισμού → ίδιος κωδικός: κρατάμε τη
        // γραμμή που έχει IP.
        if (existing.ip.isEmpty && ip.isNotEmpty) {
          existing.ip = ip;
          existing.row = row;
        }
        continue;
      }
      final agrees = lampNetworkModelsAgree(
        row.equipmentText,
        '${info.modelText} ${info.description}',
      );
      pendingByCode[code] = _PendingUpdate(
        row: row,
        ip: ip,
        hostname: hostname,
        modelMismatch: !agrees,
        explicitCode: false,
      );
      continue;
    }

    // Ονόματα χρήστη / περιγραφικά: μόνο ουρά, ποτέ αυτόματη εγγραφή.
    final duplicateCount =
        hostnameCounts[lampNetworkSearchNormalize(hostname)] ?? 0;
    final candidates = candidatesFor(hostname);
    final candidateText = candidates.isEmpty
        ? ''
        : ' Πιθανοί υποψήφιοι στη Λάμπα (αναζήτηση κειμένου): '
              '${candidates.map((c) {
                final description = equipmentByCode[c]?.description ?? '';
                final preview = description.length > 40 ? description.substring(0, 40) : description;
                return '$c ($preview)';
              }).join(', ')}.';

    final String issueType;
    final String reason;
    if (ip.isEmpty && _ipv4Pattern.hasMatch(row.comments)) {
      issueType = kLampNetworkIssueIpInComments;
      reason =
          'κενή κύρια IP, αλλά υπάρχει IP μέσα στα σχόλια — θέλει επιβεβαίωση';
    } else if (duplicateCount > 1) {
      issueType = kLampNetworkIssueDuplicateHostname;
      reason = 'το όνομα «$hostname» εμφανίζεται $duplicateCount φορές στην πηγή';
    } else {
      issueType = kLampNetworkIssueHostnameUnmatched;
      reason = 'όνομα τύπου χρήστη/περιγραφικό χωρίς ασφαλή αντιστοίχιση';
    }
    issues.add(
      LampNetworkIssue(
        issueType: issueType,
        rowNumber: row.positionCodeAsInt,
        rawValue: row.rawLine,
        message:
            'Αναντιστοίχιστη εγγραφή δικτύου ($reason). ${row.summary}.'
            '$candidateText Χειροκίνητα: αναζήτησε την IP/όνομα στην παλιά '
            'εφαρμογή δικτύου.',
      ),
    );
  }

  final sortedCodes = pendingByCode.keys.toList()..sort();
  for (final code in sortedCodes) {
    final pending = pendingByCode[code]!;
    final info = equipmentByCode[code]!;
    var source = pending.explicitCode
        ? 'Από παλιά βάση δικτύου (~2023), ρητή αντιστοίχιση από τη στήλη '
              'equipment_code του φύλλου network'
              '${pending.hostname.isEmpty ? '' : ' (hostname «${pending.hostname}»)'}'
        : 'Από παλιά βάση δικτύου (~2023), αντιστοίχιση μέσω hostname '
              '«${pending.hostname}»';
    if (pending.ip.isEmpty) {
      source += ' · χωρίς IP στην πηγή';
    }
    if (pending.modelMismatch) {
      final networkModel = pending.row.equipmentText.trim();
      source +=
          ' · ΑΣΥΜΦΩΝΙΑ ΜΟΝΤΕΛΟΥ: δίκτυο «$networkModel» ↔ Λάμπα '
          '«${info.description}» — προς επιθεώρηση';
      issues.add(
        LampNetworkIssue(
          issueType: kLampNetworkIssueModelMismatch,
          rowNumber: code,
          rawValue: pending.row.rawLine,
          message:
              'Γράφτηκε IP/όνομα στον κωδικό $code, αλλά το μοντέλο διαφωνεί: '
              'δίκτυο «$networkModel» ↔ Λάμπα «${info.description}». '
              '${pending.row.summary}',
        ),
      );
    }
    String? nonEmpty(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    updates.add(
      LampNetworkUpdate(
        code: code,
        ip: pending.ip.isEmpty ? null : pending.ip,
        networkName: pending.hostname.isEmpty ? null : pending.hostname,
        networkSource: source,
        node: nonEmpty(pending.row.positionCode),
        vlan: nonEmpty(pending.row.vlan),
        mac: nonEmpty(pending.row.mac),
        description: nonEmpty(pending.row.equipmentText),
        comments: nonEmpty(pending.row.comments),
      ),
    );
  }

  return LampNetworkEnrichmentPlan(updates: updates, issues: issues);
}
