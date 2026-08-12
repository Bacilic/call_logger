import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/category_repository.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/id_search_query.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../models/dashboard_summary_model.dart';
import '../models/lansweeper_sync_state.dart';

/// Μοντέλο φίλτρων για το ιστορικό κλήσεων.
class HistoryFilterModel {
  const HistoryFilterModel({
    this.keyword = '',
    this.dateFrom,
    this.dateTo,
    this.category,
    this.onlyWithTask = false,
    this.lansweeperState,
  });

  final String keyword;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? category;

  /// Μόνο κλήσεις με ζωντανή συνδεδεμένη εκκρεμότητα.
  final bool onlyWithTask;

  /// Μόνο κλήσεις σε αυτή την κατάσταση Lansweeper· `null` σημαίνει «όλες».
  ///
  /// Αντικατέστησε ένα δυαδικό «με αίτημα Lansweeper», που δεν μπορούσε να
  /// ξεχωρίσει την εξαιρεμένη από την ακαταχώρητη — καμία από τις δύο δεν έχει
  /// αριθμό αιτήματος, οπότε και οι δύο έπεφταν έξω από το παλιό φίλτρο.
  final String? lansweeperState;

  HistoryFilterModel copyWith({
    String? keyword,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? category,
    bool? onlyWithTask,
    String? lansweeperState,
    bool clearDateRange = false,
    bool clearCategory = false,
    bool clearLansweeperState = false,
  }) {
    return HistoryFilterModel(
      keyword: keyword ?? this.keyword,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      category: clearCategory ? null : (category ?? this.category),
      onlyWithTask: onlyWithTask ?? this.onlyWithTask,
      lansweeperState: clearLansweeperState
          ? null
          : (lansweeperState ?? this.lansweeperState),
    );
  }

  /// Ημερομηνία από σε yyyy-MM-dd για SQL.
  String? get dateFromSql => dateFrom != null ? _formatDate(dateFrom!) : null;

  String? get dateToSql => dateTo != null ? _formatDate(dateTo!) : null;

  /// Τα ονόματα των φίλτρων που περιορίζουν αυτή τη στιγμή τη λίστα.
  ///
  /// Χρησιμεύει σε όποιον αλλάζει το πλαίσιο απ' έξω, ώστε να μπορεί να πει στον
  /// χρήστη τι ακριβώς έπαψε να ισχύει.
  List<String> get activeFilterLabels => [
    if (keyword.trim().isNotEmpty) 'αναζήτηση',
    if (dateFrom != null || dateTo != null) 'ημερομηνίες',
    if (category != null && category!.trim().isNotEmpty) 'κατηγορία',
    if (onlyWithTask) 'με εκκρεμότητα',
    if (hasLansweeperStateFilter)
      'Lansweeper: ${LansweeperSyncState.labelPlural(lansweeperState)}',
  ];

  /// True όταν το φίλτρο κατάστασης περιορίζει όντως τη λίστα.
  bool get hasLansweeperStateFilter =>
      lansweeperState != null && lansweeperState!.trim().isNotEmpty;

  /// True όταν υπάρχει ενεργό φίλτρο (αναζήτηση, ημερομηνίες ή κατηγορία).
  bool get hasActiveFilters =>
      keyword.trim().isNotEmpty ||
      dateFrom != null ||
      dateTo != null ||
      (category != null && category!.trim().isNotEmpty) ||
      onlyWithTask ||
      hasLansweeperStateFilter;

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

