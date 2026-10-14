import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/old_database/old_equipment_repository.dart'
    show lampAcceptedNoteKey;

// Η «μετάφραση» μιας γραμμής της Λάμπας σε ενότητες καρτών: ποια πεδία
// εμφανίζονται, με ποια ετικέτα και μορφή, και ποια επεξεργάζονται. Καθαρά
// δεδομένα — η κάρτα και ο διάλογος επεξεργασίας μόνο τα εμφανίζουν.

typedef SaveEquipmentSection =
    Future<EquipmentSectionSaveResult> Function({
      required int id,
      required InfoSectionType sectionType,
      required Map<String, Object?> updatedFields,
    });
typedef TransferSectionRequest =
    Future<void> Function({
      required InfoSectionType sectionType,
      required Map<String, Object?> sourceRow,
    });

class EquipmentSectionSaveResult {
  const EquipmentSectionSaveResult({required this.success, this.message});

  final bool success;
  final String? message;
}

enum InfoSectionType { equipment, model, network, contract, owner, department }

extension InfoSectionTypeSpec on InfoSectionType {
  String get title => switch (this) {
    InfoSectionType.equipment => 'ΕΞΟΠΛΙΣΜΟΣ',
    InfoSectionType.model => 'ΜΟΝΤΕΛΟ',
    InfoSectionType.network => 'ΔΙΚΤΥΟ',
    InfoSectionType.contract => 'ΣΥΜΒΑΣΗ',
    InfoSectionType.owner => 'ΙΔΙΟΚΤΗΤΗΣ',
    InfoSectionType.department => 'ΤΜΗΜΑ',
  };

  IconData get icon => switch (this) {
    InfoSectionType.equipment => Icons.print_outlined,
    InfoSectionType.model => Icons.handyman_outlined,
    InfoSectionType.network => Icons.lan_outlined,
    InfoSectionType.contract => Icons.receipt_long_outlined,
    InfoSectionType.owner => Icons.person_outline,
    InfoSectionType.department => Icons.account_balance_outlined,
  };

  Color get color => switch (this) {
    InfoSectionType.equipment => const Color(0xFF2563EB),
    InfoSectionType.model => const Color(0xFF7C3AED),
    InfoSectionType.network => const Color(0xFF0D9488),
    InfoSectionType.contract => const Color(0xFFF97316),
    InfoSectionType.owner => const Color(0xFF16A34A),
    InfoSectionType.department => const Color(0xFFDC2626),
  };
}

class EquipmentViewModel {
  const EquipmentViewModel({required this.sections, required this._sourceRow});

