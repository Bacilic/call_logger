// Οι προειδοποιήσεις μιας καταχώρησης Lansweeper, όπως τις ξαναδιαβάζει η
// εφαρμογή αργότερα (χωρίς widgets/βάση).
//
// Η ροή αποστολής παράγει ήδη προειδοποιήσεις — «ο αιτών δεν βρέθηκε, αιτών
// καταχωρήθηκε ο πράκτορας» — και τις αποθηκεύει στο `metadata` του
// `call_external_links`. Ως τώρα εμφανίζονταν μία φορά, κολλημένες στο τέλος
// του μηνύματος επιτυχίας, και μετά δεν τις ξανάβλεπε κανείς: η πληροφορία
// υπήρχε στη βάση και ήταν πρακτικά άφταστη.
//
// Τρία σημεία τις ζητούν πλέον (snackbar καταχώρησης, προειδοποίηση
// επεξεργασίας κλήσης, ιστορικό tickets). Η αποκωδικοποίηση ζει εδώ **μία**
// φορά: τρεις χωριστές αναγνώσεις του ίδιου JSON θα απέκλιναν σιωπηλά, με
// πράσινα τεστ σε κάθε πλευρά.

import 'dart:convert';

/// Το κλειδί των προειδοποιήσεων μέσα στο `metadata` του εξωτερικού link.
const String kLansweeperWarningsMetadataKey = 'warnings';

/// Οι προειδοποιήσεις που κρύβει το ωμό `metadata` μιας γραμμής.
///
/// Δέχεται ό,τι κι αν βρεθεί στη στήλη: κείμενο JSON, έτοιμο `Map`, ή `null`.
/// Κάθε αμφιβολία απαντά με κενή λίστα και **ποτέ** με εξαίρεση — το μόνο που
/// θα κέρδιζε ένα σκάσιμο εδώ είναι να χαλάσει η οθόνη που απλώς ήθελε να
/// δείξει μια προειδοποίηση.
List<String> lansweeperWarningsFromMetadata(Object? metadataRaw) {
  final decoded = _decodeMetadata(metadataRaw);
  if (decoded == null) return const <String>[];
  final raw = decoded[kLansweeperWarningsMetadataKey];
  if (raw is! List) return const <String>[];
  final warnings = <String>[];
  for (final item in raw) {
    final text = item?.toString().trim() ?? '';
    if (text.isNotEmpty) warnings.add(text);
  }
  return warnings;
}

/// Οι προειδοποιήσεις της **πιο πρόσφατης** καταχώρησης για το [ticketId].
///
/// Οι [links] έρχονται όπως τις δίνει το `callExternalLinksProvider`, δηλαδή
/// ήδη ταξινομημένες από τη νεότερη προς την παλαιότερη.
///
/// **Το συμβόλαιο:** μετράει μόνο η τελευταία καταχώρηση αυτού του ticket. Αν
/// εκείνη δεν είχε προειδοποιήσεις, η απάντηση είναι κενή — δεν σκαλίζουμε πιο
/// πίσω για γραμμή που είχε. Μια επανυποβολή που πέτυχε καθαρά έχει ήδη
/// ακυρώσει το παλιό παράπονο· η ανάστασή του θα ήταν ψέμα προς τον χρήστη.
List<String> lansweeperWarningsForTicket({
  required List<Map<String, dynamic>> links,
  required String? ticketId,
}) {
  final wanted = ticketId?.trim() ?? '';
  if (wanted.isEmpty) return const <String>[];
  for (final row in links) {
    final externalId = (row['external_id']?.toString() ?? '').trim();
    if (externalId != wanted) continue;
    return lansweeperWarningsFromMetadata(row['metadata']);
  }
  return const <String>[];
}

/// Το κείμενο του snackbar μετά την καταχώρηση: το αποτέλεσμα, και από κάτω
/// ό,τι χρειάζεται προσοχή.
String lansweeperSubmitSnackBarText({
  required String baseMessage,
  required List<String> warnings,
}) {
  if (warnings.isEmpty) return baseMessage;
  return <String>[baseMessage, ...warnings].join('\n');
}

Map<String, dynamic>? _decodeMetadata(Object? metadataRaw) {
  if (metadataRaw == null) return null;
  if (metadataRaw is Map<String, dynamic>) return metadataRaw;
  if (metadataRaw is Map) return Map<String, dynamic>.from(metadataRaw);
  final raw = metadataRaw.toString().trim();
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}
