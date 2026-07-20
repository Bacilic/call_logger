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
    return <String, String>{
      'Email': value,
      'AgentEmail': value,
    };
  }
  return <String, String>{
    'Username': value,
    'AgentUsername': value,
  };
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
  return domain.isNotEmpty && username.isNotEmpty;
}