  factory EquipmentViewModel.fromRow(Map<String, Object?> row) {
    final sourceRow = Map<String, Object?>.from(row);
    final equipment = InfoSectionData(
      type: InfoSectionType.equipment,
      recordId: _parseIntLike(row['code']),
      editableFields: <EditableInfoField>[
        EditableInfoField(
          label: 'Κωδικός',
          fieldKey: 'code',
          value: _text(row['code']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Περιγραφή',
          fieldKey: 'description',
          value: _text(row['description']),
          maxLines: 3,
          autofocus: true,
        ),
        EditableInfoField(
          label: 'Κωδ. μοντέλου',
          fieldKey: 'model_id',
          value: _text(row['model_id']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Μοντέλο (αρχικό)',
          fieldKey: 'model_original_text',
          value: _text(row['model_original_text']),
        ),
        EditableInfoField(
          label: 'Serial No',
          fieldKey: 'serial_no',
          value: _text(row['serial_no']),
        ),
        EditableInfoField(
          label: 'Αρ. Παγίου',
          fieldKey: 'asset_no',
          value: _text(row['asset_no']),
        ),
        EditableInfoField(
          label: 'Κωδ. κατάστασης',
          fieldKey: 'state_id',
          value: _text(row['state_id']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Κατάσταση',
          fieldKey: 'state_name',
          value: _text(row['state_name']),
        ),
        EditableInfoField(
          label: 'Κατάσταση (αρχική)',
          fieldKey: 'state_original_text',
          value: _text(row['state_original_text']),
        ),
        EditableInfoField(
          label: 'Συνδεδεμένο σε',
          fieldKey: 'set_master',
          value: _text(row['set_master']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Σύνδεση (αρχική)',
          fieldKey: 'set_master_original_text',
          value: _text(row['set_master_original_text']),
        ),
        EditableInfoField(
          label: 'Κωδ. σύμβασης',
          fieldKey: 'contract_id',
          value: _text(row['contract_id']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Σύμβαση (αρχική)',
          fieldKey: 'contract_original_text',
          value: _text(row['contract_original_text']),
        ),
        EditableInfoField(
          label: 'Συντήρηση',
          fieldKey: 'maintenance_contract',
          value: _text(row['maintenance_contract']),
        ),
        EditableInfoField(
          label: 'Παραλαβή',
          fieldKey: 'receiving_date',
          value: _text(row['receiving_date']),
          type: EditableFieldType.date,
        ),
        EditableInfoField(
          label: 'Εγγύηση',
          fieldKey: 'end_of_guarantee_date',
          value: _text(row['end_of_guarantee_date']),
          type: EditableFieldType.date,
        ),
        EditableInfoField(
          label: 'Κόστος',
          fieldKey: 'cost',
          value: _text(row['cost']),
        ),
        EditableInfoField(
          label: 'Κωδ. κατόχου',
          fieldKey: 'owner_id',
          value: _text(row['owner_id']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Κάτοχος (αρχικός)',
          fieldKey: 'owner_original_text',
          value: _text(row['owner_original_text']),
        ),
        EditableInfoField(
          label: 'Κωδ. γραφείου',
          fieldKey: 'office_id',
          value: _text(row['office_id']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Γραφείο (αρχικό)',
          fieldKey: 'office_original_text',
          value: _text(row['office_original_text']),
        ),
        EditableInfoField(
          label: 'Χαρακτ. εξοπλ.',
          fieldKey: 'equipment_attributes',
          value: _text(row['equipment_attributes']),
          maxLines: 3,
        ),
        EditableInfoField(
          label: 'Σχόλια',
          fieldKey: 'equipment_comments',
          value: _text(row['equipment_comments']),
          maxLines: 3,
        ),
      ],
      items: _items(<InfoItem>[
        InfoItem(label: 'Κωδικός', value: _text(row['code'])),
        InfoItem(
          label: 'Περιγραφή',
          value: _text(row['description']),
          maxLines: 3,
        ),
        InfoItem(label: 'Serial No', value: _text(row['serial_no'])),
        InfoItem(label: 'Αρ. Παγίου', value: _text(row['asset_no'])),
        InfoItem(label: 'Κατάσταση', value: _text(row['state_name'])),
        if (!_codeEqualsConnectedTo(row))
          InfoItem(label: 'Συνδεδεμένο σε', value: _setMasterText(row)),
        InfoItem(label: 'Παραλαβή', value: _formatDate(row['receiving_date'])),
        InfoItem(
          label: 'Εγγύηση',
          value: _formatDate(row['end_of_guarantee_date']),
        ),
        InfoItem(label: 'Κόστος', value: _formatMoney(row['cost'])),
        InfoItem(
          label: 'Σχόλια',
          value: _text(row['equipment_comments']),
          maxLines: 3,
        ),
      ]),
    );

    final model = InfoSectionData(
      type: InfoSectionType.model,
      recordId: _parseIntLike(row['model_id']),
      editableFields: <EditableInfoField>[
        EditableInfoField(
          label: 'Κωδ. μοντέλου',
          fieldKey: 'model_id',
          value: _text(row['model_id']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Μοντέλο',
          fieldKey: 'model_name',
          value: _text(row['model_name']),
          autofocus: true,
        ),
        EditableInfoField(
          label: 'Κωδ. κατηγορίας',
          fieldKey: 'category_code',
          value: _text(row['category_code']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Κατηγ. (αρχική)',
          fieldKey: 'category_code_original_text',
          value: _text(row['category_code_original_text']),
        ),
        EditableInfoField(
          label: 'Κατηγορία',
          fieldKey: 'category_name',
          value: _text(row['category_name']),
        ),
        EditableInfoField(
          label: 'Κωδ. υποκατηγ.',
          fieldKey: 'subcategory_code',
          value: _text(row['subcategory_code']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Υποκατ. (αρχική)',
          fieldKey: 'subcategory_code_original_text',
          value: _text(row['subcategory_code_original_text']),
        ),
        EditableInfoField(
          label: 'Υποκατηγ.',
          fieldKey: 'subcategory_name',
          value: _text(row['subcategory_name']),
        ),
        EditableInfoField(
          label: 'Κωδ. κατασκ.',
          fieldKey: 'manufacturer',
          value: _text(row['manufacturer']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Κατασκ. (αρχικός)',
          fieldKey: 'manufacturer_original_text',
          value: _text(row['manufacturer_original_text']),
        ),
        EditableInfoField(
          label: 'Κατασκευ.',
          fieldKey: 'manufacturer_name',
          value: _text(row['manufacturer_name']),
        ),
        EditableInfoField(
          label: 'Κωδικός κατασκ.',
          fieldKey: 'manufacturer_code',
          value: _text(row['manufacturer_code']),
        ),
        EditableInfoField(
          label: 'Χαρακτ.',
          fieldKey: 'model_attributes',
          value: _text(row['model_attributes']),
          maxLines: 3,
        ),
        EditableInfoField(
          label: 'Αναλώσιμα',
          fieldKey: 'consumables',
          value: _text(row['consumables']),
          maxLines: 2,
        ),
        EditableInfoField(
          label: 'Δικτύωση',
          fieldKey: 'network_connectivity',
          value: _text(row['network_connectivity']),
          type: EditableFieldType.code,
        ),
      ],
      items: _items(<InfoItem>[
        InfoItem(
          label: 'Μοντέλο',
          value: _firstText(row['model_name'], row['model_original_text']),
        ),
        InfoItem(label: 'Κατηγορία', value: _text(row['category_name'])),
        InfoItem(label: 'Υποκατηγ.', value: _text(row['subcategory_name'])),
        InfoItem(label: 'Κατασκευ.', value: _text(row['manufacturer_name'])),
        InfoItem(
          label: 'Χαρακτ.',
          value: _firstText(
            row['model_attributes'],
            row['equipment_attributes'],
          ),
          maxLines: 3,
        ),
        InfoItem(
          label: 'Αναλώσιμα',
          value: _text(row['consumables']),
          maxLines: 2,
        ),
      ]),
    );

    // Δίκτυο: εμπλουτισμός από την παλιά βάση δικτύου — αποθηκεύεται στον
    // πίνακα equipment, γι' αυτό recordId = code. Χωρίς κουμπί μεταφοράς
    // στη νέα βάση (μόνο ανάγνωση/επεξεργασία).
    final network = InfoSectionData(
      type: InfoSectionType.network,
      recordId: _parseIntLike(row['code']),
      editableFields: <EditableInfoField>[
        EditableInfoField(
          label: 'Κόμβος',
          fieldKey: 'network_node',
          value: _text(row['network_node']),
        ),
        EditableInfoField(
          label: 'IP',
          fieldKey: 'ip_address',
          value: _text(row['ip_address']),
          autofocus: true,
          note: _acceptedNote(row, 'ip_address'),
        ),
        EditableInfoField(
          label: 'VLAN',
          fieldKey: 'network_vlan',
          value: _text(row['network_vlan']),
        ),
        EditableInfoField(
          label: 'MAC',
          fieldKey: 'network_mac',
          value: _text(row['network_mac']),
        ),
        EditableInfoField(
          label: 'Hostname',
          fieldKey: 'network_name',
          value: _text(row['network_name']),
          note: _acceptedNote(row, 'network_name'),
        ),
        EditableInfoField(
          label: 'Περιγραφή',
          fieldKey: 'network_description',
          value: _text(row['network_description']),
          maxLines: 2,
        ),
        EditableInfoField(
          label: 'Σχόλια',
          fieldKey: 'network_comments',
          value: _text(row['network_comments']),
          maxLines: 3,
        ),
      ],
      items: _items(<InfoItem>[
        InfoItem(label: 'Κόμβος', value: _text(row['network_node'])),
        InfoItem(
          label: 'IP',
          value: _text(row['ip_address']),
          note: _acceptedNote(row, 'ip_address'),
        ),
        InfoItem(label: 'VLAN', value: _text(row['network_vlan'])),
        InfoItem(label: 'MAC', value: _text(row['network_mac'])),
        InfoItem(
          label: 'Hostname',
          value: _text(row['network_name']),
          note: _acceptedNote(row, 'network_name'),
        ),
        InfoItem(
          label: 'Περιγραφή',
          value: _text(row['network_description']),
          maxLines: 2,
        ),
        InfoItem(
          label: 'Σχόλια',
          value: _text(row['network_comments']),
          maxLines: 3,
        ),
      ]),
    );

    final contract = InfoSectionData(
      type: InfoSectionType.contract,
      recordId: _parseIntLike(row['contract_id']),
      editableFields: <EditableInfoField>[
        EditableInfoField(
          label: 'Κωδ. σύμβασης',
          fieldKey: 'contract_id',
          value: _text(row['contract_id']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Σύμβαση',
          fieldKey: 'contract_name',
          value: _text(row['contract_name']),
          autofocus: true,
        ),
        EditableInfoField(
          label: 'Κωδ. κατηγορίας',
          fieldKey: 'contract_category',
          value: _text(row['contract_category']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Κατηγ. (αρχική)',
          fieldKey: 'contract_category_original_text',
          value: _text(row['contract_category_original_text']),
        ),
        EditableInfoField(
          label: 'Κατηγορία',
          fieldKey: 'contract_category_name',
          value: _text(row['contract_category_name']),
        ),
        EditableInfoField(
          label: 'Κωδ. προμηθ.',
          fieldKey: 'supplier_id',
          value: _text(row['supplier_id']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Προμηθ. (αρχικός)',
          fieldKey: 'supplier_original_text',
          value: _text(row['supplier_original_text']),
        ),
        EditableInfoField(
          label: 'Προμηθ.',
          fieldKey: 'supplier_name',
          value: _text(row['supplier_name']),
        ),
        EditableInfoField(
          label: 'Έναρξη',
          fieldKey: 'contract_start_date',
          value: _text(row['contract_start_date']),
          type: EditableFieldType.date,
        ),
        EditableInfoField(
          label: 'Λήξη',
          fieldKey: 'contract_end_date',
          value: _text(row['contract_end_date']),
          type: EditableFieldType.date,
        ),
        EditableInfoField(
          label: 'Διακήρυξη',
          fieldKey: 'contract_declaration',
          value: _text(row['contract_declaration']),
        ),
        EditableInfoField(
          label: 'Ανάθεση',
          fieldKey: 'contract_award',
          value: _text(row['contract_award']),
        ),
        EditableInfoField(
          label: 'Κόστος',
          fieldKey: 'contract_cost',
          value: _text(row['contract_cost']),
        ),
        EditableInfoField(
          label: 'Επιτροπή',
          fieldKey: 'contract_committee',
          value: _text(row['contract_committee']),
        ),
        EditableInfoField(
          label: 'Σχόλια',
          fieldKey: 'contract_comments',
          value: _text(row['contract_comments']),
          maxLines: 3,
        ),
      ],
      items: _items(<InfoItem>[
        InfoItem(
          label: 'Σύμβαση',
          value: _firstText(
            row['contract_name'],
            row['contract_original_text'],
          ),
        ),
        InfoItem(
          label: 'Κατηγορία',
          value: _text(row['contract_category_name']),
        ),
        InfoItem(label: 'Προμηθ.', value: _text(row['supplier_name'])),
        InfoItem(label: 'Ανάθεση', value: _text(row['contract_award'])),
        InfoItem(label: 'Διακήρυξη', value: _text(row['contract_declaration'])),
        InfoItem(label: 'Συντήρηση', value: _text(row['maintenance_contract'])),
        InfoItem(
          label: 'Σχόλια',
          value: _text(row['contract_comments']),
          maxLines: 3,
        ),
      ]),
    );

    final owner = InfoSectionData(
      type: InfoSectionType.owner,
      recordId: _parseIntLike(row['owner_id'] ?? row['owner']),
      editableFields: <EditableInfoField>[
        EditableInfoField(
          label: 'Κωδ. κατόχου',
          fieldKey: 'owner_id',
          value: _text(row['owner_id'] ?? row['owner']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Επώνυμο',
          fieldKey: 'last_name',
          value: _text(row['last_name']),
          autofocus: true,
        ),
        EditableInfoField(
          label: 'Όνομα',
          fieldKey: 'first_name',
          value: _text(row['first_name']),
        ),
        EditableInfoField(
          label: 'Κωδ. γραφείου',
          fieldKey: 'owner_office',
          value: _text(row['owner_office']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Γραφείο (αρχικό)',
          fieldKey: 'owner_office_original_text',
          value: _text(row['owner_office_original_text']),
        ),
        EditableInfoField(
          label: 'Email',
          fieldKey: 'owner_email',
          value: _text(row['owner_email']),
          type: EditableFieldType.email,
        ),
        EditableInfoField(
          label: 'Τηλέφωνα',
          fieldKey: 'owner_phones',
          value: _text(row['owner_phones']),
          type: EditableFieldType.phone,
          maxLines: 2,
        ),
      ],
      items: _items(<InfoItem>[
        InfoItem(
          label: 'Όνομα',
          value:
              _joinName(row['last_name'], row['first_name']) ??
              _text(row['owner_original_text']),
          maxLines: 2,
        ),
        InfoItem(label: 'Email', value: _text(row['owner_email'])),
        InfoItem(
          label: 'Τηλέφωνα',
          value: _joinList(row['owner_phones']),
          maxLines: 2,
        ),
      ]),
    );

    final department = InfoSectionData(
      type: InfoSectionType.department,
      recordId: _parseIntLike(row['office_id'] ?? row['office']),
      editableFields: <EditableInfoField>[
        EditableInfoField(
          label: 'Κωδ. γραφείου',
          fieldKey: 'office_id',
          value: _text(row['office_id'] ?? row['office']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Τμήμα',
          fieldKey: 'office_name',
          value: _text(row['office_name']),
          autofocus: true,
        ),
        EditableInfoField(
          label: 'Κωδ. οργανισμού',
          fieldKey: 'organization',
          value: _text(row['organization']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Οργανισμός',
          fieldKey: 'organization_name',
          value: _text(row['organization_name']),
        ),
        EditableInfoField(
          label: 'Κωδ. υπηρεσίας',
          fieldKey: 'department',
          value: _text(row['department']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Υπηρεσία',
          fieldKey: 'department_name',
          value: _text(row['department_name']),
        ),
        EditableInfoField(
          label: 'Υπεύθυνος',
          fieldKey: 'responsible',
          value: _text(row['responsible']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(
          label: 'Υπεύθ. (αρχικός)',
          fieldKey: 'responsible_original_text',
          value: _text(row['responsible_original_text']),
        ),
        EditableInfoField(
          label: 'Email',
          fieldKey: 'office_email',
          value: _text(row['office_email']),
          type: EditableFieldType.email,
        ),
        EditableInfoField(
          label: 'Τηλέφωνα',
          fieldKey: 'office_phones',
          value: _text(row['office_phones']),
          type: EditableFieldType.phone,
          maxLines: 2,
        ),
        EditableInfoField(
          label: 'Κτίριο',
          fieldKey: 'building',
          value: _text(row['building']),
        ),
        EditableInfoField(
          label: 'Όροφος',
          fieldKey: 'level',
          value: _text(row['level']),
          type: EditableFieldType.number,
        ),
      ],
      items: _items(<InfoItem>[
        InfoItem(
          label: 'Τμήμα',
          value: _firstText(
            row['office_name'],
            row['department_name'],
            row['office_original_text'],
          ),
          maxLines: 2,
        ),
        InfoItem(label: 'Οργανισμός', value: _text(row['organization_name'])),
        InfoItem(label: 'Email', value: _text(row['office_email'])),
        InfoItem(
          label: 'Τηλέφωνα',
          value: _joinList(row['office_phones']),
          maxLines: 2,
        ),
        InfoItem(label: 'Κτίριο', value: _text(row['building'])),
        InfoItem(label: 'Όροφος', value: _formatNumber(row['level'])),
      ]),
    );

    // Σειρά καρτών: Εξοπλισμός, Μοντέλο, Δίκτυο, Ιδιοκτήτης, Τμήμα, Σύμβαση.
    return EquipmentViewModel(
      sourceRow: sourceRow,
      sections: <InfoSectionData>[
        equipment,
        model,
        network,
        owner,
        department,
        contract,
      ].where((section) => section.items.isNotEmpty).toList(growable: false),
    );
  }

  final List<InfoSectionData> sections;
  final Map<String, Object?> _sourceRow;
  Map<String, Object?> get sourceRow => Map<String, Object?>.from(_sourceRow);

  EquipmentViewModel copyWithUpdatedFields(Map<String, Object?> updatedFields) {
    return EquipmentViewModel.fromRow(<String, Object?>{
      ..._sourceRow,
      ...updatedFields,
    });
  }

  static List<InfoItem> _items(List<InfoItem> items) {
    return items.where((item) => item.value != null).toList(growable: false);
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// «✓ Αποδεκτό: …» όταν η τιμή της στήλης έχει κριθεί αποδεκτή στον έλεγχο
  /// προβλημάτων — η Λάμπα δεν διορθώνεται, άρα η εξήγηση συνοδεύει την τιμή.
  static String? _acceptedNote(Map<String, Object?> row, String column) {
    final note = _text(row[lampAcceptedNoteKey(column)]);
    return note == null ? null : '✓ Αποδεκτό: $note';
  }

  static String? _firstText(Object? first, [Object? second, Object? third]) {
    return _text(first) ?? _text(second) ?? _text(third);
  }

  static String? _joinName(Object? lastName, Object? firstName) {
    final parts = <String>[
      if (_text(lastName) != null) _text(lastName)!,
      if (_text(firstName) != null) _text(firstName)!,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  static String? _joinList(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    return text
        .split(RegExp(r'[,;\n]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' · ');
  }

  static String? _setMasterText(Map<String, Object?> row) {
    return _text(row['set_master']) ?? _text(row['set_master_original_text']);
  }

  /// Απόκρυψη «Συνδεδεμένο σε» όταν ο εξοπλισμός δείχνει στον ίδιο τον εαυτό του.
  static bool _codeEqualsConnectedTo(Map<String, Object?> row) {
    final connected = _setMasterText(row);
    if (connected == null) return false;

    final codeRaw = row['code'];
    final masterRaw = row['set_master'];
    if (codeRaw != null && masterRaw != null) {
      final codeNum = _parseIntLike(codeRaw);
      final masterNum = _parseIntLike(masterRaw);
      if (codeNum != null && masterNum != null && codeNum == masterNum) {
        return true;
      }
    }

    final codeDisplay = _text(codeRaw);
    return codeDisplay != null && codeDisplay == connected;
  }

  static int? _parseIntLike(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static String? _formatDate(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    return DateFormat.yMd('el').format(parsed);
  }

  static String? _formatNumber(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    final number = num.tryParse(text.replaceAll(',', '.'));
    if (number == null) return text;
    return NumberFormat.decimalPattern('el').format(number);
  }

  static String? _formatMoney(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    final number = parseLampMoney(text);
    if (number == null) return text;
    return NumberFormat.currency(locale: 'el', symbol: '€').format(number);
  }

  /// Διαβάζει ποσό με τη γραφή που έχει πραγματικά αποθηκευτεί.
  ///
  /// Η Λάμπα γράφει τα κόστη με τελεία υποδιαστολή («1537.5000»)· όσα
  /// διορθώνονται με το χέρι μπορεί να γραφτούν ελληνικά («1.537,50»). Με
  /// κόμμα η γραφή είναι ελληνική· χωρίς κόμμα, μία τελεία είναι υποδιαστολή
  /// και πολλές τελείες είναι χιλιάδες.
  @visibleForTesting
  static num? parseLampMoney(String text) {
    var t = text.replaceAll('€', '').replaceAll(' ', '').trim();
    if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if ('.'.allMatches(t).length > 1) {
      t = t.replaceAll('.', '');
    }
    return num.tryParse(t);
  }
}

class InfoSectionData {
  const InfoSectionData({
    required this.type,
    required this.items,
    this.recordId,
    this.editableFields = const <EditableInfoField>[],
  });

  final InfoSectionType type;
  final List<InfoItem> items;
  final int? recordId;
  final List<EditableInfoField> editableFields;

  bool get canEdit => recordId != null && editableFields.isNotEmpty;
}

class InfoItem {
  const InfoItem({
    required this.label,
    required this.value,
    this.maxLines = 1,
    this.note,
  });

  final String label;
  final String? value;
  final int maxLines;

  /// Επεξηγηματική γραμμή κάτω από την τιμή — μόνο για ανάγνωση.
  final String? note;
}

enum EditableFieldType { text, email, date, number, phone, code }

class EditableInfoField {
  const EditableInfoField({
    required this.label,
    required this.fieldKey,
    this.value,
    this.type = EditableFieldType.text,
    this.maxLines = 1,
    this.autofocus = false,
    this.note,
  });

  final String label;
  final String fieldKey;
  final String? value;
  final EditableFieldType type;
  final int maxLines;
  final bool autofocus;

  /// Επεξηγηματική γραμμή κάτω από το πεδίο — μόνο για ανάγνωση.
  final String? note;
}
