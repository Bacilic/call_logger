/// Τι δείχνουμε δίπλα σε κάθε υποψήφιο, όταν οι υποψήφιοι μοιάζουν μεταξύ τους.
///
/// **Το πρόβλημα που λύνει (14/09/2026):** για την τιμή «ΑΙΜΑΤΟΛΟΓΙΚΟ»
/// προτείνονταν πέντε γραφεία, όλα με ένδειξη «Ομοιότητα: 72%» και όλα με
/// «τμήμα=Αιματολογικό Εργαστήριο». Καμία από τις δύο πληροφορίες δεν βοηθούσε
/// να ξεχωρίσει κανείς: το ποσοστό ήταν σταθερά, και το τμήμα ήταν ίδιο και
/// στους πέντε. Ό,τι πραγματικά τους χώριζε — πόσος εξοπλισμός κρέμεται από
/// τον καθένα, ποιος είναι υπεύθυνος, ποιο τηλέφωνο — υπήρχε στη βάση και δεν
/// έφτανε ποτέ στην οθόνη.
///
/// **Ο κανόνας:** ένα χαρακτηριστικό αξίζει χώρο μόνο αν **διαφέρει** μέσα
/// στη συγκεκριμένη λίστα. Το ίδιο πεδίο μπορεί να είναι πολύτιμο σε μια
/// επιλογή και καθαρός θόρυβος στην επόμενη — γι' αυτό η κρίση γίνεται ανά
/// λίστα υποψηφίων και ποτέ με σταθερή λίστα πεδίων.
library;

/// Ένα χαρακτηριστικό υποψηφίου: πώς λέγεται και τι αξία έχει εδώ.
class LampCandidateFacet {
  const LampCandidateFacet(this.label, this.value);

  /// Πώς παρουσιάζεται στον χρήστη («εξοπλισμοί», «υπεύθυνος», «τηλέφωνο»).
  final String label;

  /// Η τιμή για τον συγκεκριμένο υποψήφιο. Κενή σημαίνει «δεν έχει» — και
  /// αυτό είναι πληροφορία: ένα γραφείο χωρίς τηλέφωνο ξεχωρίζει από ένα με.
  final String value;

  @override
  String toString() => '$label=$value';
}

/// Κρατά, για κάθε υποψήφιο, μόνο τα χαρακτηριστικά που τον **ξεχωρίζουν**.
///
/// Ένα χαρακτηριστικό επιβιώνει αν δύο υποψήφιοι της λίστας δίνουν
/// διαφορετική τιμή γι' αυτό. Όσα είναι ίδια παντού αφαιρούνται: δεν βοηθούν
/// σε τίποτα και σπρώχνουν κάτω ό,τι μετράει.
///
/// Με **έναν** υποψήφιο δεν επιστρέφεται τίποτα — δεν υπάρχει από ποιον να
/// ξεχωρίσει.
Map<int, List<LampCandidateFacet>> distinguishingFacets(
  Map<int, List<LampCandidateFacet>> facetsById,
) {
  if (facetsById.length < 2) {
    return <int, List<LampCandidateFacet>>{
      for (final id in facetsById.keys) id: const <LampCandidateFacet>[],
    };
  }

  // Η απουσία τιμής μετράει ως τιμή: αν το ένα γραφείο έχει τηλέφωνο και το
  // άλλο όχι, το τηλέφωνο ΕΙΝΑΙ διακριτικό.
  final valuesByLabel = <String, Set<String>>{};
  for (final facets in facetsById.values) {
    for (final facet in facets) {
      valuesByLabel.putIfAbsent(facet.label, () => <String>{});
    }
  }
  for (final label in valuesByLabel.keys) {
    for (final facets in facetsById.values) {
      final match = facets.where((f) => f.label == label);
      valuesByLabel[label]!.add(match.isEmpty ? '' : match.first.value.trim());
    }
  }

  final distinguishing = <String>{
    for (final entry in valuesByLabel.entries)
      if (entry.value.length > 1) entry.key,
  };

  return <int, List<LampCandidateFacet>>{
    for (final entry in facetsById.entries)
      entry.key: <LampCandidateFacet>[
        for (final facet in entry.value)
          if (distinguishing.contains(facet.label) &&
              facet.value.trim().isNotEmpty)
            facet,
      ],
  };
}

/// Η μία γραμμή που διαβάζει ο χρήστης κάτω από το όνομα του υποψηφίου.
///
/// Κενή όταν τίποτα δεν ξεχωρίζει — και τότε η οθόνη σωστά δεν γράφει τίποτα,
/// αντί για μια σειρά από πανομοιότυπες λεπτομέρειες.
String candidateFacetsSummary(List<LampCandidateFacet> facets) {
  final parts = <String>[
    for (final facet in facets)
      if (facet.value.trim().isNotEmpty)
        '${facet.label}: ${facet.value.trim()}',
  ];
  return parts.join(' · ');
}
