// Τι δείχνεται δίπλα σε υποψήφιους που μοιάζουν μεταξύ τους.
//
// Σενάριο 14/09: για την τιμή «ΑΙΜΑΤΟΛΟΓΙΚΟ» προτείνονται πέντε γραφεία (66,
// 282, 283, 281, 186) με ίδιο τμήμα, ίδιο κτίριο και ίδιο όροφο. Ό,τι τα
// χωρίζει είναι ο εξοπλισμός, ο υπεύθυνος και το τηλέφωνο.
//
//   flutter test test/core/database/old_database/lamp_candidate_facets_test.dart

import 'package:call_logger/core/database/old_database/lamp_candidate_facets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Τα πραγματικά πέντε γραφεία του σεναρίου, όπως τα δίνει η βάση.
  Map<int, List<LampCandidateFacet>> theFiveOffices() {
    return <int, List<LampCandidateFacet>>{
      66: const <LampCandidateFacet>[
        LampCandidateFacet('τμήμα', 'Αιματολογικό Εργαστήριο'),
        LampCandidateFacet('κτίριο', 'Α'),
        LampCandidateFacet('εξοπλισμοί', '14'),
        LampCandidateFacet('υπεύθυνος', 'Μουράτης Γεώργιος'),
        LampCandidateFacet('τηλέφωνο', '2517'),
      ],
      282: const <LampCandidateFacet>[
        LampCandidateFacet('τμήμα', 'Αιματολογικό Εργαστήριο'),
        LampCandidateFacet('κτίριο', 'Α'),
        LampCandidateFacet('εξοπλισμοί', '7'),
        LampCandidateFacet('υπεύθυνος', 'Μουράτης Γεώργιος'),
        LampCandidateFacet('τηλέφωνο', '2417'),
      ],
      283: const <LampCandidateFacet>[
        LampCandidateFacet('τμήμα', 'Αιματολογικό Εργαστήριο'),
        LampCandidateFacet('κτίριο', 'Α'),
        LampCandidateFacet('εξοπλισμοί', '5'),
        LampCandidateFacet('υπεύθυνος', 'Καράμ Χάνα'),
        LampCandidateFacet('τηλέφωνο', '2517'),
      ],
      281: const <LampCandidateFacet>[
        LampCandidateFacet('τμήμα', 'Αιματολογικό Εργαστήριο'),
        LampCandidateFacet('κτίριο', 'Α'),
        LampCandidateFacet('εξοπλισμοί', '1'),
        LampCandidateFacet('υπεύθυνος', 'Καράμ Χάνα'),
        LampCandidateFacet('τηλέφωνο', '2517'),
      ],
      186: const <LampCandidateFacet>[
        LampCandidateFacet('τμήμα', 'Αιματολογικό Εργαστήριο'),
        LampCandidateFacet('κτίριο', 'Α'),
        LampCandidateFacet('εξοπλισμοί', '0'),
        LampCandidateFacet('υπεύθυνος', 'Καράμ Χάνα'),
        LampCandidateFacet('τηλέφωνο', ''),
      ],
    };
  }

  List<String> labelsFor(Map<int, List<LampCandidateFacet>> kept, int id) =>
      kept[id]!.map((f) => f.label).toList();

  test('ό,τι είναι ίδιο σε όλους δεν επιβιώνει', () {
    final kept = distinguishingFacets(theFiveOffices());
    for (final id in kept.keys) {
      expect(
        labelsFor(kept, id),
        isNot(contains('τμήμα')),
        reason: 'Και τα πέντε ανήκουν στο ίδιο τμήμα — δεν ξεχωρίζει κανένα',
      );
      expect(labelsFor(kept, id), isNot(contains('κτίριο')));
    }
  });

  test('ό,τι διαφέρει επιβιώνει', () {
    final kept = distinguishingFacets(theFiveOffices());
    expect(
      labelsFor(kept, 66),
      containsAll(<String>['εξοπλισμοί', 'υπεύθυνος', 'τηλέφωνο']),
    );
  });

  test('η απουσία τιμής είναι κι αυτή διάκριση', () {
    // Το 186 δεν έχει τηλέφωνο ενώ τα άλλα έχουν: το τηλέφωνο μένει
    // διακριτικό για τη λίστα, και ο υποψήφιος χωρίς αυτό απλώς δεν το δείχνει.
    final kept = distinguishingFacets(theFiveOffices());
    expect(labelsFor(kept, 283), contains('τηλέφωνο'));
    expect(
      labelsFor(kept, 186),
      isNot(contains('τηλέφωνο')),
      reason: 'Κενή τιμή δεν τυπώνεται ως κενό — απλώς λείπει',
    );
  });

  test('με έναν μόνο υποψήφιο δεν υπάρχει τίποτα να ξεχωρίσει', () {
    final kept = distinguishingFacets(<int, List<LampCandidateFacet>>{
      66: const <LampCandidateFacet>[
        LampCandidateFacet('τμήμα', 'Αιματολογικό Εργαστήριο'),
        LampCandidateFacet('εξοπλισμοί', '14'),
      ],
    });
    expect(kept[66], isEmpty);
  });

  test('όταν όλα είναι πανομοιότυπα, δεν δείχνεται τίποτα', () {
    final kept = distinguishingFacets(<int, List<LampCandidateFacet>>{
      1: const <LampCandidateFacet>[LampCandidateFacet('τμήμα', 'Ίδιο')],
      2: const <LampCandidateFacet>[LampCandidateFacet('τμήμα', 'Ίδιο')],
    });
    expect(kept[1], isEmpty);
    expect(kept[2], isEmpty);
  });

  test('η σύνοψη γράφεται με ετικέτα, χωρίς κλίση ονομάτων', () {
    final kept = distinguishingFacets(theFiveOffices());
    final summary = candidateFacetsSummary(kept[66]!);
    expect(summary, contains('εξοπλισμοί: 14'));
    expect(summary, contains('υπεύθυνος: Μουράτης Γεώργιος'));
    expect(summary, isNot(contains('τμήμα')));
  });

  test('χωρίς διακριτικά, η σύνοψη είναι κενή αντί για παύλες', () {
    expect(candidateFacetsSummary(const <LampCandidateFacet>[]), isEmpty);
  });
}
