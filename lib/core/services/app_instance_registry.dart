import 'dart:convert';

/// Ένα αντίγραφο της εφαρμογής που έχει τρέξει σε αυτόν τον υπολογιστή.
class AppInstanceRecord {
  const AppInstanceRecord({
    required this.executablePath,
    required this.version,
    required this.lastSeen,
    this.schemaVersion,
  });

  /// Πλήρης διαδρομή του εκτελέσιμου.
  final String executablePath;

  /// Έκδοση εφαρμογής όπως ήταν στην τελευταία εκκίνηση από αυτή τη διαδρομή.
  final String version;

  final DateTime lastSeen;

  /// Έως ποια έκδοση σχήματος βάσης διαβάζει αυτό το αντίγραφο.
  ///
  /// `null` σε εγγραφές από παλαιότερες εκδόσεις που δεν την κατέγραφαν —
  /// «άγνωστη», ποτέ μάντεμα: μια οδηγία «άνοιξε τη βάση με εκείνο το
  /// εκτελέσιμο» επιτρέπεται μόνο όταν το ξέρουμε με βεβαιότητα.
  final int? schemaVersion;

  Map<String, dynamic> toJson() => {
    'path': executablePath,
    'version': version,
    'lastSeen': lastSeen.toIso8601String(),
    if (schemaVersion != null) 'schemaVersion': schemaVersion,
  };

  static AppInstanceRecord? fromJson(Map<String, dynamic> json) {
    final path = (json['path'] as String?)?.trim() ?? '';
    if (path.isEmpty) return null;
    final seen = DateTime.tryParse((json['lastSeen'] as String?) ?? '');
    if (seen == null) return null;
    return AppInstanceRecord(
      executablePath: path,
      version: (json['version'] as String?)?.trim() ?? '',
      lastSeen: seen,
      schemaVersion: (json['schemaVersion'] as num?)?.toInt(),
    );
  }
}

/// Μητρώο αντιγράφων: ποια εκτελέσιμα μοιράζονται τις ίδιες ρυθμίσεις.
///
/// Συμβόλαιο: **δεν μαντεύει — βλέπει.** Καταγράφεται μόνο ό,τι έχει όντως
/// τρέξει, οπότε δεν υπάρχουν ψευδώς θετικά. Σε υπολογιστή με μία εγκατάσταση
/// το μητρώο έχει πάντα ένα στοιχείο και δεν ειδοποιεί ποτέ.
///
/// Καθαρή λογική, χωρίς αποθήκευση — η επιμονή γίνεται από τον καλούντα.
class AppInstanceRegistry {
  AppInstanceRegistry._();

  /// Ενημερώνει (ή προσθέτει) την εγγραφή του τρέχοντος αντιγράφου.
  ///
  /// Η σύγκριση διαδρομών αγνοεί πεζά/κεφαλαία: τα Windows θεωρούν το ίδιο
  /// αρχείο ίδιο ανεξάρτητα από τη γραφή του.
  static List<AppInstanceRecord> touch({
    required List<AppInstanceRecord> known,
    required String executablePath,
    required String version,
    required DateTime now,
    int? schemaVersion,
  }) {
    final current = executablePath.trim();
    if (current.isEmpty) return List.unmodifiable(known);

    final updated = <AppInstanceRecord>[
      for (final record in known)
        if (!_samePath(record.executablePath, current)) record,
      AppInstanceRecord(
        executablePath: current,
        version: version.trim(),
        lastSeen: now,
        schemaVersion: schemaVersion,
      ),
    ]..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

    return List.unmodifiable(updated);
  }

  /// Τα υπόλοιπα αντίγραφα — όσα δεν είναι το τρέχον.
  static List<AppInstanceRecord> others(
    List<AppInstanceRecord> all,
    String currentExecutablePath,
  ) {
    final current = currentExecutablePath.trim();
    return List.unmodifiable([
      for (final record in all)
        if (!_samePath(record.executablePath, current)) record,
    ]);
  }

  /// Υπογραφή του συνόλου διαδρομών.
  ///
  /// Αλλάζει **μόνο** όταν εμφανίζεται ή φεύγει αντίγραφο — όχι όταν απλώς
  /// ξανατρέχει κάποιο. Έτσι η ειδοποίηση που έκλεισε ο χρήστης δεν
  /// ξαναεμφανίζεται για το ίδιο σύνολο, αλλά ξαναχτυπά σε νέο αντίγραφο.
  static String signature(List<AppInstanceRecord> all) {
    final paths = [
      for (final record in all) record.executablePath.trim().toLowerCase(),
    ]..sort();
    return paths.join('|');
  }

  /// Σύντομη, αναγνωρίσιμη ετικέτα φακέλου για στενούς χώρους (λωρίδα).
  ///
  /// Η πλήρης διαδρομή ζει στην κάρτα «Αντίγραφα της εφαρμογής»· σε μία λωρίδα
  /// δεν χωράει και σπάει σε άσχημο σημείο. Κρατάμε τα τελευταία [segments]
  /// τμήματα του φακέλου — αρκούν για να ξεχωρίσει ποιο αντίγραφο είναι.
  static String shortFolderLabel(String executablePath, {int segments = 2}) {
    final normalized = executablePath.trim().replaceAll('/', r'\');
    if (normalized.isEmpty) return '';

    final parts = normalized.split(r'\')
      ..removeWhere((part) => part.isEmpty);
    if (parts.length <= 1) return normalized;

    // Χωρίς το όνομα του εκτελέσιμου — ο φάκελος είναι που ξεχωρίζει.
    final folderParts = parts.sublist(0, parts.length - 1);
    if (folderParts.length <= segments) return folderParts.join(r'\');

    final tail = folderParts.sublist(folderParts.length - segments);
    return '…\\${tail.join(r'\')}';
  }

  static String encode(List<AppInstanceRecord> all) =>
      jsonEncode([for (final record in all) record.toJson()]);

  static List<AppInstanceRecord> decode(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return const <AppInstanceRecord>[];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const <AppInstanceRecord>[];
      return List.unmodifiable([
        for (final item in decoded)
          if (item is Map<String, dynamic>)
            ?AppInstanceRecord.fromJson(item)
          else if (item is Map)
            ?AppInstanceRecord.fromJson(Map<String, dynamic>.from(item)),
      ]);
    } catch (_) {
      return const <AppInstanceRecord>[];
    }
  }

  static bool _samePath(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
}
