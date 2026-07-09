import 'package:call_logger/features/lamp/widgets/lamp_result_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> rowWithNetwork() => <String, Object?>{
    'code': 3900,
    'description': 'Πολυμηχάνημα Α4',
    'model_id': 5,
    'model_name': 'Kyocera M2540',
    'contract_id': 9,
    'contract_name': 'Σύμβαση εκτυπωτικών',
    'owner_id': 11,
    'last_name': 'Παπαδοπούλου',
    'office_id': 21,
    'office_name': 'Πληροφορική',
    'network_node': '710',
    'ip_address': '10.10.223.43',
    'network_vlan': 'Οικονομικού',
    'network_mac': '70B5E869B696',
    'network_name': 'PR3900',
    'network_description': 'ΠολυμηχάνημαΑ4',
    'network_comments': 'Ασύρματο',
  };

  group('EquipmentViewModel — κάρτα Δίκτυο', () {
    test('σειρά καρτών: Εξοπλισμός, Μοντέλο, Δίκτυο, Ιδιοκτήτης, Τμήμα, Σύμβαση',
        () {
      final vm = EquipmentViewModel.fromRow(rowWithNetwork());
      expect(vm.sections.map((s) => s.type).toList(), <InfoSectionType>[
        InfoSectionType.equipment,
        InfoSectionType.model,
        InfoSectionType.network,
        InfoSectionType.owner,
        InfoSectionType.department,
        InfoSectionType.contract,
      ]);
    });

    test('η κάρτα Δίκτυο δείχνει όλα τα πεδία με τις σωστές ετικέτες', () {
      final vm = EquipmentViewModel.fromRow(rowWithNetwork());
      final network = vm.sections.singleWhere(
        (s) => s.type == InfoSectionType.network,
      );
      final byLabel = <String, String?>{
        for (final item in network.items) item.label: item.value,
      };
      expect(byLabel, <String, String?>{
        'Κόμβος': '710',
        'IP': '10.10.223.43',
        'VLAN': 'Οικονομικού',
        'MAC': '70B5E869B696',
        'Hostname': 'PR3900',
        'Περιγραφή': 'ΠολυμηχάνημαΑ4',
        'Σχόλια': 'Ασύρματο',
      });
      // Επεξεργάσιμη με στόχο την εγγραφή εξοπλισμού (code).
      expect(network.canEdit, isTrue);
      expect(network.recordId, 3900);
    });

    test('χωρίς δεδομένα δικτύου η κάρτα Δίκτυο δεν εμφανίζεται', () {
      final row = rowWithNetwork()
        ..removeWhere((key, _) => key.startsWith('network_'))
        ..remove('ip_address');
      final vm = EquipmentViewModel.fromRow(row);
      expect(
        vm.sections.any((s) => s.type == InfoSectionType.network),
        isFalse,
      );
    });

    test('τίτλος και μετάδοση: το Δίκτυο δεν έχει μεταφορά στη νέα βάση', () {
      // Ο τίτλος της ενότητας και η μη-συμμετοχή στη μεταφορά.
      expect(InfoSectionType.network.title, 'ΔΙΚΤΥΟ');
      const transferable = <InfoSectionType>{
        InfoSectionType.equipment,
        InfoSectionType.department,
        InfoSectionType.owner,
      };
      expect(transferable.contains(InfoSectionType.network), isFalse);
    });
  });
}
