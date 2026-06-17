import 'dart:convert';

/// Αποθηκευμένα φίλτρα λίστας λεξικού (χωρίς αναζήτηση κειμένου).
class LexiconListFiltersModel {
  const LexiconListFiltersModel({
    this.langFilter,
    this.sourceFilter,
    this.categoryFilter,
    this.columnGroups,
    this.lettersCompareOp = '>=',
    this.lettersCount = '',
    this.diacriticMarksFilter,
    this.page = 0,
  });

  final String? langFilter;
  final String? sourceFilter;
  final String? categoryFilter;
  /// null = αυτόματος αριθμός ομάδων στηλών· 1–4 = σταθερός.
  final int? columnGroups;
  final String lettersCompareOp;
  final String lettersCount;
  /// null = όλα· `none` | `1` | `2` | `3` | `gt3`
  final String? diacriticMarksFilter;
  final int page;

  static const _allowedLettersOps = {'>=', '<=', '='};
  static const _allowedDiacriticFilters = {'none', '1', '2', '3', 'gt3'};
  static const Object _unset = Object();

  LexiconListFiltersModel copyWith({
    Object? langFilter = _unset,
    Object? sourceFilter = _unset,
    Object? categoryFilter = _unset,
    Object? columnGroups = _unset,
    String? lettersCompareOp,
    String? lettersCount,
    Object? diacriticMarksFilter = _unset,
    int? page,
  }) {
    return LexiconListFiltersModel(
      langFilter: identical(langFilter, _unset)
          ? this.langFilter
          : langFilter as String?,
      sourceFilter: identical(sourceFilter, _unset)
          ? this.sourceFilter
          : sourceFilter as String?,
      categoryFilter: identical(categoryFilter, _unset)
          ? this.categoryFilter
          : categoryFilter as String?,
      columnGroups: identical(columnGroups, _unset)
          ? this.columnGroups
          : columnGroups as int?,
      lettersCompareOp: lettersCompareOp ?? this.lettersCompareOp,
      lettersCount: lettersCount ?? this.lettersCount,
      diacriticMarksFilter: identical(diacriticMarksFilter, _unset)
          ? this.diacriticMarksFilter
          : diacriticMarksFilter as String?,
      page: page ?? this.page,
    );
  }

  Map<String, dynamic> toJson() => {
        if (langFilter != null) 'lang': langFilter,
        if (sourceFilter != null) 'source': sourceFilter,
        if (categoryFilter != null) 'category': categoryFilter,
        if (columnGroups != null) 'column_groups': columnGroups,
        'letters_op': lettersCompareOp,
        if (lettersCount.isNotEmpty) 'letters_count': lettersCount,
        if (diacriticMarksFilter != null) 'diacritic': diacriticMarksFilter,
        if (page != 0) 'page': page,
      };

  static LexiconListFiltersModel fromJson(Map<String, dynamic> json) {
    final rawOp = json['letters_op'] as String? ?? '>=';
    final lettersOp = _allowedLettersOps.contains(rawOp) ? rawOp : '>=';

    final rawLetters = json['letters_count']?.toString().trim() ?? '';
    final lettersCount = sanitizeLettersCount(rawLetters);

    final rawDiacritic = json['diacritic'] as String?;
    final diacritic = rawDiacritic != null &&
            _allowedDiacriticFilters.contains(rawDiacritic)
        ? rawDiacritic
        : null;

    final rawGroups = json['column_groups'];
    int? columnGroups;
    if (rawGroups is int) {
      columnGroups = rawGroups.clamp(1, 4);
    } else if (rawGroups is String) {
      final n = int.tryParse(rawGroups);
      if (n != null) columnGroups = n.clamp(1, 4);
    }

    final rawPage = json['page'];
    var page = 0;
    if (rawPage is int) {
      page = rawPage < 0 ? 0 : rawPage;
    } else if (rawPage is String) {
      page = int.tryParse(rawPage)?.clamp(0, 1 << 30) ?? 0;
    }

    return LexiconListFiltersModel(
      langFilter: _nullableString(json['lang']),
      sourceFilter: _nullableString(json['source']),
      categoryFilter: _nullableString(json['category']),
      columnGroups: columnGroups,
      lettersCompareOp: lettersOp,
      lettersCount: lettersCount,
      diacriticMarksFilter: diacritic,
      page: page,
    );
  }

  static String? _nullableString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String sanitizeLettersCount(String raw) {
    if (raw.isEmpty) return '';
    final n = int.tryParse(raw);
    if (n == null || n < 1 || n > 100) return '';
    return '$n';
  }

  String encodeForStorage() => jsonEncode(toJson());

  static LexiconListFiltersModel decodeFromStorage(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const LexiconListFiltersModel();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const LexiconListFiltersModel();
      }
      return fromJson(decoded);
    } catch (_) {
      return const LexiconListFiltersModel();
    }
  }
}
