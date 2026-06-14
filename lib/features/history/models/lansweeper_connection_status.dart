/// Κατάσταση ελέγχου σύνδεσης Lansweeper (API ή Help Desk).
sealed class LansweeperConnectionStatus {
  const LansweeperConnectionStatus();
}

/// Ο έλεγχος σύνδεσης βρίσκεται σε εξέλιξη.
final class LansweeperConnectionChecking extends LansweeperConnectionStatus {
  const LansweeperConnectionChecking();
}

/// Η σύνδεση είναι εφικτή.
final class LansweeperConnectionAvailable extends LansweeperConnectionStatus {
  const LansweeperConnectionAvailable();
}

/// Η σύνδεση απέτυχε· το [reason] προέρχεται από την αντίστοιχη probe.
final class LansweeperConnectionUnavailable extends LansweeperConnectionStatus {
  const LansweeperConnectionUnavailable(this.reason);

  final String reason;
}
