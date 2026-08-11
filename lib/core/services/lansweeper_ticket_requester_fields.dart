import 'package:email_validator/email_validator.dart';

/// Πεδία για Lansweeper `AddTicket`: πράκτορας (agent) και αιτών (requester)
/// με την **ίδια** καταχώριση — χρήστης τομέα `domain\username`.
///
/// - [Username] και [AgentUsername]: η ίδια τιμή (`domain\username`).
/// - Αν μοιάζει με έγκυρο email: [Email] και [AgentEmail] αντί για username πεδία.
Map<String, String> lansweeperAgentAsMatchingRequesterFields(
  String domainUsername,
) {
  final value = domainUsername.trim();
  if (lansweeperAgentValueLooksLikeEmail(value)) {
    return <String, String>{'Email': value, 'AgentEmail': value};
  }
  return <String, String>{'Username': value, 'AgentUsername': value};
}

/// Κρίνει αν η τιμή μοιάζει με έγκυρο email (πακέτο `email_validator`,
/// χωρίς top-level domain μόνο και χωρίς μη λατινικούς χαρακτήρες —
/// π.χ. `dro@fd` και `ΒασίληςΔρόσος@γγγ.κλ` απορρίπτονται).
bool lansweeperAgentValueLooksLikeEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  // allowTopLevelDomains: false, allowInternational: false
  return EmailValidator.validate(trimmed, false, false);
}

/// Πεδία `AddTicket`/`EditTicket` όταν ο αιτών **διαφέρει** από τον πράκτορα:
/// ο αιτών στα [Username]/[Email], ο πράκτορας στα [AgentUsername]/[AgentEmail].
/// Καθεμιά από τις δύο ταυτότητες ταξινομείται ανεξάρτητα (email ή τομέας\όνομα).
Map<String, String> lansweeperRequesterAndAgentFields({
  required String requester,
  required String agent,
}) {
  final requesterValue = requester.trim();
  final agentValue = agent.trim();
  return <String, String>{
    if (lansweeperAgentValueLooksLikeEmail(requesterValue))
      'Email': requesterValue
    else
      'Username': requesterValue,
    if (lansweeperAgentValueLooksLikeEmail(agentValue))
      'AgentEmail': agentValue
    else
      'AgentUsername': agentValue,
  };
}

/// Παράμετροι `SearchUsers` για τη δοσμένη ταυτότητα: email → `Email`,
/// `τομέας\όνομα` → `Username` + `UserDomain`, αλλιώς σκέτο `Username`.
Map<String, String> lansweeperSearchUsersParamsFor(String identity) {
  final value = identity.trim();
  if (lansweeperAgentValueLooksLikeEmail(value)) {
    return <String, String>{'Email': value};
  }
  final separator = value.indexOf(r'\');
  if (separator > 0 && !value.contains(r'\', separator + 1)) {
    final domain = value.substring(0, separator);
    final username = value.substring(separator + 1);
    if (domain.isNotEmpty && username.isNotEmpty) {
      return <String, String>{'Username': username, 'UserDomain': domain};
    }
  }
  return <String, String>{'Username': value};
}

/// Κρίνει αν η τιμή **δεν** μοιάζει με έγκυρη ταυτότητα `domain\username`
/// ούτε με έγκυρο email (π.χ. απλό display name ή άκυρο `dro@fd`).
bool lansweeperAgentValueLooksLikeDisplayName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  if (lansweeperAgentValueLooksLikeEmail(trimmed)) return false;
  if (_looksLikeDomainUsername(trimmed)) return false;
  return true;
}

bool _looksLikeDomainUsername(String trimmed) {
  final separator = trimmed.indexOf(r'\');
  if (separator <= 0) return false;
  if (trimmed.contains(r'\', separator + 1)) return false;
  final domain = trimmed.substring(0, separator);
  final username = trimmed.substring(separator + 1);
  if (domain.isEmpty || username.isEmpty) return false;
  // Κενό μέσα στην ταυτότητα σημαίνει σχεδόν πάντα ότι κόλλησε μπροστά μια
  // ονομασία («Γραφείο Λοιμώξεων gnk\loimokseis1»). Λογαριασμοί τομέα δεν
  // έχουν κενά, οπότε το Lansweeper δεν θα έβρισκε ποτέ τέτοιον χρήστη.
  if (_containsWhitespace(domain) || _containsWhitespace(username)) {
    return false;
  }
  return true;
}

final RegExp _whitespace = RegExp(r'\s');

bool _containsWhitespace(String value) => _whitespace.hasMatch(value);
