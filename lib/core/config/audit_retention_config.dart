import 'dart:convert';

import 'audit_retention_class.dart';

/// Ρυθμίσεις εκκαθάρισης του Ιστορικού (`audit_log`).
///
/// **Τρία επίπεδα, από το ακίνδυνο στο οριστικό:**
/// 1. **Συμπίεση** — σβήνεται μόνο το παραγόμενο κείμενο αναζήτησης από παλιές
///    εγγραφές. Καμία γραμμή δεν χάνεται, και το κείμενο ξαναχτίζεται όποτε
///    χρειαστεί. Μετρημένο στη βάση του νοσοκομείου: **61% του χώρου**.
/// 2. **Διαβάθμιση** — όρια ηλικίας **ανά κλάση**, όχι ένα ψαλίδι για όλους.
///    Οι δημιουργίες και διαγραφές Καταλόγου δεν σβήνονται ποτέ.
/// 3. **Δικλείδες** — πάτωμα γραμμών που δεν παραβιάζεται, και εξαγωγή σε
///    αρχείο πριν από κάθε οριστική διαγραφή.
class AuditRetentionConfig {
  const AuditRetentionConfig({
    this.maxRows,
    this.purgeOnAppStart = false,
    this.compactSearchTextAfterDays,
    this.operationalMaxAgeDays,
    this.volatileMaxAgeDays,
    this.minimumRowsFloor = kDefaultMinimumRowsFloor,
    this.exportBeforePurge = true,
  });

  /// Πόσες γραμμές μένουν πάντα, όσο σφιχτά κι αν ρυθμιστούν τα όρια.
  ///
  /// Υπάρχει για την περίπτωση λάθους ρύθμισης: κανένα «κράτα 1 ημέρα» δεν
  /// πρέπει να αδειάζει το Ιστορικό σε βαθμό που να μη φαίνεται τι έγινε
  /// χθες.
  static const int kDefaultMinimumRowsFloor = 500;

  /// Μέγιστο πλήθος γραμμών (null = χωρίς όριο πλήθους).
  ///
  /// Κόβει **οριζόντια** και αγνοεί τις κλάσεις, γι' αυτό εφαρμόζεται
  /// τελευταίο και μόνο πάνω σε ό,τι δεν είναι [AuditRetentionClass.permanent].
  final int? maxRows;

  final bool purgeOnAppStart;

  /// Επίπεδο 1 — μετά από πόσες μέρες πετιέται το παραγόμενο κείμενο
  /// αναζήτησης. `null` = ποτέ.
  final int? compactSearchTextAfterDays;

  /// Επίπεδο 2 — όριο ηλικίας για τις αλλαγές σε καρτέλες. `null` = χωρίς όριο.
  final int? operationalMaxAgeDays;

  /// Επίπεδο 2 — όριο ηλικίας για κλήσεις, εκκρεμότητες και αντίγραφα.
  final int? volatileMaxAgeDays;

  /// Επίπεδο 3 — το πάτωμα γραμμών.
  final int minimumRowsFloor;

  /// Επίπεδο 3 — εξαγωγή σε αρχείο πριν από κάθε οριστική διαγραφή.
  final bool exportBeforePurge;

  /// Υπάρχει κάτι να εφαρμοστεί;
  bool get hasAnyPolicy =>
      compactSearchTextAfterDays != null ||
      operationalMaxAgeDays != null ||
      volatileMaxAgeDays != null ||
      maxRows != null;

  /// Το όριο ηλικίας μιας κλάσης· `null` σημαίνει «μην αγγίξεις».
  ///
  /// Η [AuditRetentionClass.permanent] επιστρέφει πάντα `null` — δεν είναι
  /// ρύθμιση που μπορεί να παρακαμφθεί, είναι η ίδια η αρχή της διαβάθμισης.
  int? maxAgeDaysFor(AuditRetentionClass value) {
    switch (value) {
      case AuditRetentionClass.permanent:
        return null;
      case AuditRetentionClass.operational:
        return operationalMaxAgeDays;
      case AuditRetentionClass.volatile:
        return volatileMaxAgeDays;
    }
  }

