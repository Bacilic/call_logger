import '../database/equipment_repository.dart';
import 'lansweeper_asset_target.dart';

/// Ο εξοπλισμός μιας κλήσης όπως θα σταλεί στο ticket (`AddAsset`).
///
/// Τρία σκαλοπάτια, με αυτή τη σειρά:
/// 1. Η **συνδεδεμένη** καρτέλα του Καταλόγου (`equipment_id`).
/// 2. Αν λείπει η σύνδεση, η καρτέλα που έχει **τον ίδιο κωδικό** με το κείμενο
///    της κλήσης: κουβαλά ίσως δικό της αναγνωριστικό (π.χ. IP εκτυπωτή) που ο
///    κανόνας «PC + κωδικός» δεν θα μάντευε ποτέ.
/// 3. Αλλιώς ο ίδιος ο κανόνας πάνω στο ελεύθερο κείμενο — ό,τι κάνει ήδη το
///    VNC για κλήση που δεν πέρασε ποτέ από τον Κατάλογο.
///
/// Null όταν δεν προκύπτει τίποτα χρήσιμο: το ticket φεύγει χωρίς εξοπλισμό,
/// χωρίς σφάλμα.
Future<LansweeperAssetTarget?> resolveLansweeperAssetTarget({
  required EquipmentRepository repository,
  required int? equipmentId,
  required String? equipmentText,
}) async {
  if (equipmentId != null) {
    final linked = await repository.getLansweeperAssetFieldsById(equipmentId);
    if (linked != null) {
      return lansweeperAssetTargetFor(
        storedAssetName: linked.assetName,
        equipmentCode: linked.code,
      );
    }
  }

  final text = equipmentText?.trim() ?? '';
  if (text.isEmpty) return null;

  final byCode = await repository.getLansweeperAssetFieldsByCode(text);
  if (byCode != null) {
    return lansweeperAssetTargetFor(
      storedAssetName: byCode.assetName,
      equipmentCode: byCode.code,
    );
  }

  return lansweeperAssetTargetFor(equipmentCode: text);
}

/// Οι εξοπλισμοί **όλων** των εγγραφών που ενώνονται σε ένα αίτημα, όπως θα
/// σταλούν (`AddAsset` για τον καθένα) — η μοναδική υλοποίηση, κοινή για την
/// προεπισκόπηση της φόρμας και την αποστολή.
///
/// Ως τώρα έφευγε μόνο ο εξοπλισμός της πρώτης κλήσης· οι υπόλοιποι χάνονταν
/// σιωπηλά, ενώ η περιγραφή του αιτήματος μιλούσε και γι' αυτούς.
///
/// Σειρά των [equipment] (πρώτη εμφάνιση κερδίζει). Το ίδιο μηχάνημα από δύο
/// κλήσεις μπαίνει **μία** φορά· εγγραφή χωρίς εξοπλισμό δεν προσθέτει τίποτα.
Future<List<LansweeperAssetTarget>> resolveLansweeperAssetTargets({
  required EquipmentRepository repository,
  required List<({int? equipmentId, String? equipmentText})> equipment,
}) async {
  final targets = <LansweeperAssetTarget>[];
  final seen = <String>{};
  for (final entry in equipment) {
    final target = await resolveLansweeperAssetTarget(
      repository: repository,
      equipmentId: entry.equipmentId,
      equipmentText: entry.equipmentText,
    );
    if (target == null) continue;
    if (seen.add('${target.kind.name}|${target.value.toLowerCase()}')) {
      targets.add(target);
    }
  }
  return targets;
}
