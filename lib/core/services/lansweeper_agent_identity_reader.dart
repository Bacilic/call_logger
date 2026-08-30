import 'lansweeper_identity_diagnosis.dart';
import 'settings_service.dart';

/// Διαβάζει την ταυτότητα πράκτορα Lansweeper **λέγοντας αν τα κατάφερε**.
///
/// Ο μοναδικός `catch` αυτής της ανάγνωσης ζει εδώ. Όσο κάθε καλών έπιανε
/// μόνος του το σφάλμα, και οι τρεις το κατάπιναν με το ίδιο λανθασμένο
/// σχόλιο («αποτυχία = απλώς καμία υποψία») — ενώ στην πραγματικότητα η
/// εφεδρεία του τομέα αναφοράς έκρινε με άλλο μέτρο. Τώρα η σιωπή είναι
/// αδύνατη: όποιος διαβάζει την ταυτότητα, παίρνει μαζί και το «δεν ξέρω».
///
/// Η ανάγνωση αποτυγχάνει τυπικά όταν η κοινόχρηστη βάση είναι κλειδωμένη:
/// η ρύθμιση είναι **προσωπική** και ζει στο προφίλ του χρήστη μέσα σ' αυτήν.
Future<LansweeperAgentIdentity> readLansweeperAgentIdentity() async {
  try {
    final value = await SettingsService().remoteLansweeper
        .getLansweeperAgentUsername();
    return LansweeperAgentIdentity.read(value);
  } catch (_) {
    return const LansweeperAgentIdentity.unavailable();
  }
}