  /// Πλαίσιο μετάβασης από άλλη οθόνη: ό,τι δεν δηλώνεται εδώ **μηδενίζεται**.
  ///
  /// Η [update] κρατά ό,τι ίσχυε — σωστό για τα χειριστήρια του ίδιου του
  /// Ιστορικού, λάθος για όποιον έρχεται απ' έξω: ένα φίλτρο κατηγορίας που είχε
  /// μείνει από προηγούμενη δουλειά θα έκρυβε ακριβώς τις κλήσεις που ζητήθηκαν,
  /// και ο χρήστης θα έβλεπε «δεν βρέθηκαν κλήσεις» χωρίς να ξέρει γιατί.
  ///
  /// Επιστρέφει τα ονόματα των φίλτρων που έπαψαν να ισχύουν, ώστε ο καλών να
  /// μπορεί να το ανακοινώσει. Φίλτρο που αντικαταστάθηκε (π.χ. άλλες
  /// ημερομηνίες) δεν μετράει ως καθαρισμένο — δεν χάθηκε, άλλαξε.
  List<String> focus({
    String keyword = '',
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    final before = state.activeFilterLabels;
    state = HistoryFilterModel(
      keyword: keyword,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    final after = state.activeFilterLabels.toSet();
    return before.where((label) => !after.contains(label)).toList();
  }
}

/// Μήνυμα για τα φίλτρα που καθάρισε μια μετάβαση· `null` όταν δεν έφυγε κανένα.
String? historyFiltersClearedMessage(List<String> cleared) {
  if (cleared.isEmpty) return null;
  if (cleared.length == 1) {
    return 'Καθαρίστηκε το φίλτρο: ${cleared.single}.';
  }
  return 'Καθαρίστηκαν τα φίλτρα: ${cleared.join(', ')}.';
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilterModel>(
      HistoryFilterNotifier.new,
    );

/// Οι στήλες δεδομένων του πίνακα ιστορικού που ταξινομούνται.
///
/// Η σειρά των τιμών ταυτίζεται με τη σειρά των στηλών στον πίνακα — έτσι όποιος
/// ζητά ταξινόμηση γράφει το όνομα της στήλης αντί για γυμνό αριθμό θέσης.
enum HistorySortColumn {
  dateTime,
  caller,
  phone,
  department,
  equipment,
  category,
  notes,
  duration,
  links,
}

/// Ταξινόμηση του πίνακα ιστορικού.
///
/// Ζει σε provider και όχι μέσα στον πίνακα, ώστε όποιος στέλνει τον χρήστη στο
/// Ιστορικό — π.χ. τα κουμπιά «Προβολή όλων» του Πίνακα Ελέγχου — να ορίζει και
/// με ποια σειρά θα δει τις κλήσεις.
class HistorySortModel {
  const HistorySortModel({this.column, this.ascending = true});

  /// `null` σημαίνει καμία ταξινόμηση: ισχύει η σειρά που δίνει η βάση.
  final HistorySortColumn? column;
  final bool ascending;
}

class HistorySortNotifier extends Notifier<HistorySortModel> {
  @override
  HistorySortModel build() => const HistorySortModel();

  void apply(HistorySortModel sort) => state = sort;

  /// Πάτημα κεφαλίδας: η ίδια στήλη αντιστρέφει τη φορά, νέα στήλη ξεκινά αύξουσα.
  void toggle(HistorySortColumn column) {
    state = state.column == column
        ? HistorySortModel(column: column, ascending: !state.ascending)
        : HistorySortModel(column: column);
  }
}

final historySortProvider =
    NotifierProvider<HistorySortNotifier, HistorySortModel>(
      HistorySortNotifier.new,
    );

/// Η ταξινόμηση που αναπαράγει στο Ιστορικό τη σειρά της κάρτας «Κορυφαίοι
/// Καλούντες»: αλφαβητικά ανά άτομο, ώστε οι κλήσεις καθενός να είναι μαζί.
const HistorySortModel historySortForTopCallers = HistorySortModel(
  column: HistorySortColumn.caller,
);

/// Η ταξινόμηση που αναπαράγει τη σειρά της κάρτας χρόνου.
///
/// Οι δύο όψεις της απαντούν σε διαφορετικό ερώτημα: «ανά κλήση» ρωτά ποια κλήση
/// κράτησε περισσότερο (μεγαλύτερες διάρκειες πρώτες), «ανά άτομο» ποιος
/// τηλεφωνεί (ομαδοποίηση ανά καλούντα).
HistorySortModel historySortForLongestCalls(LongestCallsMode mode) =>
    switch (mode) {
      LongestCallsMode.perCall => const HistorySortModel(
        column: HistorySortColumn.duration,
        ascending: false,
      ),
      LongestCallsMode.perPerson => historySortForTopCallers,
    };

/// Όνομα αρχείου ενεργής βάσης (για μηνύματα σφάλματος).
final historyDatabaseDisplayNameProvider = FutureProvider.autoDispose<String>((
  ref,
) async {
  try {
    final db = await DatabaseHelper.instance.database;
    return p.basename(db.path);
  } catch (_) {
    final path = await SettingsService().getDatabasePath();
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '—';
    return p.basename(trimmed);
  }
});

/// Συνολικό πλήθος εγγραφών στον πίνακα calls (χωρίς φίλτρα UI).
final totalCallsCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final db = await DatabaseHelper.instance.database;
  return CallsRepository(db).getTotalCallCount();
});

/// Πλήθος κλήσεων ιστορικού με βάση φίλτρα ημερομηνίας και κατηγορίας (χωρίς keyword).
final historyCategoryDateCallCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final filter = ref.watch(historyFilterProvider);
  final db = await DatabaseHelper.instance.database;
  return CallsRepository(db).getHistoryCallCount(
    dateFrom: filter.dateFromSql,
    dateTo: filter.dateToSql,
    category: filter.category != null && filter.category!.isEmpty
        ? null
        : filter.category,
  );
});

