import 'package:flutter/material.dart';

/// Το κυλιόμενο σώμα ενός διαλόγου φόρμας.
///
/// Δύο περιθώρια, δύο διαφορετικοί λόγοι — και κανένας από τους δύο δεν είναι
/// αισθητικός:
///
/// - **Οριζόντια.** Το περιθώριο περνά *μέσα* στο κυλιόμενο τμήμα, ώστε η μπάρα
///   κύλισης να κάθεται στην άκρη του διαλόγου και όχι πάνω στα πεδία. Γι' αυτό
///   ο διάλογος δίνει `contentPadding: EdgeInsets.fromLTRB(0, …, 0, …)`.
/// - **Πάνω.** Η ετικέτα ενός πεδίου με περίγραμμα, όταν ανεβαίνει πάνω στη
///   γραμμή του πλαισίου, ζωγραφίζεται **5,5 px έξω από το πεδίο**. Όσο το
///   περιεχόμενο χωράει, δεν φαίνεται τίποτα· μόλις χρειαστεί κύλιση, το
///   κυλιόμενο τμήμα κόβει ό,τι βγαίνει έξω και η πρώτη ετικέτα εμφανίζεται
///   κομμένη στη μέση. Το [kDialogContentTopSlack] είναι ο χώρος που της
///   χρωστάμε.
///
/// Χρησιμοποίησέ το σε **κάθε** διάλογο με κυλιόμενη φόρμα: το περιθώριο έχει
/// ξεχαστεί ήδη τρεις φορές όταν ήταν γραμμένο χειροκίνητα σε κάθε οθόνη.
class DialogScrollableContent extends StatelessWidget {
  const DialogScrollableContent({
    super.key,
    required this.child,
    this.horizontalPadding = 24,
  });

  /// Το περιεχόμενο του διαλόγου — συνήθως [Column] με τα πεδία.
  final Widget child;

  /// Απόσταση από τις πλαϊνές άκρες του διαλόγου.
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        kDialogContentTopSlack,
        horizontalPadding,
        0,
      ),
      child: child,
    );
  }
}

/// Ο χώρος που χρειάζεται η ετικέτα του πρώτου πεδίου για να μην κοπεί.
///
/// Μετρημένο: μια ετικέτα που έχει ανέβει στο περίγραμμα ξεκινά 5,5 px πάνω
/// από το πεδίο της.
const double kDialogContentTopSlack = 6;
