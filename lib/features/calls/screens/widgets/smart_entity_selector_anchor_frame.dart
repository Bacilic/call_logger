import 'package:flutter/material.dart';

/// Πράσινο πλαίσιο **άγκυρας**: σημαδεύει το πεδίο από το οποίο
/// ξεκίνησε η αναζήτηση, ώστε ο χρήστης να καταλαβαίνει γιατί η πρώτη γραμμή
/// κάθε tooltip μιλά για **αυτή** την οντότητα.
///
/// Εμφανίζεται μόνο όταν υπάρχει τουλάχιστον ένας δείκτης στη φόρμα — και
/// ανεξάρτητα από το αν η ίδια η άγκυρα έχει δείκτη.
///
/// Το χρώμα είναι σκόπιμα **πράσινο**: ουδέτερο, δεν δηλώνει ανησυχία. Το μοβ
/// αποκλείστηκε γιατί το `deepPurple` είναι το χρώμα εστίασης της εφαρμογής και
/// θα συγχεόταν με το πεδίο που απλώς έχει τον κέρσορα.
///
/// Το πλαίσιο είναι **πάντα** στο δέντρο και αλλάζει μόνο χρώμα: υπό όρους
/// τύλιγμα ενός stateful πεδίου θα προκαλούσε remount και απώλεια του κέρσορα
/// κατά την πληκτρολόγηση.
class AnchorFrame extends StatelessWidget {
  const AnchorFrame({super.key, required this.isAnchor, required this.child});

  final bool isAnchor;
  final Widget child;

  static const Color _anchorColor = Color(0xFF2E7D32);
  static const double _inset = 3;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        border: Border.all(
          color: isAnchor ? _anchorColor : Colors.transparent,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}
