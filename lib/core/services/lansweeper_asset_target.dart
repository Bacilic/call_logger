import '../../features/calls/utils/vnc_remote_target.dart';

/// Ποια παράμετρος του `AddAsset` θα μεταφέρει τον στόχο: όνομα ή IP.
enum LansweeperAssetTargetKind { assetName, ipAddress }

/// Στόχος σύνδεσης εξοπλισμού σε ticket Lansweeper (`AddAsset`).
class LansweeperAssetTarget {
  const LansweeperAssetTarget({required this.value, required this.kind});

  final String value;
  final LansweeperAssetTargetKind kind;
}

/// Ο στόχος asset για το `AddAsset`: η αποθηκευμένη τιμή αν υπάρχει, αλλιώς ο
/// κοινός κανόνας του VNC από τον κωδικό εξοπλισμού ([VncRemoteTarget]):
/// 3–6 ψηφία → «PC + κωδικός», IPv4 μένει IPv4, όνομα με γράμμα μένει ως έχει.
///
/// Null όταν δεν προκύπτει τίποτα χρήσιμο — τότε το ticket απλώς δεν συνδέει
/// εξοπλισμό, χωρίς σφάλμα.
LansweeperAssetTarget? lansweeperAssetTargetFor({
  String? storedAssetName,
  String? equipmentCode,
}) {
  final stored = storedAssetName?.trim() ?? '';
  if (stored.isNotEmpty) return _classify(stored);

  final code = equipmentCode?.trim() ?? '';
  if (code.isEmpty) return null;
  final resolved = VncRemoteTarget.resolveValidVncHost(code);
  if (resolved == null) return null;
  return _classify(resolved);
}

LansweeperAssetTarget _classify(String value) {
  final ip = VncRemoteTarget.tryParseIpv4Host(value);
  if (ip != null) {
    return LansweeperAssetTarget(
      value: ip,
      kind: LansweeperAssetTargetKind.ipAddress,
    );
  }
  return LansweeperAssetTarget(
    value: value,
    kind: LansweeperAssetTargetKind.assetName,
  );
}
