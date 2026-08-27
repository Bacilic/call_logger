import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/managed_server.dart';
import '../../../core/providers/servers_provider.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/services/server_sessions/logoff_target_resolution.dart';
import '../provider/remote_paths_provider.dart';
import 'vnc_remote_target.dart';

/// Ό,τι χρειάζεται κάθε ενέργεια διακομιστή που ξεκινά από κάρτα εξοπλισμού.
typedef EquipmentServerContext = ({
  /// Το όνομα σταθμού του εξοπλισμού (π.χ. `PC5068`), ή κενό όταν δεν προκύπτει.
  String stationName,

  /// Ο προτεινόμενος διακομιστής μαζί με το γιατί προτάθηκε.
  ServerTargetChoice choice,

  /// Όλοι οι καταχωρημένοι διακομιστές, για τον επιλογέα.
  List<ManagedServer> servers,
});

/// Βρίσκει σταθμό και διακομιστή για έναν κωδικό εξοπλισμού.
///
/// **Ζει σε ένα σημείο επίτηδες.** Και η «Αποσύνδεση χρήστη» και οι
/// «Εκτυπωτές» ξεκινούν από την ίδια ερώτηση: ποιο PC είναι αυτός ο
/// εξοπλισμός και ποιον διακομιστή ρωτάμε γι' αυτόν. Δύο αντίγραφα του
/// κανόνα θα απέκλιναν σιωπηλά — και οι δύο οθόνες θα έδειχναν διαφορετικά
/// πράγματα για τον ίδιο υπολογιστή.
Future<EquipmentServerContext> resolveEquipmentServerContext(
  WidgetRef ref,
  String equipmentCode,
) async {
  final servers = await ref.read(serversListProvider.future);
  final tools = await ref.read(remoteToolsCatalogProvider.future);

  final equipment = LookupService.instance.findEquipmentByCode(equipmentCode);

  // Το όνομα σταθμού βγαίνει από τον ΙΔΙΟ κανόνα που χρησιμοποιεί το VNC,
  // ώστε να μην υπάρχουν δύο ορισμοί του «ποιο PC είναι ο εξοπλισμός 5068».
  var station = equipment != null
      ? equipment.vncTargetResolved(tools)
      : VncRemoteTarget.hostForUnknownEquipmentText(equipmentCode);
  if (station == 'Άγνωστο') station = '';

  final remoteAddress = equipment?.rdpHostResolved(tools)?.trim() ?? '';
  final choice = LogoffTargetResolution.resolveServer(
    equipmentRemoteAddress: remoteAddress,
    servers: servers,
  );

  return (stationName: station, choice: choice, servers: servers);
}
