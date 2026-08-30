import '../../../core/models/owner_filter.dart';
import '../providers/operator_directory_providers.dart';

/// Οι επιλογές ενός φίλτρου «χρήστης», με τη σειρά που εμφανίζονται.
///
/// «Όλοι» πάντα πρώτο, μετά τα ονόματα αλφαβητικά, και «Χωρίς χρήστη»
/// τελευταίο — μόνο όταν υπάρχουν όντως τέτοιες εγγραφές.
///
/// Οι Εκκρεμότητες και το Ιστορικό ρωτούν διαφορετικούς πίνακες αλλά χτίζουν
/// **την ίδια** λίστα: γράφεται εδώ μία φορά, ώστε μια αλλαγή στον τρόπο που
/// εμφανίζεται ένα όνομα να μην ξεχάσει το ένα από τα δύο.
List<OwnerFilterOption> buildOwnerFilterOptions({
  required Set<int> ownerIds,
  required Map<int, String>? names,
  required bool hasUnassigned,
}) {
  final named =
      ownerIds
          .map(
            (id) => OwnerFilterOption(
              value: OwnerFilter.byOperator(id),
              // Χρήστης που δεν βρίσκεται πια στον πίνακα δεν κρύβεται: οι
              // εγγραφές του υπάρχουν και πρέπει να μπορούν να βρεθούν.
              label: operatorDisplayNameFor(names, id),
            ),
          )
          .toList()
        ..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );

  return <OwnerFilterOption>[
    const OwnerFilterOption(value: OwnerFilter.everyone, label: 'Όλοι'),
    ...named,
    if (hasUnassigned)
      const OwnerFilterOption(
        value: OwnerFilter.unassigned,
        label: 'Χωρίς χρήστη',
      ),
  ];
}
