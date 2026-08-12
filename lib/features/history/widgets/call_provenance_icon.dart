import 'package:flutter/material.dart';

import '../../calls/models/call_refined_source.dart';

/// Το εικονίδιο που λέει **ποιανού είναι τα λόγια** της Περιγραφής.
///
/// Τρεις καταστάσεις, τρία διαφορετικά σχήματα — όχι τρεις αποχρώσεις του
/// ίδιου. Σε 14 pixel η απόχρωση δεν διαβάζεται με μια ματιά, το σχήμα ναι.
/// Το χειρόγραφο παίρνει επιπλέον ουδέτερο χρώμα: τα λόγια του χρήστη
/// σημειώνονται, δεν διαφημίζονται σαν παραγωγή μηχανής.
///
/// Ζει σε ένα σημείο επίτηδες. Το δείχνουν και η στήλη «Περιγραφή» του
/// Ιστορικού Κλήσεων και η καρτέλα επεξεργασίας· δύο αντίγραφα της ίδιας
/// αντιστοίχισης θα απέκλιναν σιωπηλά με την πρώτη αλλαγή.
class CallProvenanceIcon extends StatelessWidget {
  const CallProvenanceIcon({super.key, required this.source, this.size = 14});

  /// Η ωμή τιμή του `calls.refined_source`.
  final String? source;

  final double size;

  /// Ποιο σχήμα δηλώνει την κάθε προέλευση.
  ///
  /// Το συμβόλαιο είναι ότι τα τρία είναι **ανά δύο διακριτά**, όχι η
  /// συγκεκριμένη επιλογή σχήματος. Άγνωστη τιμή κρατά το σχήμα της ΤΝ, όπως
  /// συμπεριφερόταν το Ιστορικό πριν μπει η διάκριση.
  static IconData iconFor(String? source) => switch ((source ?? '').trim()) {
    CallRefinedSource.manual => Icons.edit_outlined,
    CallRefinedSource.aiEdited => Icons.auto_fix_high_outlined,
    CallRefinedSource.ai => Icons.auto_awesome_outlined,
    _ => Icons.auto_awesome_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isManual = (source ?? '').trim() == CallRefinedSource.manual;
    return Icon(
      iconFor(source),
      size: size,
      color: isManual ? scheme.onSurfaceVariant : scheme.primary,
    );
  }
}
