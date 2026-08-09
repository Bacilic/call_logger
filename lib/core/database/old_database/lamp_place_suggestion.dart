/// Πρόταση γραφείου ή τμήματος από ελεύθερο κείμενο.
///
/// Το πεδίο υπαλλήλου της Λάμπας κρατά συχνά χώρο: «Γιατροί Μαιευτικής»,
/// «ΞΕΝΩΝΑΣ», «ΟΔΗΓΟΙ». Η ακριβής σύγκριση δεν βοηθά — «Γιατροί» δεν είναι
/// «Ιατρών» και «Μαιευτικής» δεν είναι «Γυναικολογικής». Η ταύτιση γίνεται
/// σε **ρίζες λέξεων**: η «Μαιευτικής» και η «Μαιευτική-Γυναικολογική
/// Κλινική» μοιράζονται τη ρίζα «μαιευτ».
///
/// Δοκιμασμένο πάνω σε ολόκληρη τη Λάμπα: το «Γιατροί Μαιευτικής» βρίσκει και
/// τα τέσσερα γραφεία της σωστής κλινικής, το «ΟΔΗΓΟΙ» βρίσκει το «Οδηγοί -
/// Γραφείο Γραμματείας ΤΕΙ», και τα ονόματα ανθρώπων δεν βρίσκουν τίποτα.
///
/// Η πρόταση είναι **μόνο ένδειξη**. Δεν συμπληρώνει πεδίο και δεν αποφασίζει
/// — δίνει στον χρήστη σημείο εκκίνησης πριν διαλέξει μόνος του.
library;

import '../../utils/text_similarity.dart';

/// Γραμμή γραφείου όπως τη χρειάζεται η πρόταση, χωρίς εξάρτηση από τη βάση.
typedef LampPlaceRow = ({int id, String? officeName, String? departmentName});

/// Από πόσα γράμματα και πάνω μια λέξη κόβεται σε ρίζα. Κάτω από αυτό
/// συγκρίνεται ολόκληρη: το «ΤΕΠ» δεν έχει ρίζα να κρατήσει.
const int kLampPlaceStemLength = 6;

/// Λέξεις κοντύτερες από αυτό είναι θόρυβος («και», «ΜΤΝ» το κρατάμε οριακά).
const int kLampPlaceMinWordLength = 3;

/// Πάνω από αυτό το πλήθος η πρόταση παύει να κατευθύνει και γίνεται κατάλογος.
const int kLampPlaceMaxSuggestions = 4;

class LampPlaceSuggestion {
  const LampPlaceSuggestion({
    required this.matches,
    required this.sharedDepartment,
    required this.totalMatchCount,
  });

  /// Τα κορυφαία γραφεία, ταξινομημένα — ακριβής ταύτιση πρώτα.
  final List<LampPlaceRow> matches;

  /// Το τμήμα στο οποίο ανήκουν **όλα** τα υποψήφια, αν είναι κοινό. Τότε η
  /// ένδειξη λέει το τμήμα αντί να απαριθμεί τέσσερα γραφεία.
  final String? sharedDepartment;

  /// Πόσα βρέθηκαν συνολικά, πριν την περικοπή.
  final int totalMatchCount;

  bool get isEmpty => matches.isEmpty;

  /// Η ένδειξη σε ανθρώπινη γλώσσα, ή `null` όταν δεν βρέθηκε τίποτα.
  String? get sentence {
    if (matches.isEmpty) return null;
    final names = matches
        .map((m) => (m.officeName ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final more = totalMatchCount - matches.length;
    final tail = more > 0 ? ' και $more ακόμη' : '';
    if (sharedDepartment != null && names.length > 1) {
      return 'Τα κοντινότερα γραφεία ανήκουν όλα στο τμήμα '
          '«$sharedDepartment» — ${names.join(', ')}$tail.';
    }
    if (names.length == 1) {
      final department = (matches.first.departmentName ?? '').trim();
      final scope = department.isEmpty ? '' : ' (τμήμα «$department»)';
      return 'Κοντινότερο γραφείο: ${matches.first.id} · ${names.first}'
          '$scope$tail.';
    }
    return 'Κοντινότερα γραφεία: ${names.join(', ')}$tail.';
  }
}

/// Ψάχνει γραφεία και τμήματα που μοιράζονται ρίζες λέξεων με το [rawValue].
LampPlaceSuggestion lampPlaceSuggestion({
  required String rawValue,
  required Iterable<LampPlaceRow> places,
  int limit = kLampPlaceMaxSuggestions,
}) {
  final needle = _tokens(rawValue);
  if (needle.isEmpty) {
    return const LampPlaceSuggestion(
      matches: <LampPlaceRow>[],
      sharedDepartment: null,
      totalMatchCount: 0,
    );
  }
  final normalizedValue = TextSimilarity.normalize(rawValue);

  final scored = <({int exact, int common, int breadth, LampPlaceRow place})>[];
  for (final place in places) {
    final haystack = _tokens(place.officeName ?? '')
      ..addAll(_tokens(place.departmentName ?? ''));
    final common = needle.intersection(haystack).length;
    if (common == 0) continue;
    final exact = TextSimilarity.normalize(place.officeName ?? '') ==
            normalizedValue
        ? 2
        : (TextSimilarity.normalize(place.departmentName ?? '') ==
                  normalizedValue
              ? 1
              : 0);
    scored.add((
      exact: exact,
      common: common,
      // Λιγότερες λέξεις συνολικά σημαίνει στενότερο ταίριασμα: το «Γραμματεία
      // ΤΕΠ» προηγείται του «Προϊσταμένη Γραμματείας ΤΕΙ».
      breadth: haystack.length,
      place: place,
    ));
  }
  if (scored.isEmpty) {
    return const LampPlaceSuggestion(
      matches: <LampPlaceRow>[],
      sharedDepartment: null,
      totalMatchCount: 0,
    );
  }

  scored.sort((a, b) {
    final byExact = b.exact.compareTo(a.exact);
    if (byExact != 0) return byExact;
    final byCommon = b.common.compareTo(a.common);
    if (byCommon != 0) return byCommon;
    final byBreadth = a.breadth.compareTo(b.breadth);
    return byBreadth != 0 ? byBreadth : a.place.id.compareTo(b.place.id);
  });

  final top = scored.take(limit).map((s) => s.place).toList(growable: false);
  final departments = <String>{
    for (final place in top) (place.departmentName ?? '').trim(),
  };
  final shared = departments.length == 1 && departments.first.isNotEmpty
      ? departments.first
      : null;

  return LampPlaceSuggestion(
    matches: top,
    sharedDepartment: shared,
    totalMatchCount: scored.length,
  );
}

/// Λέξεις σε μορφή σύγκρισης: οι μακριές κόβονται σε ρίζα, οι κοντές μένουν
/// ολόκληρες, οι πολύ κοντές πετιούνται.
Set<String> _tokens(String value) {
  return <String>{
    for (final word in TextSimilarity.normalize(value).split(' '))
      if (word.length >= kLampPlaceMinWordLength)
        word.length >= kLampPlaceStemLength
            ? word.substring(0, kLampPlaceStemLength)
            : word,
  };
}
