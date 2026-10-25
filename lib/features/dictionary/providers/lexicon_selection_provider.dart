import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lexicon_selection.dart';

/// Η επιλογή λέξεων της οθόνης Λεξικού. Ζει όσο ζει η οθόνη: φεύγοντας από
/// το Λεξικό, ή αλλάζοντας βάση, δεν μένουν επιλεγμένες λέξεις άλλης λίστας.
class LexiconSelectionNotifier extends Notifier<LexiconSelection> {
  @override
  LexiconSelection build() => const LexiconSelection();

  void toggle(Map<String, dynamic> row) => state = state.toggle(row);

  void selectRange(
    List<Map<String, dynamic>> visible,
    Map<String, dynamic> target,
  ) => state = state.selectRange(visible, target);

  void addAll(Iterable<Map<String, dynamic>> rows) =>
      state = state.addAll(rows);

  void removeAll(Iterable<Map<String, dynamic>> rows) =>
      state = state.removeAll(rows);

  /// Κουτάκι επικεφαλίδας: γεμάτη σελίδα αδειάζει, αλλιώς γεμίζει.
  void togglePage(List<Map<String, dynamic>> page) {
    state = state.pageState(page) == true
        ? state.removeAll(page)
        : state.addAll(page);
  }

  void clear() => state = const LexiconSelection();
}

final lexiconSelectionProvider =
    NotifierProvider.autoDispose<LexiconSelectionNotifier, LexiconSelection>(
      LexiconSelectionNotifier.new,
    );
