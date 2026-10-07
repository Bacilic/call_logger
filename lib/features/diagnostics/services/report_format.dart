/// Μικρές μορφοποιήσεις που μοιράζονται οι ενότητες του αρχείου
/// διαγνωστικών — μία γραφή ημερομηνίας σε όλο το αρχείο.
library;

String _two(int value) => value.toString().padLeft(2, '0');

/// «05/10/2026».
String reportDay(DateTime moment) =>
    '${_two(moment.day)}/${_two(moment.month)}/${moment.year}';

/// «05/10/2026 18:19:16».
String reportMoment(DateTime moment) =>
    '${reportDay(moment)} ${_two(moment.hour)}:${_two(moment.minute)}:'
    '${_two(moment.second)}';

/// Η πρώτη μη κενή γραμμή, χωρίς κενά στις άκρες.
String firstLineOf(String? text) {
  if (text == null) return '';
  return text.trimLeft().split('\n').first.trim();
}

/// Οι πρώτες [count] γραμμές, με σημείωση για όσες έμειναν έξω.
String firstLinesOf(String text, int count) {
  final lines = text.trimRight().split('\n');
  if (lines.length <= count) return lines.join('\n');
  return '${lines.take(count).join('\n')}\n… (+${lines.length - count} '
      'γραμμές)';
}

/// Το κείμενο σε μία γραμμή, κομμένο στους [max] χαρακτήρες.
String oneLine(String text, {int max = 240}) {
  final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (single.length <= max) return single;
  return '${single.substring(0, max)}…';
}

/// Κόβει κάθε συνεχόμενη στοίβα κλήσεων (γραμμές `#0`, `#1`, …) στις
/// πρώτες [keep] γραμμές. Τα πρώτα πλαίσια λένε πού έγινε το σφάλμα· τα
/// εκατό επόμενα είναι το framework που το μετέφερε.
String trimStackRuns(String text, int keep) {
  final frame = RegExp(r'^#\d+\s');
  final out = <String>[];
  var run = 0;
  var dropped = 0;
  void flush() {
    if (dropped > 0) out.add('… (+$dropped γραμμές στοίβας)');
    run = 0;
    dropped = 0;
  }

  for (final line in text.split('\n')) {
    if (frame.hasMatch(line)) {
      run++;
      if (run <= keep) {
        out.add(line);
      } else {
        dropped++;
      }
      continue;
    }
    flush();
    out.add(line);
  }
  flush();
  return out.join('\n');
}

/// Η έκδοση των Windows όπως τη διαβάζει άνθρωπος.
///
/// Τα Windows 11 δηλώνουν ακόμη «Windows 10» στο όνομά τους· τα ξεχωρίζει
/// μόνο ο αριθμός build, από το 22000 και πάνω.
String describeWindowsVersion(String reported) {
  final build = int.tryParse(
    RegExp(r'Build (\d+)').firstMatch(reported)?.group(1) ?? '',
  );
  final clean = reported.replaceAll('"', '').trim();
  if (build == null || build < 22000) return clean;
  return clean.replaceFirst('Windows 10', 'Windows 11');
}

/// Μπλοκ κώδικα με φράχτη που δεν μπορεί να κλείσει από το περιεχόμενο.
String fenced(String text) {
  var fence = '```';
  while (text.contains(fence)) {
    fence += '`';
  }
  return '$fence\n$text\n$fence';
}
