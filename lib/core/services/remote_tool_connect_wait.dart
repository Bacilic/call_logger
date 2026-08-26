import '../models/remote_tool.dart';
import 'overridable_settings.dart';

/// Ο χρόνος αναμονής του εργαλείου **όπως ισχύει σε αυτόν τον υπολογιστή**.
///
/// Ο ορισμός του εργαλείου δίνει την κοινή αφετηρία (το RDP αργεί, το AnyDesk
/// όχι)· πόσο όμως αργεί *εδώ* εξαρτάται από την ταχύτητα αυτού του μηχανήματος
/// και του δικτύου του. Χωρίς τοπική παράκαμψη, ο συνάδελφος με το γρήγορο
/// μηχάνημα θα περίμενε άσκοπα τον χρόνο του πιο αργού.
///
/// **Το μοναδικό σημείο** όπου απαντάται «πόσο κλειδώνει;» — όπως το
/// `effectiveExecutablePath` για τη διαδρομή.
abstract final class RemoteToolConnectWait {
  static OverridableSettingKey keyFor(int toolId) =>
      OverridableSettingKeys.remoteToolConnectWait.forId(toolId);

  /// Τα δευτερόλεπτα που ισχύουν τώρα. Μηδέν = χωρίς κλείδωμα.
  static Future<int> effectiveSeconds(RemoteTool tool) async {
    final resolved = await OverridableSettings.resolve(
      keyFor(tool.id),
      shared: '${tool.connectWaitSeconds}',
    );
    return RemoteTool.normalizeConnectWaitSeconds(resolved);
  }

  static Future<Duration> effectiveWait(RemoteTool tool) async =>
      Duration(seconds: await effectiveSeconds(tool));

  /// Η τοπική παράκαμψη όπως έχει δηλωθεί, ή `null` όταν **δεν** έχει δηλωθεί.
  ///
  /// Η διάκριση μετράει: «δεν δήλωσα τίποτα» σημαίνει «ακολουθώ την κοινή
  /// τιμή», και πρέπει να ξεχωρίζει από μια δηλωμένη τιμή που τυχαίνει να
  /// συμπίπτει με αυτήν.
  static Future<int?> localOverrideSeconds(int toolId) async {
    final raw = await OverridableSettings.overrideOf(keyFor(toolId));
    if (raw == null) return null;
    return RemoteTool.normalizeConnectWaitSeconds(raw);
  }

  static Future<void> setLocalOverride(int toolId, int seconds) =>
      OverridableSettings.setOverride(
        keyFor(toolId),
        '${RemoteTool.normalizeConnectWaitSeconds(seconds)}',
      );

  /// «Χρήση της κοινής τιμής»: αφαιρεί εντελώς τη δήλωση.
  static Future<void> clearLocalOverride(int toolId) =>
      OverridableSettings.clearOverride(keyFor(toolId));
}
