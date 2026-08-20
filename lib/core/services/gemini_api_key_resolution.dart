import '../database/database_helper.dart';
import '../database/settings_repository.dart';
import 'overridable_settings.dart';

/// Το κλειδί API της ΤΝ **που ισχύει τώρα** — η μία απάντηση για όλους.
///
/// Αλυσίδα (Φάση 3): το προσωπικό κλειδί του συνδεδεμένου χρήστη αν έχει
/// δηλωθεί, αλλιώς το κοινό που όρισε ο διαχειριστής.
///
/// **Υπάρχει ως ξεχωριστή συνάρτηση επίτηδες:** το κλειδί διαβάζεται από δύο
/// σημεία — τον provider της οθόνης και τον εκτελεστή των κλήσεων προς την ΤΝ.
/// Δύο αντίγραφα της ίδιας αλυσίδας θα απέκλιναν σιωπηλά, και η οθόνη θα
/// έδειχνε άλλο κλειδί από αυτό που στέλνεται στο δίκτυο.
Future<String> resolveGeminiApiKey() async {
  final db = await DatabaseHelper.instance.database;
  final shared =
      (await SettingsRepository(
        db,
      ).getSetting(kGeminiApiKeySettingKey))?.trim() ??
      '';
  final resolved = await OverridableSettings.resolve(
    OverridableSettingKeys.geminiApiKey,
    shared: shared,
  );
  return resolved.trim();
}