/// Λίστα κλήσεων ιστορικού με βάση τα τρέχοντα φίλτρα.
/// Η αναζήτηση keyword γίνεται στη βάση μέσω `calls.search_index` (κανονικοποιημένο).
final historyCallsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final filter = ref.watch(historyFilterProvider);
      // Ο ίδιος κανόνας «#id» με τον Κατάλογο: το «#276» δείχνει την κλήση 276
      // και μόνο αυτήν, ενώ οι υπόλοιποι όροι μένουν ελεύθερο κείμενο.
      final query = IdSearchQuery.parse(filter.keyword);
      // «#» χωρίς αριθμό δεν ταιριάζει τίποτα — ειλικρινές «κανένα
      // αποτέλεσμα», αντί για σιωπηλή μετάπτωση σε αναζήτηση κειμένου.
      if (query.hasInvalidIdToken) return const <Map<String, dynamic>>[];

      final normalizedKeyword = SearchTextNormalizer.normalizeForSearch(
        query.text,
      );

      final db = await DatabaseHelper.instance.database;
      final calls = CallsRepository(db);
      return calls.getHistoryCalls(
        dateFrom: filter.dateFromSql,
        dateTo: filter.dateToSql,
        category: filter.category != null && filter.category!.isEmpty
            ? null
            : filter.category,
        keyword: normalizedKeyword.isEmpty ? null : normalizedKeyword,
        onlyWithTask: filter.onlyWithTask,
        lansweeperState: filter.lansweeperState,
        callIds: query.ids,
      );
    });

/// Λίστα ονομάτων κατηγοριών για το dropdown φίλτρου.
final historyCategoriesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final db = await DatabaseHelper.instance.database;
  return CategoryRepository(db).getCategoryNames();
});

/// Ενεργές κατηγορίες (id + όνομα) για φόρμα κλήσης / επίλυση category_id.
final historyCategoryEntriesProvider =
    FutureProvider.autoDispose<List<({int id, String name})>>((ref) async {
      final db = await DatabaseHelper.instance.database;
      final rows = await CategoryRepository(db).getActiveCategoryRows();
      return rows
          .map(
            (m) => (
              id: m['id'] as int,
              name: (m['name'] as String?)?.trim() ?? '',
            ),
          )
          .where((e) => e.name.isNotEmpty)
          .toList();
    });

class HistorySelectedCallIdsNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => <int>{};

  void setAll(Set<int> ids) {
    state = ids;
  }

  void clear() {
    state = <int>{};
  }
}

/// Επιλεγμένα call ids στον πίνακα ιστορικού (multi-select για μαζικές ενέργειες).
final historySelectedCallIdsProvider =
    NotifierProvider.autoDispose<HistorySelectedCallIdsNotifier, Set<int>>(
      HistorySelectedCallIdsNotifier.new,
    );
