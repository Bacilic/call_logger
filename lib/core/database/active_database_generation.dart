import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Πόσες φορές άλλαξε η ενεργή βάση σε αυτή τη συνεδρία.
///
/// Ο αριθμός δεν έχει καμία σημασία από μόνος του — μετράει **μόνο ότι
/// άλλαξε**. Είναι το σήμα «ό,τι δείχνεις ήρθε από βάση που δεν διαβάζουμε
/// πια».
///
/// Υπάρχει επειδή η εκκαθάριση των Riverpod caches φτάνει μόνο σε ό,τι ζει σε
/// provider. Οθόνες που κρατούν δεδομένα βάσης στη **δική τους κατάσταση**
/// (φορτωμένες γραμμές, επιλεγμένος πίνακας) δεν την ακούν, και μετά από
/// εναλλαγή συνεχίζουν να δείχνουν την προηγούμενη βάση. Ένα `ref.listen` σε
/// αυτό τον provider τις συνδέει με μία γραμμή.
///
/// **Δεν είναι εναλλακτική της εκκαθάρισης** — είναι η συνέχειά της για όσα
/// δεν μπορεί να αγγίξει: αυξάνεται μέσα στο ίδιο σημείο
/// (`invalidateDatabaseScopedCaches`), ώστε τα δύο να μη γίνεται να αποκλίνουν.
final activeDatabaseGenerationProvider =
    NotifierProvider<ActiveDatabaseGenerationNotifier, int>(
      ActiveDatabaseGenerationNotifier.new,
    );

class ActiveDatabaseGenerationNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Δηλώνει ότι από εδώ και πέρα διαβάζουμε άλλη βάση.
  void bump() => state = state + 1;
}
