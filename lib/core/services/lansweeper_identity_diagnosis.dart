import 'package:email_validator/email_validator.dart';

/// Στοχευμένη διάγνωση ταυτότητας Lansweeper: «τομέας\όνομα» ή email.
///
/// Η αρχή: πρώτα μαντεύουμε τι ΠΡΟΣΠΑΘΗΣΕ να γράψει ο χρήστης (από τα
/// σημάδια `\` και `@`) και λέμε τι χάλασε ΣΕ ΕΚΕΙΝΟ. Το γενικό «γράψτε
/// τομέα\όνομα ή email» μένει μόνο όταν δεν υπάρχει κανένα σημάδι πρόθεσης.
///
/// Οι κανόνες ΔΕΝ είναι δικής μας επινόησης:
/// • Email: το πακέτο `email_validator` (πρακτικά ο κανόνας WHATWG/HTML5 των
///   browsers), με υποχρεωτική τελεία στον τομέα και χωρίς μη λατινικούς
///   χαρακτήρες — ίδιες επιλογές με τον υπάρχοντα κριτή της εφαρμογής.
/// • Τομέας\όνομα: οι κανόνες ονοματοδοσίας της Microsoft — NetBIOS τομέας
///   έως 15 χαρακτήρες χωρίς σημεία στίξης, sAMAccountName έως 20 χαρακτήρες
///   χωρίς τους απαγορευμένους χαρακτήρες `" / \ [ ] : ; | = , + * ? < >`.

/// Τι αναγνωρίστηκε ότι προσπάθησε να γράψει ο χρήστης.
enum LansweeperIdentityKind {
  /// Ταυτότητα `τομέας\όνομα` (έγκυρη ή προβληματική).
  domainAccount,

  /// Διεύθυνση email (έγκυρη ή προβληματική).
  email,

  /// Κανένα σημάδι πρόθεσης — δεν κρίνεται τι ήθελε.
  unknown,
}

/// Το πόρισμα για ΜΙΑ τιμή.
class LansweeperIdentityDiagnosis {
  const LansweeperIdentityDiagnosis({
    required this.kind,
    this.problem,
    this.suggestion,
  });

  final LansweeperIdentityKind kind;

  /// Το στοχευμένο μήνυμα λάθους· `null` = η τιμή είναι έγκυρη.
  final String? problem;

  /// Έτοιμη πρόταση διόρθωσης, όταν μπορεί να μαντευτεί με ασφάλεια
  /// (π.χ. το ξεχασμένο «=» πριν από έγκυρη ουρά).
  final String? suggestion;

  bool get isValid => problem == null;
}

/// Απαγορευμένοι χαρακτήρες NetBIOS ονόματος τομέα (Microsoft naming
/// conventions) — το `\` ελέγχεται χωριστά ως διαχωριστής.
const String _netbiosForbidden = r'/:*?"<>|.';

/// Απαγορευμένοι χαρακτήρες sAMAccountName (Microsoft) — χωρίς το `\`.
const String _samForbidden = '"/[]:;|=,+*?<>';

/// Διαγιγνώσκει την [value]. Κενή/λευκή τιμή θεωρείται «χωρίς ταυτότητα» —
/// έγκυρη επιλογή, ο καλών δεν χρειάζεται να τη στείλει καν εδώ.
LansweeperIdentityDiagnosis diagnoseLansweeperIdentity(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return const LansweeperIdentityDiagnosis(
      kind: LansweeperIdentityKind.unknown,
    );
  }

  final hasBackslash = trimmed.contains(r'\');
  final hasAt = trimmed.contains('@');

  if (hasBackslash && hasAt) {
    return const LansweeperIdentityDiagnosis(
      kind: LansweeperIdentityKind.unknown,
      problem:
          'Περιέχει και «\\» και «@» — γράψτε είτε «τομέας\\όνομα» είτε email',
    );
  }
  if (hasBackslash) return _diagnoseDomainAccount(trimmed);
  if (hasAt) return _diagnoseEmail(trimmed);

  return const LansweeperIdentityDiagnosis(
    kind: LansweeperIdentityKind.unknown,
    problem:
        'Δεν μοιάζει ούτε με τομέα\\όνομα ούτε με email — γράψτε έγκυρο '
        '«τομέας\\όνομα» ή email',
  );
}

