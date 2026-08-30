import 'package:sqflite_common/sqlite_api.dart';

import '../../features/operators/avatars/operator_avatar_assignment.dart';
import '../models/operator.dart';

/// Δίνει εικονίδιο στα προφίλ που δεν έχουν ακόμη.
///
/// **Πού χρησιμοποιείται:** στη μετάπτωση που γέννησε τη στήλη, ώστε οι
/// συνάδελφοι που ήδη δουλεύουν να δουν εικονίδια από την πρώτη εκκίνηση αντί
/// για μια σειρά από ίδια ανθρωπάκια.
///
/// **Γιατί δεν ζει μαζί με τη λογική επιλογής:** εκείνη δουλεύει με σκέτα
/// μοντέλα και δεν αγγίζει βάση· εδώ γίνεται η εγγραφή. Ο χωρισμός κρατά τον
/// κανόνα «SQL μόνο στο `core/database`» χωρίς να αντιγράφεται η πολιτική
/// μοναδικότητας σε δεύτερο σημείο.
///
/// Ενεργεί μόνο σε προφίλ **χωρίς** εικονίδιο: όποιος έχει ήδη διαλέξει δεν
/// χάνει την επιλογή του, όσες φορές κι αν ξανατρέξει.
Future<int> assignAvatarsToExistingOperators(DatabaseExecutor db) async {
  final rows = await db.query('operators');
  final operators = [for (final row in rows) Operator.fromMap(row)];

  final taken = takenAvatarKeys(operators);
  var assigned = 0;

  // Πρώτα οι ενεργοί. Μόνο αυτοί δεσμεύουν εικονίδιο, οπότε αν έπαιρναν σειρά
  // ανακατεμένοι με τους απενεργοποιημένους, ένα εικονίδιο μόλις δοσμένο σε
  // απενεργοποιημένο θα ξαναδινόταν αμέσως μετά σε ενεργό — δύο προφίλ με το
  // ίδιο πρόσωπο, από την πρώτη κιόλας εκκίνηση.
  final ordered = [
    for (final operator in operators)
      if (operator.isActive) operator,
    for (final operator in operators)
      if (!operator.isActive) operator,
  ];

  for (final operator in ordered) {
    if (operator.id == null) continue;
    if (operator.avatarKey != null) continue;

    final key = pickAvatarKey(taken);
    // Τελείωσαν τα εικονίδια: τα υπόλοιπα προφίλ μένουν με το κλασικό
    // ανθρωπάκι. Δεν είναι σφάλμα και δεν υπάρχει λόγος να συνεχιστεί ο βρόχος.
    if (key == null) break;

    // Και τα απενεργοποιημένα κρατούν ό,τι πήραν, αλλά μόνο τα ενεργά
    // δεσμεύουν — ίδιο συμβόλαιο με τη ζωντανή εφαρμογή.
    if (operator.isActive) taken.add(key);

    await db.update(
      'operators',
      {'avatar_key': key},
      where: 'id = ?',
      whereArgs: [operator.id],
    );
    assigned++;
  }
  return assigned;
}
