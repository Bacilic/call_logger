/// Μορφοποίηση κειμένου για αιτήματα του Lansweeper.
///
/// Δύο ξεχωριστές δουλειές, σε δύο ξεχωριστές στιγμές:
///
/// - [formatInlineSolutionSteps] τρέχει **όταν γεμίζει η φόρμα**, ώστε ο
///   χρήστης να βλέπει στο πεδίο ακριβώς ό,τι θα σταλεί και να μπορεί να το
///   διορθώσει.
/// - [lansweeperHtmlText] τρέχει **μόνο τη στιγμή της αποστολής**: είναι η
///   μορφή μεταφοράς, όχι κείμενο που βλέπει κανείς.
library;

/// Βάζει σε ξεχωριστές γραμμές μια λύση γραμμένη ως αριθμημένα βήματα στη
/// σειρά: «1. Α. 2. Β. Η λειτουργία επανήλθε.» γίνεται
///
///     1. Α.
///     2. Β.
///
///     Η λειτουργία επανήλθε.
///
/// Η πρόταση που ακολουθεί την πρώτη πρόταση του τελευταίου βήματος είναι το
/// αποτέλεσμα, και πηγαίνει σε δική της παράγραφο.
///
/// Κείμενο που έχει ήδη αλλαγές γραμμής το έχει στήσει κάποιος· μένει όπως
/// είναι. Το ίδιο και όταν τα βήματα δεν είναι τουλάχιστον δύο, με συνεχή
/// αρίθμηση από το 1 — αλλιώς ένα «έκδοση 2.» μέσα σε πρόταση θα έσπαγε σε
/// γραμμή.
String formatInlineSolutionSteps(String text) {
  final trimmed = text.trim();
  if (trimmed.contains('\n')) return trimmed;

  final first = RegExp(r'(?:^|\s)1[.)]\s+').firstMatch(trimmed);
  if (first == null) return trimmed;
  final intro = trimmed.substring(0, first.start).trim();
  final stepStarts = <int>[first.start == 0 ? 0 : first.start + 1];

  for (var n = 2; ; n++) {
    final next = RegExp(
      '\\s+$n[.)]\\s+',
    ).allMatches(trimmed, stepStarts.last + 2).firstOrNull;
    if (next == null) break;
    stepStarts.add(next.start + next.group(0)!.indexOf('$n'));
  }
  if (stepStarts.length < 2) return trimmed;

  final steps = <String>[
    for (var i = 0; i < stepStarts.length; i++)
      trimmed
          .substring(
            stepStarts[i],
            i + 1 < stepStarts.length ? stepStarts[i + 1] : trimmed.length,
          )
          .trim(),
  ];

  // Μέσα στο τελευταίο βήμα: ό,τι ακολουθεί τέλος πρότασης και κεφαλαίο
  // γράμμα είναι το αποτέλεσμα. Ο έλεγχος ξεκινά μετά τον αριθμό, αλλιώς η
  // τελεία του «3.» θα μετρούσε για τέλος πρότασης.
  var tail = '';
  final last = steps.last;
  final numberEnd = RegExp(r'^\d+[.)]\s+').firstMatch(last)!.end;
  final sentenceEnd = RegExp(
    r'[.!;]\s+(?=\p{Lu})',
    unicode: true,
  ).allMatches(last, numberEnd).firstOrNull;
  if (sentenceEnd != null) {
    steps[steps.length - 1] = last.substring(0, sentenceEnd.start + 1);
    tail = last.substring(sentenceEnd.end).trim();
  }

  return [
    if (intro.isNotEmpty) intro,
    ...steps,
    if (tail.isNotEmpty) '\n$tail',
  ].join('\n');
}

/// Το κείμενο στη μορφή που το εμφανίζει σωστά το Lansweeper.
///
/// Οι σημειώσεις και οι περιγραφές του Lansweeper εμφανίζονται ως ιστοσελίδα:
/// μια απλή αλλαγή γραμμής «ισιώνεται» σε κενό, όπως μετρήθηκε στο ζωντανό
/// σύστημα (20/10/2026, αίτημα #18263). Γι' αυτό η αλλαγή γραμμής στέλνεται ως
/// `<br>`, και οι χαρακτήρες με ειδική σημασία σε ιστοσελίδα (`&`, `<`, `>`)
/// στέλνονται ως έχουν νόημα για τον αναγνώστη, όχι ως εντολές μορφής.
String lansweeperHtmlText(String text) {
  return text
      .replaceAll('\r\n', '\n')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('\n', '<br>');
}