  AuditRetentionConfig copyWith({
    int? maxRows,
    bool clearMaxRows = false,
    bool? purgeOnAppStart,
    int? compactSearchTextAfterDays,
    bool clearCompactSearchText = false,
    int? operationalMaxAgeDays,
    bool clearOperationalMaxAge = false,
    int? volatileMaxAgeDays,
    bool clearVolatileMaxAge = false,
    int? minimumRowsFloor,
    bool? exportBeforePurge,
  }) {
    return AuditRetentionConfig(
      maxRows: clearMaxRows ? null : (maxRows ?? this.maxRows),
      purgeOnAppStart: purgeOnAppStart ?? this.purgeOnAppStart,
      compactSearchTextAfterDays: clearCompactSearchText
          ? null
          : (compactSearchTextAfterDays ?? this.compactSearchTextAfterDays),
      operationalMaxAgeDays: clearOperationalMaxAge
          ? null
          : (operationalMaxAgeDays ?? this.operationalMaxAgeDays),
      volatileMaxAgeDays: clearVolatileMaxAge
          ? null
          : (volatileMaxAgeDays ?? this.volatileMaxAgeDays),
      minimumRowsFloor: minimumRowsFloor ?? this.minimumRowsFloor,
      exportBeforePurge: exportBeforePurge ?? this.exportBeforePurge,
    );
  }

  Map<String, dynamic> toJson() => {
    'max_rows': maxRows,
    'purge_on_app_start': purgeOnAppStart,
    'compact_search_text_after_days': compactSearchTextAfterDays,
    'operational_max_age_days': operationalMaxAgeDays,
    'volatile_max_age_days': volatileMaxAgeDays,
    'minimum_rows_floor': minimumRowsFloor,
    'export_before_purge': exportBeforePurge,
  };

  /// **Συμβατότητα με τις δύο προηγούμενες μορφές.**
  ///
  /// 1. Ως τις 18/09/2026 υπήρχαν δύο διακόπτες — «ενεργή πολιτική» και
  ///    «εκκαθάριση στην εκκίνηση» — και η εκκαθάριση απαιτούσε **και τους
  ///    δύο**. Ένα αποθηκευμένο `enabled: false` πρέπει να συνεχίσει να
  ///    σημαίνει «μην καθαρίζεις».
  /// 2. Ως τις 19/09/2026 υπήρχε **ένα** όριο ηλικίας για όλα (`max_age_days`).
  ///    Μεταφέρεται και στις δύο αναλώσιμες κλάσεις, ώστε να μη χαλαρώσει
  ///    σιωπηλά μια πολιτική που κάποιος είχε ορίσει — οι δημιουργίες
  ///    Καταλόγου όμως προστατεύονται πλέον, που είναι **αυστηρότερο** από
  ///    πριν και ποτέ επικίνδυνο.
  factory AuditRetentionConfig.fromJson(Map<String, dynamic> m) {
    final legacyEnabled = !m.containsKey('enabled') || m['enabled'] == true;
    final legacyMaxAge = (m['max_age_days'] as num?)?.toInt();

    int? readAge(String key) {
      final value = (m[key] as num?)?.toInt();
      return value ?? legacyMaxAge;
    }

    return AuditRetentionConfig(
      maxRows: (m['max_rows'] as num?)?.toInt(),
      purgeOnAppStart: legacyEnabled && m['purge_on_app_start'] == true,
      compactSearchTextAfterDays: (m['compact_search_text_after_days'] as num?)
          ?.toInt(),
      operationalMaxAgeDays: readAge('operational_max_age_days'),
      volatileMaxAgeDays: readAge('volatile_max_age_days'),
      minimumRowsFloor:
          (m['minimum_rows_floor'] as num?)?.toInt() ??
          kDefaultMinimumRowsFloor,
      // Οι παλιές εγγραφές δεν ξέρουν από εξαγωγή· η ασφαλής προεπιλογή είναι
      // «ναι, κράτα αντίγραφο».
      exportBeforePurge: m['export_before_purge'] != false,
    );
  }

  static AuditRetentionConfig fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const AuditRetentionConfig();
    }
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) {
        return AuditRetentionConfig.fromJson(d);
      }
      if (d is Map) {
        return AuditRetentionConfig.fromJson(Map<String, dynamic>.from(d));
      }
    } catch (_) {
      // Χαλασμένη ρύθμιση σημαίνει «καμία πολιτική», ποτέ «σβήσε τα πάντα».
    }
    return const AuditRetentionConfig();
  }
}
