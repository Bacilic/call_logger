// Πότε μια διαγραφή καταλόγου σβήνει «πολύ» — καθαρή λογική, χωρίς UI.
//
// Αποφάσεις Διευθυντή 15/10 και 23/10/2026: ποσοστό ρυθμιζόμενο από τον
// διαχειριστή, ενιαίο για υπαλλήλους, τμήματα και εξοπλισμό· ισχύει από 50
// στοιχεία και πάνω· ο ολόκληρος κατάλογος προειδοποιεί πάντα, πιο αυστηρά.

import '../../../core/config/mass_deletion_percent.dart';
import '../../../core/utils/search_text_normalizer.dart';

export '../../../core/config/mass_deletion_percent.dart';

/// Κάτω από τόσα στοιχεία ο κατάλογος δεν παίρνει προειδοποίηση ποσοστού —
/// μόνο τη διαγραφή ολόκληρου.
const int kMassDeletionMinCatalogSize = 50;

/// Η λέξη που γράφεται για να σβηστεί ολόκληρος ο κατάλογος.
const String kWholeCatalogConfirmWord = 'ΔΙΑΓΡΑΦΗ';

enum MassDeletionLevel {
  /// Καμία προειδοποίηση.
  none,

  /// Φτάνει το ρυθμισμένο ποσοστό: πλαίσιο προειδοποίησης.
  share,

  /// Ολόκληρος ο κατάλογος: η διαγραφή θέλει τη λέξη [kWholeCatalogConfirmWord].
  whole,
}

/// Πόσο βαριά είναι η διαγραφή [deleting] στοιχείων από κατάλογο [catalogTotal].
///
/// Ο ολόκληρος κατάλογος κρίνεται **πριν** από το όριο των 50: είναι ολική
/// απώλεια όποιο κι αν είναι το μέγεθός του.
MassDeletionLevel massDeletionLevel({
  required int deleting,
  required int catalogTotal,
  required int thresholdPercent,
}) {
  if (deleting <= 0 || catalogTotal <= 0) return MassDeletionLevel.none;
  if (deleting >= catalogTotal) return MassDeletionLevel.whole;
  if (catalogTotal < kMassDeletionMinCatalogSize) return MassDeletionLevel.none;
  final percent = normalizeMassDeletionPercent(thresholdPercent);
  return deleting * 100 >= percent * catalogTotal
      ? MassDeletionLevel.share
      : MassDeletionLevel.none;
}

/// Αν επιτρέπεται να πατηθεί η διαγραφή. Μόνο ο ολόκληρος κατάλογος ζητά τη
/// λέξη· τόνοι και κεφαλαία δεν μετρούν, ώστε το «διαγραφή» να αρκεί.
bool massDeletionConfirmAllowed(MassDeletionLevel level, String typedWord) {
  if (level != MassDeletionLevel.whole) return true;
  return SearchTextNormalizer.normalizeForSearch(typedWord.trim()) ==
      SearchTextNormalizer.normalizeForSearch(kWholeCatalogConfirmWord);
}

/// Ποιος κατάλογος σβήνεται — για να γράφεται σωστά η πρόταση.
enum MassDeletionCatalog {
  users(
    shareNoun: 'τους {n} υπαλλήλους',
    wholeNoun: 'και οι {n} υπάλληλοι',
    title: 'Υπάλληλοι',
  ),
  departments(
    shareNoun: 'τα {n} τμήματα',
    wholeNoun: 'και τα {n} τμήματα',
    title: 'Τμήματα',
  ),
  equipment(
    shareNoun: 'τους {n} εξοπλισμούς',
    wholeNoun: 'και οι {n} εξοπλισμοί',
    title: 'Εξοπλισμός',
  );

  const MassDeletionCatalog({
    required this.shareNoun,
    required this.wholeNoun,
    required this.title,
  });

  final String shareNoun;
  final String wholeNoun;

  /// Όπως λέγεται η καρτέλα του Καταλόγου.
  final String title;
}

/// «Θα διαγραφούν 70 από τους 115 υπαλλήλους (61%).»
String massDeletionShareText({
  required MassDeletionCatalog catalog,
  required int deleting,
  required int catalogTotal,
}) {
  final percent = catalogTotal <= 0 ? 0 : (deleting * 100) ~/ catalogTotal;
  final noun = catalog.shareNoun.replaceFirst('{n}', '$catalogTotal');
  return 'Θα διαγραφούν $deleting από $noun ($percent%).';
}

/// «Θα διαγραφεί ολόκληρος ο κατάλογος — και οι 115 υπάλληλοι.»
String massDeletionWholeText({
  required MassDeletionCatalog catalog,
  required int catalogTotal,
}) {
  final noun = catalog.wholeNoun.replaceFirst('{n}', '$catalogTotal');
  return 'Θα διαγραφεί ολόκληρος ο κατάλογος — $noun. '
      'Δεν θα μείνει κανένα στοιχείο.';
}

/// Το πλαίσιο που χρειάζεται ένας διάλογος διαγραφής για να προειδοποιήσει.
class MassDeletionContext {
  const MassDeletionContext({
    required this.catalog,
    required this.catalogTotal,
    required this.thresholdPercent,
  });

  final MassDeletionCatalog catalog;

  /// Τα ενεργά στοιχεία του καταλόγου, όχι μόνο τα ορατά με τα φίλτρα.
  final int catalogTotal;
  final int thresholdPercent;

  MassDeletionLevel levelFor(int deleting) => massDeletionLevel(
    deleting: deleting,
    catalogTotal: catalogTotal,
    thresholdPercent: thresholdPercent,
  );
}

/// Η γραμμή κάλυψης της ρύθμισης, από τα **πραγματικά** πλήθη: ποιοι κατάλογοι
/// παίρνουν προειδοποίηση ποσοστού και ποιοι όχι, επειδή είναι μικροί.
String massDeletionCoverageText(Map<MassDeletionCatalog, int> totals) {
  String list(Iterable<MapEntry<MassDeletionCatalog, int>> entries) =>
      entries.map((e) => '${e.key.title} (${e.value})').join(', ');
  final covered = totals.entries
      .where((e) => e.value >= kMassDeletionMinCatalogSize)
      .toList();
  final small = totals.entries
      .where((e) => e.value < kMassDeletionMinCatalogSize)
      .toList();
  final lines = <String>[
    covered.isEmpty
        ? 'Κανένας κατάλογος δεν έχει ακόμη $kMassDeletionMinCatalogSize '
              'στοιχεία — η προειδοποίηση ποσοστού δεν ισχύει πουθενά.'
        : 'Καλύπτονται: ${list(covered)}.',
    if (small.isNotEmpty)
      'Δεν καλύπτονται, επειδή έχουν λιγότερα από '
          '$kMassDeletionMinCatalogSize στοιχεία: ${list(small)}.',
    'Η διαγραφή ολόκληρου καταλόγου ζητά πάντα να γραφτεί η λέξη '
        '«$kWholeCatalogConfirmWord», σε υπαλλήλους, τμήματα και εξοπλισμό, '
        'όποιο κι αν είναι το μέγεθός τους.',
  ];
  return lines.join('\n');
}
