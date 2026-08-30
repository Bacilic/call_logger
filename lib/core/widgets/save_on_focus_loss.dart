import 'package:flutter/material.dart';

/// Τυλίγει πεδίο ρύθμισης ώστε η τιμή του να αποθηκεύεται **και** όταν ο
/// χρήστης φεύγει από το πεδίο — όχι μόνο όταν πατά Enter.
///
/// Το `onEditingComplete` και το `onSubmitted` ενός `TextField` ζητούν και τα
/// δύο Enter. Όποιος γράφει και μετά κάνει κλικ αλλού, ή φεύγει από την οθόνη,
/// βλέπει την παλιά τιμή να επιστρέφει — χωρίς μήνυμα, σαν να μην πληκτρολόγησε
/// ποτέ. Η οθόνη Ρυθμίσεων δεν έχει κουμπί «Αποθήκευση»: κάθε διακόπτης της
/// γράφει μόλις τον αγγίξεις, οπότε το ίδιο οφείλουν να κάνουν και τα πεδία.
///
/// Δεν αντικαθιστά το Enter — το συμπληρώνει. Το [onLostFocus] πρέπει να
/// αντέχει να κληθεί δύο φορές με την ίδια τιμή (Enter και μετά έξοδος).
class SaveOnFocusLoss extends StatelessWidget {
  const SaveOnFocusLoss({
    required this.onLostFocus,
    required this.child,
    super.key,
  });

  /// Καλείται τη στιγμή που η εστίαση φεύγει από το [child].
  final VoidCallback onLostFocus;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Κόμβος που δεν παίρνει ο ίδιος εστίαση: μόνο ακούει τα παιδιά του,
      // ώστε το πεδίο μέσα να συμπεριφέρεται ακριβώς όπως πριν.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) onLostFocus();
      },
      child: child,
    );
  }
}
