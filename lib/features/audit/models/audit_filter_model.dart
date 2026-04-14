/// Φίλτρα λίστας ιστορικού εφαρμογής.
class AuditFilterModel {
  const AuditFilterModel({
    this.keyword = '',
    this.action,
    this.entityType,
    this.dateFrom,
    this.dateTo,
  });

  final String keyword;
  final String? action;
  final String? entityType;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  AuditFilterModel copyWith({
    String? keyword,
    String? action,
    String? entityType,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearAction = false,
    bool clearEntityType = false,
    bool clearDateRange = false,
  }) {
    return AuditFilterModel(
      keyword: keyword ?? this.keyword,
      action: clearAction ? null : (action ?? this.action),
      entityType: clearEntityType ? null : (entityType ?? this.entityType),
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
    );
  }

  /// Έναρξη ημέρας (τοπική) για `timestamp >=`.
  String? get dateFromInclusiveIso {
    if (dateFrom == null) return null;
    final d = DateTime(dateFrom!.year, dateFrom!.month, dateFrom!.day);
    return d.toIso8601String();
  }

  /// Επόμενη ημέρα 00:00 (τοπική) για `timestamp <` (συμπερίληψη dateTo).
  String? get dateToExclusiveIso {
    if (dateTo == null) return null;
    final next = DateTime(dateTo!.year, dateTo!.month, dateTo!.day)
        .add(const Duration(days: 1));
    return next.toIso8601String();
  }
}
