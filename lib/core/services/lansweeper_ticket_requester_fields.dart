/// Πεδία για Lansweeper `AddTicket`: πράκτορας (agent) και αιτών (requester)
/// με την **ίδια** καταχώριση — χρήστης τομέα `domain\username`.
///
/// - [Username] και [AgentUsername]: η ίδια τιμή (`domain\username`).
/// - Αν περιέχει `@`: [Email] και [AgentEmail] αντί για username πεδία.
Map<String, String> lansweeperAgentAsMatchingRequesterFields(
  String domainUsername,
) {
  final value = domainUsername.trim();
  if (value.contains('@')) {
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
