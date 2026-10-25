/// Φίλτρα λίστας ιστορικού εφαρμογής.
class AuditFilterModel {
  const AuditFilterModel({
    this.keyword = '',
    this.action,
    this.entityType,
    this.userPerforming,
    this.dateFrom,
    this.dateTo,
  });

  final String keyword;

  /// Η ετικέτα της οθόνης («Υπάλληλος - Διαγραφή»), όχι η ωμή ενέργεια της
  /// βάσης: η ίδια λέξη «ΔΙΑΓΡΑΦΗ» αφορά πολλές οντότητες.
  final String? action;
  final String? entityType;

  /// Ποιος σφράγισε την εγγραφή — όχι σε ποιον αναφέρεται.
  ///
  /// Ζει σε δικό του φίλτρο και ποτέ μέσα στη λέξη-κλειδί: αν το «ποιος το
  /// έκανε» έμπαινε στο ελεύθερο κείμενο, θα ανακατευόταν αθεράπευτα με το
  /// «σε ποιον έγινε» και δεν θα ξεχώριζαν ποτέ ξανά.
  final String? userPerforming;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  AuditFilterModel copyWith({
    String? keyword,
    String? action,
    String? entityType,
    String? userPerforming,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearAction = false,
    bool clearEntityType = false,
    bool clearUserPerforming = false,
    bool clearDateRange = false,
  }) {
    return AuditFilterModel(
      keyword: keyword ?? this.keyword,
      action: clearAction ? null : (action ?? this.action),
      entityType: clearEntityType ? null : (entityType ?? this.entityType),
      userPerforming: clearUserPerforming
          ? null
          : (userPerforming ?? this.userPerforming),
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
    );
  }

  /// Ίδια φίλτρα ⇔ ίδιες γραμμές στη λίστα.
  ///
  /// Η οθόνη συγκρίνει ολόκληρο το φίλτρο για να ξέρει αν η επιλογή προς
  /// διαγραφή ισχύει ακόμη. Κάθε νέο πεδίο μπαίνει **και εδώ** — αλλιώς η
  /// αλλαγή του αφήνει επιλεγμένες εγγραφές που δεν φαίνονται πια.
  @override
  bool operator ==(Object other) =>
      other is AuditFilterModel &&
      other.keyword == keyword &&
      other.action == action &&
      other.entityType == entityType &&
      other.userPerforming == userPerforming &&
      other.dateFrom == dateFrom &&
      other.dateTo == dateTo;

  @override
  int get hashCode => Object.hash(
    keyword,
    action,
    entityType,
    userPerforming,
    dateFrom,
    dateTo,
  );

  /// Έναρξη ημέρας (τοπική) για `timestamp >=`.
  String? get dateFromInclusiveIso {
    if (dateFrom == null) return null;
    final d = DateTime(dateFrom!.year, dateFrom!.month, dateFrom!.day);
    return d.toIso8601String();
  }

  /// Επόμενη ημέρα 00:00 (τοπική) για `timestamp <` (συμπερίληψη dateTo).
  String? get dateToExclusiveIso {
    if (dateTo == null) return null;
    final next = DateTime(
      dateTo!.year,
      dateTo!.month,
      dateTo!.day,
    ).add(const Duration(days: 1));
    return next.toIso8601String();
  }
}