LansweeperIdentityDiagnosis _diagnoseDomainAccount(String trimmed) {
  const kind = LansweeperIdentityKind.domainAccount;

  // Το ξεχασμένο «=»: κενά μπροστά από ουρά που από μόνη της στέκει.
  // Προτείνουμε την πλήρη μορφή αντί να καταγγείλουμε «κενά» γενικώς.
  final whitespace = RegExp(r'\s+');
  if (whitespace.hasMatch(trimmed)) {
    final parts = trimmed.split(whitespace);
    final tail = parts.last;
    final label = parts.sublist(0, parts.length - 1).join(' ');
    if (label.isNotEmpty && diagnoseLansweeperIdentity(tail).isValid) {
      return LansweeperIdentityDiagnosis(
        kind: kind,
        problem: 'Μοιάζει να λείπει το «=» ανάμεσα σε ονομασία και ταυτότητα',
        suggestion: 'Γράψτε: $label = $tail',
      );
    }
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem:
          'Μη έγκυρος τομέας\\όνομα: δεν επιτρέπονται κενά μέσα στην '
          'ταυτότητα',
    );
  }

  final first = trimmed.indexOf(r'\');
  if (trimmed.contains(r'\', first + 1)) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem: 'Μη έγκυρος τομέας\\όνομα: περισσότερες από μία «\\»',
    );
  }

  final domain = trimmed.substring(0, first);
  final username = trimmed.substring(first + 1);
  if (domain.isEmpty) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem: 'Λείπει ο τομέας πριν την «\\» (π.χ. gnk\\όνομα)',
    );
  }
  if (username.isEmpty) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem: 'Λείπει το όνομα χρήστη μετά την «\\»',
    );
  }

  for (final ch in domain.split('')) {
    if (_netbiosForbidden.contains(ch)) {
      return LansweeperIdentityDiagnosis(
        kind: kind,
        problem:
            'Μη έγκυρος τομέας: περιέχει «$ch» — ο τομέας γράφεται στη '
            'σύντομη μορφή (π.χ. gnk), χωρίς σημεία στίξης',
      );
    }
  }
  if (domain.length > 15) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem:
          'Μη έγκυρος τομέας: ξεπερνά τους 15 χαρακτήρες (όριο NetBIOS '
          'των Windows)',
    );
  }

  for (final ch in username.split('')) {
    if (_samForbidden.contains(ch)) {
      return LansweeperIdentityDiagnosis(
        kind: kind,
        problem: 'Μη έγκυρο όνομα χρήστη: περιέχει τον χαρακτήρα «$ch»',
      );
    }
  }
  if (username.length > 20) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem:
          'Μη έγκυρο όνομα χρήστη: ξεπερνά τους 20 χαρακτήρες (όριο '
          'λογαριασμών των Windows)',
    );
  }

  return const LansweeperIdentityDiagnosis(kind: kind);
}

LansweeperIdentityDiagnosis _diagnoseEmail(String trimmed) {
  const kind = LansweeperIdentityKind.email;

  // Ο τελικός κριτής είναι ο ΙΔΙΟΣ με όλη την εφαρμογή (email_validator,
  // χωρίς σκέτο TLD, χωρίς μη λατινικούς χαρακτήρες).
  if (EmailValidator.validate(trimmed, false, false)) {
    return const LansweeperIdentityDiagnosis(kind: kind);
  }

  if (RegExp(r'\s').hasMatch(trimmed)) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem: 'Μη έγκυρο email: περιέχει κενό',
    );
  }
  final firstAt = trimmed.indexOf('@');
  if (trimmed.contains('@', firstAt + 1)) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem: 'Μη έγκυρο email: περισσότερα από ένα «@»',
    );
  }
  final local = trimmed.substring(0, firstAt);
  final domain = trimmed.substring(firstAt + 1);
  if (local.isEmpty) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem: 'Μη έγκυρο email: λείπει το όνομα πριν το «@»',
    );
  }
  if (domain.isEmpty) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem: 'Μη έγκυρο email: λείπει ο τομέας μετά το «@»',
    );
  }
  if (RegExp(r'[^\x00-\x7F]').hasMatch(trimmed)) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem:
          'Μη έγκυρο email: περιέχει μη λατινικούς χαρακτήρες — οι '
          'λογαριασμοί γράφονται με λατινικά',
    );
  }
  if (!domain.contains('.')) {
    return const LansweeperIdentityDiagnosis(
      kind: kind,
      problem:
          'Μη έγκυρο email: ο τομέας μετά το «@» δεν μοιάζει πλήρης '
          '(π.χ. gnk.gr)',
    );
  }
  return const LansweeperIdentityDiagnosis(
    kind: kind,
    problem: 'Μη έγκυρο email',
  );
}

