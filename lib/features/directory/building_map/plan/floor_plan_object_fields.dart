import '../../../../core/models/floor_plan_object_kind.dart';
import '../../../calls/utils/remote_param_validator.dart';
import '../../../calls/utils/vnc_remote_target.dart';
import 'floor_plan_ports.dart';

/// Οι κανόνες των πεδίων στα στοιχεία μιας συσκευής του χάρτη: τι δέχεται
/// το καθένα, και τι λέει όταν κάτι δεν στέκει. Καθαρές συναρτήσεις — το
/// πλαίσιο απλώς τις ρωτά.

/// Το μήνυμα για IP που δεν στέκει· `null` όταν το πεδίο είναι κενό ή η IP
/// έγκυρη. Ίδια διάγνωση με τους υπολογιστές του Καταλόγου (π.χ. «Το 300
/// ξεπερνά το όριο 255»).
String? floorPlanIpError(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (VncRemoteTarget.tryParseIpv4Host(text) != null) return null;
  return RemoteParamValidator.diagnoseIpAttempt(text) ??
      'Δεν είναι διεύθυνση IP — π.χ. 10.10.1.25.';
}

/// Η IP όπως αποθηκεύεται: κομμένα κενά, κόμμα → τελεία.
String floorPlanNormalizedIp(String raw) =>
    VncRemoteTarget.tryParseIpv4Host(raw) ?? raw.trim();

/// Το μήνυμα για πλήθος θυρών εκτός ορίων· `null` όταν είναι κενό (καμία
/// θύρα) ή από 0 ως [kFloorPlanMaxPorts].
String? floorPlanPortCountError(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final count = int.tryParse(text);
  if (count == null || count < 0 || count > kFloorPlanMaxPorts) {
    return 'Από 0 ως $kFloorPlanMaxPorts θύρες.';
  }
  return null;
}

/// Το μήνυμα για ύψος σε U που δεν χωρά σε καμπίνα [units] U· `null` όταν
/// είναι από 1 ως [units]. Αν πατά πάνω σε άλλη συσκευή το λέει η καμπίνα
/// κατά την αποθήκευση.
String? floorPlanHeightUError(String raw, int units) {
  final height = int.tryParse(raw.trim());
  if (height == null || height < 1 || height > units) {
    return 'Από 1 ως $units U.';
  }
  return null;
}

/// Πώς θα λέγεται η πρώτη θύρα ενός patch panel με όνομα [panelName] στην
/// καμπίνα [cabinetName], με διαχωριστικό [separator] — η προεπισκόπηση του
/// πλαισίου, π.χ. «MC.2.S.Molex 1.1».
String floorPlanPortSeparatorPreview({
  required String panelName,
  required String? cabinetName,
  required String separator,
}) => floorPlanPortAutoName(
  symbol: FloorPlanSymbol.patchPanel,
  objectName: panelName,
  cabinetName: cabinetName,
  number: 1,
  portSeparator: separator,
);

/// Μία ομάδα θυρών όπως τη γράφει η φόρμα της συσκευής: από ποια υπάρχουσα
/// ομάδα ξεκίνησε ([source], `null` = νέα), και τα πεδία της όπως γράφτηκαν.
typedef FloorPlanPortGroupDraft = ({
  int? source,
  String count,
  String prefix,
  String speed,
  bool continues,
});

/// Οι ομάδες [groups] σε πεδία φόρμας, με το πλήθος της καθεμιάς. Το switch
/// χωρίς πρόθεμα δείχνει «Gi», όπως ονομάζει τις θύρες του.
List<FloorPlanPortGroupDraft> floorPlanPortGroupDrafts(
  List<FloorPlanPortGroupSpec> groups, {
  required bool isSwitch,
}) => [
  for (final g in groups)
    (
      source: g.source,
      count: g.count == 0 ? '' : '${g.count}',
      prefix: g.group.prefix ?? (isSwitch ? kFloorPlanDefaultPortType : ''),
      speed: g.group.speed ?? '',
      continues: g.group.continues,
    ),
];

/// Ό,τι γράφει η φόρμα, ως ομάδες για αποθήκευση. Κενό πλήθος = καμία θύρα.
/// Οι επόμενες ομάδες χωρίς θύρες παραλείπονται — ομάδα χωρίς θύρες δεν
/// δείχνει τίποτα· η πρώτη μένει πάντα, γιατί κρατά το πρόθεμα της
/// συσκευής. Το «συνεχίζει» δεν έχει νόημα στην πρώτη.
List<FloorPlanPortGroupSpec> floorPlanPortGroupSpecs(
  List<FloorPlanPortGroupDraft> drafts,
) {
  String? blank(String s) => s.trim().isEmpty ? null : s.trim();
  return [
    for (final (i, d) in drafts.indexed)
      if (i == 0 || (int.tryParse(d.count.trim()) ?? 0) > 0)
        (
          source: d.source,
          count: int.tryParse(d.count.trim()) ?? 0,
          group: FloorPlanPortGroup(
            prefix: blank(d.prefix),
            speed: blank(d.speed),
            continues: i > 0 && d.continues,
          ),
        ),
  ];
}
