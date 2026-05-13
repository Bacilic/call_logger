/// Πεδία για Lansweeper `AddTicket`: πράκτορας (agent) και αιτών (requester)
/// με την **ίδια** καταχώριση — για περιβάλλοντα που απαιτούν και τα δύο.
///
/// - [AgentUsername] και [Displayname]: πάντα η τιμή του πράκτορα.
/// - [Email]: μόνο όταν η τιμή μοιάζει με email/UPN (περιέχει `@`).
Map<String, String> lansweeperAgentAsMatchingRequesterFields(
  String agentUsername,
) {
  final a = agentUsername.trim();
  return <String, String>{
    'AgentUsername': a,
    'Displayname': a,
    if (a.contains('@')) 'Email': a,
  };
}
