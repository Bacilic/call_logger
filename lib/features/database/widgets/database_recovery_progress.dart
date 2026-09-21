import 'dart:async';

import 'package:flutter/material.dart';

/// Κρατά στην οθόνη ένδειξη ότι δουλεύει, όσο τρέχει μια αργή ανάκαμψη βάσης.
///
/// **Γιατί υπάρχει:** οι οθόνες ανάκαμψης ρωτούν τον χρήστη, **κλείνουν** τον
/// διάλογο επιλογής, και μετά αντιγράφουν ολόκληρο το αρχείο της βάσης ή το
/// ανοίγουν με μετάπτωση. Ως τις 19/09/2026 αυτό γινόταν χωρίς καμία ένδειξη:
/// ο χρήστης κοιτούσε την οθόνη σφάλματος να μη σαλεύει για δευτερόλεπτα — και
/// σε φάκελο δικτύου για πολλά περισσότερα — χωρίς να ξέρει αν πάτησε σωστά.
/// Το πιθανότερο που έκανε ήταν να ξαναπατήσει.
///
/// **Γιατί τυλίγει τη δουλειά αντί να δίνει «άνοιξε»/«κλείσε»:** ένα ζευγάρι
/// συναρτήσεων επιτρέπει στον καλούντα να ξεχάσει το κλείσιμο σε κάποιο
/// πρόωρο `return` — και τότε η ένδειξη μένει για πάντα πάνω από την
/// εφαρμογή, σε οθόνη που υπάρχει ακριβώς για να ξεμπλοκάρει. Εδώ το κλείσιμο
/// είναι `finally`: γίνεται και όταν η δουλειά πετάξει.
///
/// Δεν αντικαθιστά τον κοινό εκτελεστή εναλλαγής διαδρομής: εκείνος φυλάει τη
/// **σειρά** των βημάτων μιας εναλλαγής, ενώ εδώ η σειρά είναι της ανάκαμψης
/// και διαφέρει ανά επιλογή. Κοινό είναι μόνο το «δείξε ότι δουλεύεις».
Future<T> withDatabaseRecoveryProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() work,
) async {
  if (!context.mounted) return work();

  // Ο navigator κρατιέται ΠΡΙΝ από το πρώτο `await`: μετά από αυτό το
  // `context` μπορεί να μην ανήκει πια σε ζωντανό δέντρο.
  final navigator = Navigator.of(context, rootNavigator: true);
  var shown = false;

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _RecoveryProgressDialog(message: message),
    ),
  );
  shown = true;

  try {
    return await work();
  } finally {
    if (shown && navigator.mounted) {
      navigator.pop();
    }
  }
}

class _RecoveryProgressDialog extends StatelessWidget {
  const _RecoveryProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // Χωρίς έξοδο: η δουλειά αγγίζει το αρχείο της βάσης, και μια ακύρωση στη
    // μέση θα άφηνε μισοτελειωμένο αντίγραφο χωρίς να το ξέρει κανείς.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              height: 40,
              width: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
