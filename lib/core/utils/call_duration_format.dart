/// Ενιαία εμφάνιση χρόνου. Δύο σκόπιμα διαφορετικές οικογένειες:
///
/// - **Διάρκεια ΜΙΑΣ κλήσης** ([formatCallDurationSeconds]): `λλ:δδ` κάτω από
///   την ώρα, `ωω:λλ:δδ` από την ώρα και πάνω. Τα δευτερόλεπτα μετρούν και το
///   σταθερό πλάτος κρατά στοιχισμένες τις στήλες και ήρεμο το χρονόμετρο.
/// - **Σύνολα** ([formatAggregateDurationSeconds]): `30ω:15λ`, `45λ:30δ`, `45δ`.
///   Σε αθροίσματα τα δευτερόλεπτα δεν λένε τίποτα και η μονάδα ξεχωρίζει
///   μονοσήμαντα τι μετράμε — το «30:15» διαβαζόταν και ως 30 λεπτά.
///
/// Συμβόλαιο: «Τα σύνολα δείχνονται με μονάδες, η διάρκεια μιας κλήσης με
/// χρονόμετρο — καμία γραφή δεν σημαίνει δύο πράγματα.»
library;

/// Η διάρκεια σε ανθρώπινη μορφή.
///
/// Δέχεται ό,τι δίνουν οι πηγές: `int` από τα μοντέλα, `num` από τα KPI,
/// ακατέργαστη τιμή γραμμής βάσης (`Object?`) από το ιστορικό. Άκυρη ή απούσα
/// τιμή γίνεται [ifMissing] — ποτέ «00:00» που θα περνούσε για μετρημένος
/// μηδενικός χρόνος.
///
/// Παραδείγματα: 191 → «03:11», 609 → «10:09», 3600 → «01:00:00»,
/// 90000 → «25:00:00» (25 ώρες, όχι «01:00:00»).
String formatCallDurationSeconds(Object? seconds, {String ifMissing = '—'}) {
  final total = _asWholeSeconds(seconds);
  if (total == null) return ifMissing;

  final safe = total < 0 ? 0 : total;
  final h = safe ~/ 3600;
  final m = (safe % 3600) ~/ 60;
  final s = safe % 60;

  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (h == 0) return '$mm:$ss';
  return '${h.toString().padLeft(2, '0')}:$mm:$ss';
}

/// Άθροισμα ή μέσος όρος διάρκειας, με ρητές μονάδες: «30ω:15λ», «45λ:30δ»,
/// «45δ».
///
/// Οι μονάδες δεν είναι διακόσμηση: χωρίς αυτές το «30:15» σημαίνει άλλοτε
/// 30 ώρες και άλλοτε 30 λεπτά, ανάλογα με το μέγεθος. Τα δευτερόλεπτα
/// παραλείπονται μόλις μπουν ώρες — σε σύνολο ωρών δεν προσθέτουν πληροφορία.
String formatAggregateDurationSeconds(
  Object? seconds, {
  String ifMissing = '—',
}) {
  final total = _asWholeSeconds(seconds);
  if (total == null) return ifMissing;

  final safe = total < 0 ? 0 : total;
  final h = safe ~/ 3600;
  final m = (safe % 3600) ~/ 60;
  final s = safe % 60;

  if (h > 0) return '$hω:${m.toString().padLeft(2, '0')}λ';
  if (m > 0) return '$mλ:${s.toString().padLeft(2, '0')}δ';
  return '$sδ';
}

/// Λεζάντα του πεδίου διάρκειας: «Διάρκεια (δτρλ) - 01:08».
///
/// Το πεδίο κρατά δευτερόλεπτα (έτσι καταχωρούνται), η λεζάντα δείχνει τι
/// σημαίνουν. Κενή ή άκυρη τιμή: σκέτη λεζάντα, χωρίς παραπλανητικό χρόνο.
String callDurationFieldLabel(String rawSeconds) {
  final formatted = formatCallDurationSeconds(rawSeconds, ifMissing: '');
  if (formatted.isEmpty) return 'Διάρκεια (δτρλ)';
  return 'Διάρκεια (δτρλ) - $formatted';
}

/// `null` όταν η τιμή δεν είναι αριθμός δευτερολέπτων που να έχει νόημα.
int? _asWholeSeconds(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) {
    if (value.isNaN || value.isInfinite) return null;
    return value.round();
  }
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return int.tryParse(text) ?? double.tryParse(text)?.round();
}
