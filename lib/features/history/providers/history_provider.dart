import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/utils/search_text_normalizer.dart';

/// Μοντέλο φίλτρων για το ιστορικό κλήσεων.
class HistoryFilterModel {
  const HistoryFilterModel({
    this.keyword = '',
    this.dateFrom,
    this.dateTo,
    this.category,
  });

  final String keyword;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? category;

  HistoryFilterModel copyWith({
    String? keyword,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? category,
    bool clearDateRange = false,
    bool clearCategory = false,
  }) {
    return HistoryFilterModel(
      keyword: keyword ?? this.keyword,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      category: clearCategory ? null : (category ?? this.category),
    );
  }

  /// Ημερομηνία από σε yyyy-MM-dd για SQL.
  String? get dateFromSql =>
      dateFrom != null ? _formatDate(dateFrom!) : null;

  String? get dateToSql =>
      dateTo != null ? _formatDate(dateTo!) : null;

  static String _formatDate(DateTime d) {
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

/// Notifier για τα κριτήρια φίλτρου ιστορικού.
class HistoryFilterNotifier extends Notifier<HistoryFilterModel> {
  @override
  HistoryFilterModel build() => const HistoryFilterModel();

  void update(HistoryFilterModel Function(HistoryFilterModel) fn) {
    state = fn(state);
  }
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilterModel>(
  HistoryFilterNotifier.new,
);

/// Λίστα κλήσεων ιστορικού με βάση τα τρέχοντα φίλτρα.
/// Η αναζήτηση keyword γίνεται στη βάση μέσω `calls.search_index` (κανονικοποιημένο).
final historyCallsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final filter = ref.watch(historyFilterProvider);
  final keyword = filter.keyword.trim();
  final normalizedKeyword = SearchTextNormalizer.normalizeForSearch(keyword);

  return DatabaseHelper.instance.getHistoryCalls(
    dateFrom: filter.dateFromSql,
    dateTo: filter.dateToSql,
    category: filter.category != null && filter.category!.isEmpty
        ? null
        : filter.category,
    keyword: keyword.isEmpty ? null : normalizedKeyword,
  );
});

/// Λίστα ονομάτων κατηγοριών για το dropdown φίλτρου.
final historyCategoriesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  return DatabaseHelper.instance.getCategoryNames();
});

/// Ενεργές κατηγορίες (id + όνομα) για φόρμα κλήσης / επίλυση category_id.
final historyCategoryEntriesProvider =
    FutureProvider.autoDispose<List<({int id, String name})>>((ref) async {
  final rows = await DatabaseHelper.instance.getActiveCategoryRows();
  return rows
      .map((m) => (
            id: m['id'] as int,
            name: (m['name'] as String?)?.trim() ?? '',
          ))
      .where((e) => e.name.isNotEmpty)
      .toList();
});
