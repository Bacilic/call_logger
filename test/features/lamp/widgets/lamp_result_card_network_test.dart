import 'package:call_logger/features/lamp/models/lamp_equipment_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

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
    test(
      'σειρά καρτών: Εξοπλισμός, Μοντέλο, Δίκτυο, Ιδιοκτήτης, Τμήμα, Σύμβαση',
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
      },
    );

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

    test('η αιτιολογία αποδοχής συνοδεύει το Hostname στην κάρτα και στον '
        'διάλογο επεξεργασίας, χωρίς να γίνεται επεξεργάσιμο πεδίο', () {
      final vm = EquipmentViewModel.fromRow(<String, Object?>{
        ...rowWithNetwork(),
        'network_name_accepted_note': 'Νεμέα',
      });
      final network = vm.sections.singleWhere(
        (s) => s.type == InfoSectionType.network,
      );
      final item = network.items.singleWhere((i) => i.label == 'Hostname');
      expect(item.value, 'PR3900');
      expect(item.note, '✓ Αποδεκτό: Νεμέα');
      final field = network.editableFields.singleWhere(
        (f) => f.fieldKey == 'network_name',
      );
      expect(field.note, '✓ Αποδεκτό: Νεμέα');
      expect(
        network.editableFields.any((f) => f.fieldKey.contains('accepted')),
        isFalse,
      );
      // Μόνο η στήλη που κρίθηκε φέρει τη γραμμή.
      expect(network.items.singleWhere((i) => i.label == 'IP').note, isNull);
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

  group('κόστος Λάμπας: διαβάζεται με τη γραφή που αποθηκεύτηκε', () {
    test('τελεία υποδιαστολή, όπως όλα τα κόστη της Λάμπας', () {
      expect(EquipmentViewModel.parseLampMoney('1537.5000'), 1537.5);
    });
    test('ελληνική γραφή από χειροκίνητη διόρθωση', () {
      expect(EquipmentViewModel.parseLampMoney('1.537,50 €'), 1537.5);
    });
    test('πολλές τελείες χωρίς κόμμα είναι χιλιάδες', () {
      expect(EquipmentViewModel.parseLampMoney('1.234.567'), 1234567);
    });
    test('κείμενο που δεν είναι ποσό μένει αδιάβαστο', () {
      expect(EquipmentViewModel.parseLampMoney('δωρεά'), isNull);
    });
  });

  group('EquipmentViewModel — ΦΩΤΟΓΡΑΦΙΑ όλων των ενοτήτων', () {
    setUpAll(() => initializeDateFormatting('el'));

    test('πλούσια γραμμή', () {
      expect(_dumpSections(EquipmentViewModel.fromRow(_richRow)), [
        'S equipment 1001 true',
        '  I Κωδικός=1001|1|null',
        '  I Περιγραφή=Εκτυπωτής Laser A3|3|null',
        '  I Serial No=SN123|1|null',
        '  I Αρ. Παγίου=INV-1|1|null',
        '  I Κατάσταση=Ενεργός|1|null',
        '  I Συνδεδεμένο σε=1000|1|null',
        '  I Παραλαβή=15/3/2021|1|null',
        '  I Εγγύηση=15/3/2024|1|null',
        '  I Κόστος=1.234,50 €|1|null',
        '  I Σχόλια=Δικτυακός|3|null',
        '  F code=1001|Κωδικός|code|1|false|null',
        '  F description=Εκτυπωτής Laser A3|Περιγραφή|text|3|true|null',
        '  F model_id=42|Κωδ. μοντέλου|code|1|false|null',
        '  F model_original_text=HP M428|Μοντέλο (αρχικό)|text|1|false|null',
        '  F serial_no=SN123|Serial No|text|1|false|null',
        '  F asset_no=INV-1|Αρ. Παγίου|text|1|false|null',
        '  F state_id=1|Κωδ. κατάστασης|code|1|false|null',
        '  F state_name=Ενεργός|Κατάσταση|text|1|false|null',
        '  F state_original_text=ενεργ|Κατάσταση (αρχική)|text|1|false|null',
        '  F set_master=1000|Συνδεδεμένο σε|code|1|false|null',
        '  F set_master_original_text=1000|Σύνδεση (αρχική)|text|1|false|null',
        '  F contract_id=15|Κωδ. σύμβασης|code|1|false|null',
        '  F contract_original_text=ΣΥΜ-15|Σύμβαση (αρχική)|text|1|false|null',
        '  F maintenance_contract=Συντήρηση|Συντήρηση|text|1|false|null',
        '  F receiving_date=2021-03-15|Παραλαβή|date|1|false|null',
        '  F end_of_guarantee_date=2024-03-15T10:00:00|Εγγύηση|date|1|false|null',
        '  F cost=1.234,50|Κόστος|text|1|false|null',
        '  F owner_id=7|Κωδ. κατόχου|code|1|false|null',
        '  F owner_original_text=Παπαδόπουλος Γ.|Κάτοχος (αρχικός)|text|1|false|null',
        '  F office_id=3|Κωδ. γραφείου|code|1|false|null',
        '  F office_original_text=Πληροφορική|Γραφείο (αρχικό)|text|1|false|null',
        '  F equipment_attributes=A3|Χαρακτ. εξοπλ.|text|3|false|null',
        '  F equipment_comments=Δικτυακός|Σχόλια|text|3|false|null',
        'S model 42 true',
        '  I Μοντέλο=LaserJet|1|null',
        '  I Κατηγορία=Εκτυπωτές|1|null',
        '  I Υποκατηγ.=Laser|1|null',
        '  I Κατασκευ.=HP|1|null',
        '  I Χαρακτ.=40ppm|3|null',
        '  I Αναλώσιμα=Toner 59A|2|null',
        '  F model_id=42|Κωδ. μοντέλου|code|1|false|null',
        '  F model_name=LaserJet|Μοντέλο|text|1|true|null',
        '  F category_code=4|Κωδ. κατηγορίας|code|1|false|null',
        '  F category_code_original_text=ΕΚΤ|Κατηγ. (αρχική)|text|1|false|null',
        '  F category_name=Εκτυπωτές|Κατηγορία|text|1|false|null',
        '  F subcategory_code=8|Κωδ. υποκατηγ.|code|1|false|null',
        '  F subcategory_code_original_text=LSR|Υποκατ. (αρχική)|text|1|false|null',
        '  F subcategory_name=Laser|Υποκατηγ.|text|1|false|null',
        '  F manufacturer=2|Κωδ. κατασκ.|code|1|false|null',
        '  F manufacturer_original_text=hp|Κατασκ. (αρχικός)|text|1|false|null',
        '  F manufacturer_name=HP|Κατασκευ.|text|1|false|null',
        '  F manufacturer_code=HP-01|Κωδικός κατασκ.|text|1|false|null',
        '  F model_attributes=40ppm|Χαρακτ.|text|3|false|null',
        '  F consumables=Toner 59A|Αναλώσιμα|text|2|false|null',
        '  F network_connectivity=1|Δικτύωση|code|1|false|null',
        'S network 1001 true',
        '  I Κόμβος=710|1|null',
        '  I IP=10.0.0.5|1|✓ Αποδεκτό: διπλή IP γνωστή',
        '  I VLAN=V10|1|null',
        '  I MAC=AA:BB|1|null',
        '  I Hostname=PR1001|1|null',
        '  I Περιγραφή=Εκτυπωτής|2|null',
        '  I Σχόλια=Ενσύρματο|3|null',
        '  F network_node=710|Κόμβος|text|1|false|null',
        '  F ip_address=10.0.0.5|IP|text|1|true|✓ Αποδεκτό: διπλή IP γνωστή',
        '  F network_vlan=V10|VLAN|text|1|false|null',
        '  F network_mac=AA:BB|MAC|text|1|false|null',
        '  F network_name=PR1001|Hostname|text|1|false|null',
        '  F network_description=Εκτυπωτής|Περιγραφή|text|2|false|null',
        '  F network_comments=Ενσύρματο|Σχόλια|text|3|false|null',
        'S owner 7 true',
        '  I Όνομα=Παπαδόπουλος Γιώργος|2|null',
        '  I Email=g@org.gr|1|null',
        '  I Τηλέφωνα=210 1 · 690 2 · 211 3|2|null',
        '  F owner_id=7|Κωδ. κατόχου|code|1|false|null',
        '  F last_name=Παπαδόπουλος|Επώνυμο|text|1|true|null',
        '  F first_name=Γιώργος|Όνομα|text|1|false|null',
        '  F owner_office=3|Κωδ. γραφείου|code|1|false|null',
        '  F owner_office_original_text=Πληρ.|Γραφείο (αρχικό)|text|1|false|null',
        '  F owner_email=g@org.gr|Email|email|1|false|null',
        '  F owner_phones=210 1; 690 2\n211 3,,|Τηλέφωνα|phone|2|false|null',
        'S department 3 true',
        '  I Τμήμα=Τμήμα Πληροφορικής|2|null',
        '  I Οργανισμός=Νοσοκομείο|1|null',
        '  I Email=it@org.gr|1|null',
        '  I Τηλέφωνα=210 9|2|null',
        '  I Κτίριο=Κτίριο Α|1|null',
        '  I Όροφος=2,5|1|null',
        '  F office_id=3|Κωδ. γραφείου|code|1|false|null',
        '  F office_name=Τμήμα Πληροφορικής|Τμήμα|text|1|true|null',
        '  F organization=1|Κωδ. οργανισμού|code|1|false|null',
        '  F organization_name=Νοσοκομείο|Οργανισμός|text|1|false|null',
        '  F department=5|Κωδ. υπηρεσίας|code|1|false|null',
        '  F department_name=Διοικητική|Υπηρεσία|text|1|false|null',
        '  F responsible=7|Υπεύθυνος|code|1|false|null',
        '  F responsible_original_text=Παπ.|Υπεύθ. (αρχικός)|text|1|false|null',
        '  F office_email=it@org.gr|Email|email|1|false|null',
        '  F office_phones=210 9|Τηλέφωνα|phone|2|false|null',
        '  F building=Κτίριο Α|Κτίριο|text|1|false|null',
        '  F level=2,5|Όροφος|number|1|false|null',
        'S contract 15 true',
        '  I Σύμβαση=Σύμβαση εκτυπωτών|1|null',
        '  I Κατηγορία=Εκτυπωτικά|1|null',
        '  I Προμηθ.=Office A.E.|1|null',
        '  I Ανάθεση=ΑΝΑΘ-1|1|null',
        '  I Διακήρυξη=ΔΙΑΚ-1|1|null',
        '  I Συντήρηση=Συντήρηση|1|null',
        '  I Σχόλια=Ετήσια|3|null',
        '  F contract_id=15|Κωδ. σύμβασης|code|1|false|null',
        '  F contract_name=Σύμβαση εκτυπωτών|Σύμβαση|text|1|true|null',
        '  F contract_category=3|Κωδ. κατηγορίας|code|1|false|null',
        '  F contract_category_original_text=ΕΚΤ|Κατηγ. (αρχική)|text|1|false|null',
        '  F contract_category_name=Εκτυπωτικά|Κατηγορία|text|1|false|null',
        '  F supplier_id=9|Κωδ. προμηθ.|code|1|false|null',
        '  F supplier_original_text=Office|Προμηθ. (αρχικός)|text|1|false|null',
        '  F supplier_name=Office A.E.|Προμηθ.|text|1|false|null',
        '  F contract_start_date=2021-01-01|Έναρξη|date|1|false|null',
        '  F contract_end_date=2025-12-31|Λήξη|date|1|false|null',
        '  F contract_declaration=ΔΙΑΚ-1|Διακήρυξη|text|1|false|null',
        '  F contract_award=ΑΝΑΘ-1|Ανάθεση|text|1|false|null',
        '  F contract_cost=5000|Κόστος|text|1|false|null',
        '  F contract_committee=Επιτροπή Α|Επιτροπή|text|1|false|null',
        '  F contract_comments=Ετήσια|Σχόλια|text|3|false|null',
      ]);
    });

    test('γραμμή με εφεδρικές τιμές και δύσκολες μορφές', () {
      expect(_dumpSections(EquipmentViewModel.fromRow(_fallbackRow)), [
        'S equipment 2002 true',
        '  I Κωδικός=2002|1|null',
        '  I Serial No=SN-OLD|1|null',
        '  I Παραλαβή=15/03/2021|1|null',
        '  I Κόστος=123,45 €|1|null',
        '  F code=2002|Κωδικός|code|1|false|null',
        '  F description=null|Περιγραφή|text|3|true|null',
        '  F model_id=null|Κωδ. μοντέλου|code|1|false|null',
        '  F model_original_text=Μοντέλο χωρίς κωδικό|Μοντέλο (αρχικό)|text|1|false|null',
        '  F serial_no=SN-OLD|Serial No|text|1|false|null',
        '  F asset_no=null|Αρ. Παγίου|text|1|false|null',
        '  F state_id=null|Κωδ. κατάστασης|code|1|false|null',
        '  F state_name=null|Κατάσταση|text|1|false|null',
        '  F state_original_text=null|Κατάσταση (αρχική)|text|1|false|null',
        '  F set_master=2002|Συνδεδεμένο σε|code|1|false|null',
        '  F set_master_original_text=null|Σύνδεση (αρχική)|text|1|false|null',
        '  F contract_id=null|Κωδ. σύμβασης|code|1|false|null',
        '  F contract_original_text=Παλιά σύμβαση|Σύμβαση (αρχική)|text|1|false|null',
        '  F maintenance_contract=null|Συντήρηση|text|1|false|null',
        '  F receiving_date=15/03/2021|Παραλαβή|date|1|false|null',
        '  F end_of_guarantee_date=null|Εγγύηση|date|1|false|null',
        '  F cost=123.45|Κόστος|text|1|false|null',
        '  F owner_id=null|Κωδ. κατόχου|code|1|false|null',
        '  F owner_original_text=Κάτοχος από κείμενο|Κάτοχος (αρχικός)|text|1|false|null',
        '  F office_id=null|Κωδ. γραφείου|code|1|false|null',
        '  F office_original_text=Γραφείο από κείμενο|Γραφείο (αρχικό)|text|1|false|null',
        '  F equipment_attributes=null|Χαρακτ. εξοπλ.|text|3|false|null',
        '  F equipment_comments=null|Σχόλια|text|3|false|null',
        'S model null false',
        '  I Μοντέλο=Μοντέλο χωρίς κωδικό|1|null',
        '  F model_id=null|Κωδ. μοντέλου|code|1|false|null',
        '  F model_name=null|Μοντέλο|text|1|true|null',
        '  F category_code=null|Κωδ. κατηγορίας|code|1|false|null',
        '  F category_code_original_text=null|Κατηγ. (αρχική)|text|1|false|null',
        '  F category_name=null|Κατηγορία|text|1|false|null',
        '  F subcategory_code=null|Κωδ. υποκατηγ.|code|1|false|null',
        '  F subcategory_code_original_text=null|Υποκατ. (αρχική)|text|1|false|null',
        '  F subcategory_name=null|Υποκατηγ.|text|1|false|null',
        '  F manufacturer=null|Κωδ. κατασκ.|code|1|false|null',
        '  F manufacturer_original_text=null|Κατασκ. (αρχικός)|text|1|false|null',
        '  F manufacturer_name=null|Κατασκευ.|text|1|false|null',
        '  F manufacturer_code=null|Κωδικός κατασκ.|text|1|false|null',
        '  F model_attributes=null|Χαρακτ.|text|3|false|null',
        '  F consumables=null|Αναλώσιμα|text|2|false|null',
        '  F network_connectivity=null|Δικτύωση|code|1|false|null',
        'S owner 12 true',
        '  I Όνομα=Κάτοχος από κείμενο|2|null',
        '  F owner_id=12|Κωδ. κατόχου|code|1|false|null',
        '  F last_name=null|Επώνυμο|text|1|true|null',
        '  F first_name=null|Όνομα|text|1|false|null',
        '  F owner_office=null|Κωδ. γραφείου|code|1|false|null',
        '  F owner_office_original_text=null|Γραφείο (αρχικό)|text|1|false|null',
        '  F owner_email=null|Email|email|1|false|null',
        '  F owner_phones=null|Τηλέφωνα|phone|2|false|null',
        'S department 4 true',
        '  I Τμήμα=Γραφείο από κείμενο|2|null',
        '  I Όροφος=ισόγειο|1|null',
        '  F office_id=4|Κωδ. γραφείου|code|1|false|null',
        '  F office_name=null|Τμήμα|text|1|true|null',
        '  F organization=null|Κωδ. οργανισμού|code|1|false|null',
        '  F organization_name=null|Οργανισμός|text|1|false|null',
        '  F department=null|Κωδ. υπηρεσίας|code|1|false|null',
        '  F department_name=null|Υπηρεσία|text|1|false|null',
        '  F responsible=null|Υπεύθυνος|code|1|false|null',
        '  F responsible_original_text=null|Υπεύθ. (αρχικός)|text|1|false|null',
        '  F office_email=null|Email|email|1|false|null',
        '  F office_phones=null|Τηλέφωνα|phone|2|false|null',
        '  F building=null|Κτίριο|text|1|false|null',
        '  F level=ισόγειο|Όροφος|number|1|false|null',
        'S contract null false',
        '  I Σύμβαση=Παλιά σύμβαση|1|null',
        '  F contract_id=null|Κωδ. σύμβασης|code|1|false|null',
        '  F contract_name=null|Σύμβαση|text|1|true|null',
        '  F contract_category=null|Κωδ. κατηγορίας|code|1|false|null',
        '  F contract_category_original_text=null|Κατηγ. (αρχική)|text|1|false|null',
        '  F contract_category_name=null|Κατηγορία|text|1|false|null',
        '  F supplier_id=null|Κωδ. προμηθ.|code|1|false|null',
        '  F supplier_original_text=null|Προμηθ. (αρχικός)|text|1|false|null',
        '  F supplier_name=null|Προμηθ.|text|1|false|null',
        '  F contract_start_date=null|Έναρξη|date|1|false|null',
        '  F contract_end_date=null|Λήξη|date|1|false|null',
        '  F contract_declaration=null|Διακήρυξη|text|1|false|null',
        '  F contract_award=null|Ανάθεση|text|1|false|null',
        '  F contract_cost=null|Κόστος|text|1|false|null',
        '  F contract_committee=null|Επιτροπή|text|1|false|null',
        '  F contract_comments=null|Σχόλια|text|3|false|null',
      ]);
    });

    test('η ενημέρωση πεδίων ξαναχτίζει τις ενότητες από την ενωμένη γραμμή', () {
      final vm = EquipmentViewModel.fromRow(
        _fallbackRow,
      ).copyWithUpdatedFields({'serial_no': 'SN-NEW', 'cost': null});
      expect(_dumpSections(vm).takeWhile((l) => l != 'S model null false').toList(), [
        'S equipment 2002 true',
        '  I Κωδικός=2002|1|null',
        '  I Serial No=SN-NEW|1|null',
        '  I Παραλαβή=15/03/2021|1|null',
        '  F code=2002|Κωδικός|code|1|false|null',
        '  F description=null|Περιγραφή|text|3|true|null',
        '  F model_id=null|Κωδ. μοντέλου|code|1|false|null',
        '  F model_original_text=Μοντέλο χωρίς κωδικό|Μοντέλο (αρχικό)|text|1|false|null',
        '  F serial_no=SN-NEW|Serial No|text|1|false|null',
        '  F asset_no=null|Αρ. Παγίου|text|1|false|null',
        '  F state_id=null|Κωδ. κατάστασης|code|1|false|null',
        '  F state_name=null|Κατάσταση|text|1|false|null',
        '  F state_original_text=null|Κατάσταση (αρχική)|text|1|false|null',
        '  F set_master=2002|Συνδεδεμένο σε|code|1|false|null',
        '  F set_master_original_text=null|Σύνδεση (αρχική)|text|1|false|null',
        '  F contract_id=null|Κωδ. σύμβασης|code|1|false|null',
        '  F contract_original_text=Παλιά σύμβαση|Σύμβαση (αρχική)|text|1|false|null',
        '  F maintenance_contract=null|Συντήρηση|text|1|false|null',
        '  F receiving_date=15/03/2021|Παραλαβή|date|1|false|null',
        '  F end_of_guarantee_date=null|Εγγύηση|date|1|false|null',
        '  F cost=null|Κόστος|text|1|false|null',
        '  F owner_id=null|Κωδ. κατόχου|code|1|false|null',
        '  F owner_original_text=Κάτοχος από κείμενο|Κάτοχος (αρχικός)|text|1|false|null',
        '  F office_id=null|Κωδ. γραφείου|code|1|false|null',
        '  F office_original_text=Γραφείο από κείμενο|Γραφείο (αρχικό)|text|1|false|null',
        '  F equipment_attributes=null|Χαρακτ. εξοπλ.|text|3|false|null',
        '  F equipment_comments=null|Σχόλια|text|3|false|null',
      ]);
      expect(vm.sourceRow['serial_no'], 'SN-NEW');
      expect(vm.sourceRow.containsKey('cost'), isTrue);
      expect(vm.sourceRow['cost'], isNull);
    });
  });
}

/// Κάθε ενότητα σε μία γραμμή ταυτότητας, και κάθε τιμή και πεδίο σε δική
/// του: ό,τι αλλάξει στη μετάφραση φαίνεται ως διαφορά κειμένου.
List<String> _dumpSections(EquipmentViewModel vm) => [
  for (final s in vm.sections) ...[
    'S ${s.type.name} ${s.recordId} ${s.canEdit}',
    for (final i in s.items)
      '  I ${i.label}=${i.value}|${i.maxLines}|${i.note}',
    for (final f in s.editableFields)
      '  F ${f.fieldKey}=${f.value}|${f.label}|${f.type.name}|${f.maxLines}|'
          '${f.autofocus}|${f.note}',
  ],
];

const _richRow = <String, Object?>{
  'code': 1001,
  'description': '  Εκτυπωτής Laser A3  ',
  'model_id': 42,
  'model_original_text': 'HP M428',
  'serial_no': 'SN123',
  'asset_no': 'INV-1',
  'state_id': 1,
  'state_name': 'Ενεργός',
  'state_original_text': 'ενεργ',
  'set_master': 1000,
  'set_master_original_text': '1000',
  'contract_id': 15,
  'contract_original_text': 'ΣΥΜ-15',
  'maintenance_contract': 'Συντήρηση',
  'receiving_date': '2021-03-15',
  'end_of_guarantee_date': '2024-03-15T10:00:00',
  'cost': '1.234,50',
  'owner_id': 7,
  'owner_original_text': 'Παπαδόπουλος Γ.',
  'office_id': 3,
  'office_original_text': 'Πληροφορική',
  'equipment_attributes': 'A3',
  'equipment_comments': 'Δικτυακός',
  'model_name': 'LaserJet',
  'category_code': 4,
  'category_code_original_text': 'ΕΚΤ',
  'category_name': 'Εκτυπωτές',
  'subcategory_code': 8,
  'subcategory_code_original_text': 'LSR',
  'subcategory_name': 'Laser',
  'manufacturer': 2,
  'manufacturer_original_text': 'hp',
  'manufacturer_name': 'HP',
  'manufacturer_code': 'HP-01',
  'model_attributes': '40ppm',
  'consumables': 'Toner 59A',
  'network_connectivity': 1,
  'network_node': '710',
  'ip_address': '10.0.0.5',
  'ip_address_accepted_note': 'διπλή IP γνωστή',
  'network_vlan': 'V10',
  'network_mac': 'AA:BB',
  'network_name': 'PR1001',
  'network_description': 'Εκτυπωτής',
  'network_comments': 'Ενσύρματο',
  'contract_name': 'Σύμβαση εκτυπωτών',
  'contract_category': 3,
  'contract_category_original_text': 'ΕΚΤ',
  'contract_category_name': 'Εκτυπωτικά',
  'supplier_id': 9,
  'supplier_original_text': 'Office',
  'supplier_name': 'Office A.E.',
  'contract_start_date': '2021-01-01',
  'contract_end_date': '2025-12-31',
  'contract_declaration': 'ΔΙΑΚ-1',
  'contract_award': 'ΑΝΑΘ-1',
  'contract_cost': '5000',
  'contract_committee': 'Επιτροπή Α',
  'contract_comments': 'Ετήσια',
  'last_name': 'Παπαδόπουλος',
  'first_name': 'Γιώργος',
  'owner_office': 3,
  'owner_office_original_text': 'Πληρ.',
  'owner_email': 'g@org.gr',
  'owner_phones': '210 1; 690 2\n211 3,,',
  'office_name': 'Τμήμα Πληροφορικής',
  'organization': 1,
  'organization_name': 'Νοσοκομείο',
  'department': 5,
  'department_name': 'Διοικητική',
  'responsible': 7,
  'responsible_original_text': 'Παπ.',
  'office_email': 'it@org.gr',
  'office_phones': '210 9',
  'building': 'Κτίριο Α',
  'level': '2,5',
};

/// Κωδικός ίσος με το «Συνδεδεμένο σε», ποσό με τελεία δεκαδικών, ημερομηνία
/// που δεν διαβάζεται, ιδιοκτήτης και τμήμα μόνο από τα αρχικά κείμενα.
const _fallbackRow = <String, Object?>{
  'code': '2002',
  'serial_no': 'SN-OLD',
  'set_master': 2002,
  'receiving_date': '15/03/2021',
  'cost': 123.45,
  'model_original_text': 'Μοντέλο χωρίς κωδικό',
  'contract_original_text': 'Παλιά σύμβαση',
  'owner': 12,
  'owner_original_text': 'Κάτοχος από κείμενο',
  'office': 4,
  'office_original_text': 'Γραφείο από κείμενο',
  'level': 'ισόγειο',
};
