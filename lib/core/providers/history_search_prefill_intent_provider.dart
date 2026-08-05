import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Κατανάλωση από [HistoryScreen]: προσυμπλήρωση του πεδίου αναζήτησης.
///
/// Ίδιο μοτίβο με το [callDepartmentPrefillIntentProvider]: όποιος στέλνει τον
/// χρήστη στο Ιστορικό για να δει συγκεκριμένες κλήσεις γράφει και τον όρο, ώστε
/// να μη χρειάζεται να τον αντιγράψει με το χέρι από μια οδηγία.
class HistorySearchPrefillIntentNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void prefill(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    state = trimmed;
  }

  void clear() {
    state = null;
  }
}

final historySearchPrefillIntentProvider =
    NotifierProvider<HistorySearchPrefillIntentNotifier, String?>(
      HistorySearchPrefillIntentNotifier.new,
    );
