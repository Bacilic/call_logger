import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Όταν αυξάνεται, η οθόνη Λεξικού ανοίγει τον διάλογο ⚙ «Ρυθμίσεις λεξικού».
///
/// Ο διάλογος χρειάζεται τις βαριές ροές της οθόνης (εισαγωγή αρχείου,
/// compile), οπότε δεν μπορεί να ανοίξει από αλλού· ζητιέται από εδώ και τον
/// ανοίγει η ίδια η οθόνη.
///
/// Μετρητής και όχι σημαία: το αίτημα φτάνει συχνά **πριν** χτιστεί η οθόνη,
/// οπότε αυτή κρατά τη δική της αφετηρία και συγκρίνει — μια σημαία που είναι
/// ήδη ανεβασμένη δεν παράγει ποτέ μετάβαση να ακούσει.
class DictionarySettingsRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() {
    state = state + 1;
  }
}

final dictionarySettingsRequestProvider =
    NotifierProvider<DictionarySettingsRequestNotifier, int>(
      DictionarySettingsRequestNotifier.new,
    );
