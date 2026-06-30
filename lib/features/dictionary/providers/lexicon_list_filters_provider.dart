import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/settings_repository.dart';
import '../models/lexicon_list_filters_model.dart';

const kLexiconListFiltersSettingKey = 'lexicon_list_filters';

/// Απομνημόνευση φίλτρων λίστας λεξικού (όχι αναζήτηση κειμένου).
class LexiconListFiltersNotifier extends Notifier<LexiconListFiltersModel> {
  final Completer<void> _hydrationCompleter = Completer<void>();

  /// Ολοκληρώθηκε η ανάγνωση φίλτρων από τη βάση (ανεξάρτητα από αλλαγή state).
  Future<void> get hydrationFuture => _hydrationCompleter.future;

  @override
  LexiconListFiltersModel build() {
    Future<void>(_hydrateFromDb);
    return const LexiconListFiltersModel();
  }

  Future<void> _hydrateFromDb() async {
    try {
      final db = await DatabaseHelper.instance.database;
      if (!ref.mounted) return;
      final raw = await SettingsRepository(db)
          .getSetting(kLexiconListFiltersSettingKey);
      if (!ref.mounted) return;
      state = LexiconListFiltersModel.decodeFromStorage(raw);
    } finally {
      if (!_hydrationCompleter.isCompleted) {
        _hydrationCompleter.complete();
      }
    }
  }

  Future<void> _persist() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(
      kLexiconListFiltersSettingKey,
      state.encodeForStorage(),
    );
  }

  Future<void> replace(LexiconListFiltersModel next, {bool persist = true}) async {
    state = next;
    if (persist) await _persist();
  }

  Future<void> setLangFilter(String? value) async {
    state = state.copyWith(langFilter: value, page: 0);
    await _persist();
  }

  Future<void> setSourceFilter(String? value) async {
    state = state.copyWith(sourceFilter: value, page: 0);
    await _persist();
  }

  Future<void> setCategoryFilter(String? value) async {
    state = state.copyWith(categoryFilter: value, page: 0);
    await _persist();
  }

  Future<void> setColumnGroups(int? value) async {
    state = state.copyWith(columnGroups: value);
    await _persist();
  }

  Future<void> setLettersCompareOp(String value) async {
    state = state.copyWith(lettersCompareOp: value, page: 0);
    await _persist();
  }

  Future<void> setLettersCount(String value) async {
    state = state.copyWith(
      lettersCount: LexiconListFiltersModel.sanitizeLettersCount(value),
      page: 0,
    );
    await _persist();
  }

  Future<void> setDiacriticMarksFilter(String? value) async {
    state = state.copyWith(diacriticMarksFilter: value, page: 0);
    await _persist();
  }

  Future<void> setPage(int page) async {
    final safe = page < 0 ? 0 : page;
    if (safe == state.page) return;
    state = state.copyWith(page: safe);
    await _persist();
  }

  Future<void> resetPage() async {
    if (state.page == 0) return;
    state = state.copyWith(page: 0);
    await _persist();
  }
}

final lexiconListFiltersProvider =
    NotifierProvider.autoDispose<LexiconListFiltersNotifier, LexiconListFiltersModel>(
  LexiconListFiltersNotifier.new,
);