/// Η ταυτότητα πράκτορα Lansweeper **όπως τη γνωρίζει** η εφαρμογή.
///
/// Ξεχωρίζει δύο καταστάσεις που έμοιαζαν ίδιες όσο ταξίδευαν ως σκέτο
/// `String?`, και που οδηγούν σε **διαφορετικό** αποτέλεσμα:
/// • **δεν έχει οριστεί** — θεμιτό· η εφεδρεία της ψηφοφορίας είναι σωστή·
/// • **δεν διαβάστηκε** — άγνωστη· η ψηφοφορία θα ήταν εικασία, και μια
///   εικασία εδώ σημαίνει σωστές εγγραφές σημαδεμένες ως ύποπτες.
class LansweeperAgentIdentity {
  /// Διαβάστηκε: [value] η τιμή, ή `null` όταν δεν έχει οριστεί ποτέ.
  const LansweeperAgentIdentity.read(this.value) : unavailable = false;

  /// ΔΕΝ διαβάστηκε — άγνωστη, όχι ανύπαρκτη.
  const LansweeperAgentIdentity.unavailable()
    : value = null,
      unavailable = true;

  final String? value;

  /// True όταν η ανάγνωση απέτυχε.
  final bool unavailable;
}

/// Ο τομέας αναφοράς για τις ήπιες υποψίες τυπογραφικού.
///
/// Δύο πηγές, με σειρά προτίμησης:
/// 1. Ο τομέας του πράκτορα (Ρυθμίσεις API) — όταν είναι «τομέας\όνομα».
///    Πράκτορας καταχωρημένος ως email ΔΕΝ κουβαλά τομέα NetBIOS.
/// 2. Ο ΠΛΕΙΟΨΗΦΙΚΟΣ τομέας των [knownIdentities] (τα ήδη αποθηκευμένα
///    αναγνωριστικά του καταλόγου): χρειάζονται τουλάχιστον 2 ψήφοι και
///    καθαρή πρωτιά — ισοπαλία σημαίνει «δεν υπάρχει συνηθισμένος τομέας».
///
/// **Άγνωστος πράκτορας σταματά και τις δύο πηγές.** Η δεύτερη είναι
/// εφεδρεία του «δεν έχει οριστεί», όχι του «δεν ξέρω»: με πράκτορα ενός
/// τομέα και κατάλογο γεμάτο από άλλον, η ψηφοφορία θα έκρινε με λάθος
/// μέτρο και θα σημάδευε πορτοκαλί ακριβώς τις σωστές εγγραφές.
String? lansweeperReferenceDomain({
  LansweeperAgentIdentity agent = const LansweeperAgentIdentity.read(null),
  Iterable<String> knownIdentities = const [],
}) {
  if (agent.unavailable) return null;
  final agentValue = (agent.value ?? '').trim();
  final agentSeparator = agentValue.indexOf(r'\');
  if (agentSeparator > 0) {
    final agentDiagnosis = diagnoseLansweeperIdentity(agentValue);
    if (agentDiagnosis.isValid &&
        agentDiagnosis.kind == LansweeperIdentityKind.domainAccount) {
      return agentValue.substring(0, agentSeparator);
    }
  }

  final votes = <String, int>{};
  for (final identity in knownIdentities) {
    final diagnosis = diagnoseLansweeperIdentity(identity);
    if (!diagnosis.isValid ||
        diagnosis.kind != LansweeperIdentityKind.domainAccount) {
      continue;
    }
    final domain = identity.trim().split(r'\').first.toLowerCase();
    if (domain.isEmpty) continue;
    votes[domain] = (votes[domain] ?? 0) + 1;
  }
  if (votes.isEmpty) return null;

  final sorted = votes.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = sorted.first;
  if (top.value < 2) return null;
  if (sorted.length > 1 && sorted[1].value == top.value) return null;
  return top.key;
}

/// Ήπια υποψία τυπογραφικού στον τομέα: ΕΓΚΥΡΗ ταυτότητα «τομέας\όνομα» της
/// οποίας ο τομέας διαφέρει από τον [referenceDomain] (βλ.
/// [lansweeperReferenceDomain]).
///
/// Ποτέ σφάλμα — σε δίκτυα με πολλούς τομείς είναι απολύτως θεμιτό. Γι' αυτό
/// επιστρέφεται χωριστά από το [diagnoseLansweeperIdentity]: ο καλών το
/// δείχνει ως προειδοποίηση δεύτερης διαβάθμισης (πορτοκαλί), όχι ως λάθος.
String? lansweeperDomainMismatchHint(String value, String? referenceDomain) {
  final reference = (referenceDomain ?? '').trim();
  if (reference.isEmpty) return null;

  final diagnosis = diagnoseLansweeperIdentity(value);
  if (!diagnosis.isValid ||
      diagnosis.kind != LansweeperIdentityKind.domainAccount) {
    return null;
  }

  final valueDomain = value.trim().split(r'\').first;
  if (valueDomain.toLowerCase() == reference.toLowerCase()) return null;
  return 'Ο τομέας «$valueDomain» διαφέρει από τον συνηθισμένο '
      '«$reference» — πιθανό τυπογραφικό';
}

/// Ο τόνος του υπομνήματος κάτω από το «Αναγνωριστικό Lansweeper».
enum LansweeperIdentityHintTone {
  /// Πληροφορία, όχι παρατήρηση.
  neutral,

  /// Έγκυρο μεν, ύποπτο δε — ήπια επισήμανση.
  suspicion,

  /// Η τιμή δεν θα βρει τον υπάλληλο.
  error,
}

/// Τι λέει το υπόμνημα του πεδίου, και με τι τόνο.
///
/// Η **σειρά** είναι η ουσία εδώ. Όταν το τμήμα δεν συμμετέχει στο Lansweeper,
/// η τιμή δεν διαβάζεται από κανέναν — οπότε κάθε άλλη συμβουλή είναι χαμένος
/// κόπος: το «το έγραψες λάθος, μήπως εννοούσες Χ;» στέλνει τον χρήστη να
/// διορθώσει κάτι που δεν πρόκειται να χρησιμοποιηθεί. Γι' αυτό το «δεν θα
/// χρησιμοποιηθεί» προηγείται και της διάγνωσης και της υποψίας τομέα.
///
/// Ζει εδώ και όχι μέσα στη φόρμα: είναι κρίση, όχι διάταξη — και ελέγχεται
/// χωρίς να στηθεί οθόνη.
({String text, LansweeperIdentityHintTone tone}) lansweeperIdentityFieldHint({
  required bool participatesInLansweeper,
  required String identity,
  required String? referenceDomain,
}) {
  if (!participatesInLansweeper) {
    return (
      text:
          'Το Lansweeper αναγνωρίζει μόνο τμήματα του νοσοκομείου — το '
          'αναγνωριστικό δεν θα χρησιμοποιηθεί.',
      tone: LansweeperIdentityHintTone.neutral,
    );
  }

  final value = identity.trim();
  final diagnosis = diagnoseLansweeperIdentity(value);
  if (value.isNotEmpty && !diagnosis.isValid) {
    final suggestion = diagnosis.suggestion;
    return (
      text: suggestion == null
          ? '${diagnosis.problem!} — το αίτημα δεν θα βρει τον υπάλληλο.'
          : '${diagnosis.problem!} — $suggestion',
      tone: LansweeperIdentityHintTone.error,
    );
  }

  if (value.isNotEmpty) {
    final mismatch = lansweeperDomainMismatchHint(value, referenceDomain);
    if (mismatch != null) {
      return (text: '$mismatch.', tone: LansweeperIdentityHintTone.suspicion);
    }
  }

  return (
    text:
        'Με συμπληρωμένο αναγνωριστικό, ο υπάλληλος καταχωρείται ως αιτών '
        'στο ticket του Lansweeper.',
    tone: LansweeperIdentityHintTone.neutral,
  );
}
