import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

const _kCardPadding = EdgeInsets.all(18);
const _kSectionSpacing = 16.0;
const _kRowSpacing = 7.0;
const _kLabelWidth = 92.0;
const _kDesktopBreakpoint = 1200.0;
const _kTabletBreakpoint = 800.0;
const _kFallbackMinWidth = 360.0;

typedef SaveEquipmentSection = Future<EquipmentSectionSaveResult> Function({
  required int id,
  required InfoSectionType sectionType,
  required Map<String, Object?> updatedFields,
});

class EquipmentSectionSaveResult {
  const EquipmentSectionSaveResult({
    required this.success,
    this.message,
  });

  final bool success;
  final String? message;
}

enum InfoSectionType {
  equipment,
  model,
  contract,
  owner,
  department,
}

extension InfoSectionTypeSpec on InfoSectionType {
  String get title => switch (this) {
    InfoSectionType.equipment => 'ΕΞΟΠΛΙΣΜΟΣ',
    InfoSectionType.model => 'ΜΟΝΤΕΛΟ',
    InfoSectionType.contract => 'ΣΥΜΒΑΣΗ',
    InfoSectionType.owner => 'ΙΔΙΟΚΤΗΤΗΣ',
    InfoSectionType.department => 'ΤΜΗΜΑ',
  };

  IconData get icon => switch (this) {
    InfoSectionType.equipment => Icons.print_outlined,
    InfoSectionType.model => Icons.handyman_outlined,
    InfoSectionType.contract => Icons.receipt_long_outlined,
    InfoSectionType.owner => Icons.person_outline,
    InfoSectionType.department => Icons.account_balance_outlined,
  };

  Color get color => switch (this) {
    InfoSectionType.equipment => const Color(0xFF2563EB),
    InfoSectionType.model => const Color(0xFF7C3AED),
    InfoSectionType.contract => const Color(0xFFF97316),
    InfoSectionType.owner => const Color(0xFF16A34A),
    InfoSectionType.department => const Color(0xFFDC2626),
  };
}

class EquipmentViewModel {
  const EquipmentViewModel({
    required this.sections,
    required Map<String, Object?> sourceRow,
  }) : _sourceRow = sourceRow;

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
        EditableInfoField(label: 'Κωδ. μοντέλου', fieldKey: 'model_id', value: _text(row['model_id']), type: EditableFieldType.code),
        EditableInfoField(label: 'Μοντέλο (αρχικό)', fieldKey: 'model_original_text', value: _text(row['model_original_text'])),
        EditableInfoField(label: 'Serial No', fieldKey: 'serial_no', value: _text(row['serial_no'])),
        EditableInfoField(label: 'Αρ. Παγίου', fieldKey: 'asset_no', value: _text(row['asset_no'])),
        EditableInfoField(label: 'Κωδ. κατάστασης', fieldKey: 'state_id', value: _text(row['state_id']), type: EditableFieldType.code),
        EditableInfoField(label: 'Κατάσταση', fieldKey: 'state_name', value: _text(row['state_name'])),
        EditableInfoField(label: 'Κατάσταση (αρχική)', fieldKey: 'state_original_text', value: _text(row['state_original_text'])),
        EditableInfoField(
          label: 'Συνδεδεμένο σε',
          fieldKey: 'set_master',
          value: _text(row['set_master']),
          type: EditableFieldType.code,
        ),
        EditableInfoField(label: 'Σύνδεση (αρχική)', fieldKey: 'set_master_original_text', value: _text(row['set_master_original_text'])),
        EditableInfoField(label: 'Κωδ. σύμβασης', fieldKey: 'contract_id', value: _text(row['contract_id']), type: EditableFieldType.code),
        EditableInfoField(label: 'Σύμβαση (αρχική)', fieldKey: 'contract_original_text', value: _text(row['contract_original_text'])),
        EditableInfoField(label: 'Συντήρηση', fieldKey: 'maintenance_contract', value: _text(row['maintenance_contract'])),
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
        EditableInfoField(label: 'Κόστος', fieldKey: 'cost', value: _text(row['cost'])),
        EditableInfoField(label: 'Κωδ. κατόχου', fieldKey: 'owner_id', value: _text(row['owner_id']), type: EditableFieldType.code),
        EditableInfoField(label: 'Κάτοχος (αρχικός)', fieldKey: 'owner_original_text', value: _text(row['owner_original_text'])),
        EditableInfoField(label: 'Κωδ. γραφείου', fieldKey: 'office_id', value: _text(row['office_id']), type: EditableFieldType.code),
        EditableInfoField(label: 'Γραφείο (αρχικό)', fieldKey: 'office_original_text', value: _text(row['office_original_text'])),
        EditableInfoField(label: 'Χαρακτ. εξοπλ.', fieldKey: 'equipment_attributes', value: _text(row['equipment_attributes']), maxLines: 3),
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
        InfoItem(
          label: 'Παραλαβή',
          value: _formatDate(row['receiving_date']),
        ),
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
        EditableInfoField(label: 'Κωδ. μοντέλου', fieldKey: 'model_id', value: _text(row['model_id']), type: EditableFieldType.code),
        EditableInfoField(label: 'Μοντέλο', fieldKey: 'model_name', value: _text(row['model_name']), autofocus: true),
        EditableInfoField(label: 'Κωδ. κατηγορίας', fieldKey: 'category_code', value: _text(row['category_code']), type: EditableFieldType.code),
        EditableInfoField(label: 'Κατηγ. (αρχική)', fieldKey: 'category_code_original_text', value: _text(row['category_code_original_text'])),
        EditableInfoField(label: 'Κατηγορία', fieldKey: 'category_name', value: _text(row['category_name'])),
        EditableInfoField(label: 'Κωδ. υποκατηγ.', fieldKey: 'subcategory_code', value: _text(row['subcategory_code']), type: EditableFieldType.code),
        EditableInfoField(label: 'Υποκατ. (αρχική)', fieldKey: 'subcategory_code_original_text', value: _text(row['subcategory_code_original_text'])),
        EditableInfoField(label: 'Υποκατηγ.', fieldKey: 'subcategory_name', value: _text(row['subcategory_name'])),
        EditableInfoField(label: 'Κωδ. κατασκ.', fieldKey: 'manufacturer', value: _text(row['manufacturer']), type: EditableFieldType.code),
        EditableInfoField(label: 'Κατασκ. (αρχικός)', fieldKey: 'manufacturer_original_text', value: _text(row['manufacturer_original_text'])),
        EditableInfoField(label: 'Κατασκευ.', fieldKey: 'manufacturer_name', value: _text(row['manufacturer_name'])),
        EditableInfoField(label: 'Κωδικός κατασκ.', fieldKey: 'manufacturer_code', value: _text(row['manufacturer_code'])),
        EditableInfoField(label: 'Χαρακτ.', fieldKey: 'model_attributes', value: _text(row['model_attributes']), maxLines: 3),
        EditableInfoField(label: 'Αναλώσιμα', fieldKey: 'consumables', value: _text(row['consumables']), maxLines: 2),
        EditableInfoField(label: 'Δικτύωση', fieldKey: 'network_connectivity', value: _text(row['network_connectivity']), type: EditableFieldType.code),
      ],
      items: _items(<InfoItem>[
        InfoItem(
          label: 'Μοντέλο',
          value: _firstText(row['model_name'], row['model_original_text']),
        ),
        InfoItem(label: 'Κατηγορία', value: _text(row['category_name'])),
        InfoItem(
          label: 'Υποκατηγ.',
          value: _text(row['subcategory_name']),
        ),
        InfoItem(label: 'Κατασκευ.', value: _text(row['manufacturer_name'])),
        InfoItem(
          label: 'Χαρακτ.',
          value: _firstText(row['model_attributes'], row['equipment_attributes']),
          maxLines: 3,
        ),
        InfoItem(
          label: 'Αναλώσιμα',
          value: _text(row['consumables']),
          maxLines: 2,
        ),
      ]),
    );

    final contract = InfoSectionData(
      type: InfoSectionType.contract,
      recordId: _parseIntLike(row['contract_id']),
      editableFields: <EditableInfoField>[
        EditableInfoField(label: 'Κωδ. σύμβασης', fieldKey: 'contract_id', value: _text(row['contract_id']), type: EditableFieldType.code),
        EditableInfoField(label: 'Σύμβαση', fieldKey: 'contract_name', value: _text(row['contract_name']), autofocus: true),
        EditableInfoField(label: 'Κωδ. κατηγορίας', fieldKey: 'contract_category', value: _text(row['contract_category']), type: EditableFieldType.code),
        EditableInfoField(label: 'Κατηγ. (αρχική)', fieldKey: 'contract_category_original_text', value: _text(row['contract_category_original_text'])),
        EditableInfoField(label: 'Κατηγορία', fieldKey: 'contract_category_name', value: _text(row['contract_category_name'])),
        EditableInfoField(label: 'Κωδ. προμηθ.', fieldKey: 'supplier_id', value: _text(row['supplier_id']), type: EditableFieldType.code),
        EditableInfoField(label: 'Προμηθ. (αρχικός)', fieldKey: 'supplier_original_text', value: _text(row['supplier_original_text'])),
        EditableInfoField(label: 'Προμηθ.', fieldKey: 'supplier_name', value: _text(row['supplier_name'])),
        EditableInfoField(label: 'Έναρξη', fieldKey: 'contract_start_date', value: _text(row['contract_start_date']), type: EditableFieldType.date),
        EditableInfoField(label: 'Λήξη', fieldKey: 'contract_end_date', value: _text(row['contract_end_date']), type: EditableFieldType.date),
        EditableInfoField(label: 'Διακήρυξη', fieldKey: 'contract_declaration', value: _text(row['contract_declaration'])),
        EditableInfoField(label: 'Ανάθεση', fieldKey: 'contract_award', value: _text(row['contract_award'])),
        EditableInfoField(label: 'Κόστος', fieldKey: 'contract_cost', value: _text(row['contract_cost'])),
        EditableInfoField(label: 'Επιτροπή', fieldKey: 'contract_committee', value: _text(row['contract_committee'])),
        EditableInfoField(label: 'Σχόλια', fieldKey: 'contract_comments', value: _text(row['contract_comments']), maxLines: 3),
      ],
      items: _items(<InfoItem>[
        InfoItem(
          label: 'Σύμβαση',
          value: _firstText(row['contract_name'], row['contract_original_text']),
        ),
        InfoItem(label: 'Κατηγορία', value: _text(row['contract_category_name'])),
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
        EditableInfoField(label: 'Κωδ. κατόχου', fieldKey: 'owner_id', value: _text(row['owner_id'] ?? row['owner']), type: EditableFieldType.code),
        EditableInfoField(label: 'Επώνυμο', fieldKey: 'last_name', value: _text(row['last_name']), autofocus: true),
        EditableInfoField(label: 'Όνομα', fieldKey: 'first_name', value: _text(row['first_name'])),
        EditableInfoField(label: 'Κωδ. γραφείου', fieldKey: 'owner_office', value: _text(row['owner_office']), type: EditableFieldType.code),
        EditableInfoField(label: 'Γραφείο (αρχικό)', fieldKey: 'owner_office_original_text', value: _text(row['owner_office_original_text'])),
        EditableInfoField(label: 'Email', fieldKey: 'owner_email', value: _text(row['owner_email']), type: EditableFieldType.email),
        EditableInfoField(label: 'Τηλέφωνα', fieldKey: 'owner_phones', value: _text(row['owner_phones']), type: EditableFieldType.phone, maxLines: 2),
      ],
      items: _items(<InfoItem>[
        InfoItem(
          label: 'Όνομα',
          value: _joinName(row['last_name'], row['first_name']) ??
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
        EditableInfoField(label: 'Κωδ. γραφείου', fieldKey: 'office_id', value: _text(row['office_id'] ?? row['office']), type: EditableFieldType.code),
        EditableInfoField(label: 'Τμήμα', fieldKey: 'office_name', value: _text(row['office_name']), autofocus: true),
        EditableInfoField(label: 'Κωδ. οργανισμού', fieldKey: 'organization', value: _text(row['organization']), type: EditableFieldType.code),
        EditableInfoField(label: 'Οργανισμός', fieldKey: 'organization_name', value: _text(row['organization_name'])),
        EditableInfoField(label: 'Κωδ. υπηρεσίας', fieldKey: 'department', value: _text(row['department']), type: EditableFieldType.code),
        EditableInfoField(label: 'Υπηρεσία', fieldKey: 'department_name', value: _text(row['department_name'])),
        EditableInfoField(label: 'Υπεύθυνος', fieldKey: 'responsible', value: _text(row['responsible']), type: EditableFieldType.code),
        EditableInfoField(label: 'Υπεύθ. (αρχικός)', fieldKey: 'responsible_original_text', value: _text(row['responsible_original_text'])),
        EditableInfoField(label: 'Email', fieldKey: 'office_email', value: _text(row['office_email']), type: EditableFieldType.email),
        EditableInfoField(label: 'Τηλέφωνα', fieldKey: 'office_phones', value: _text(row['office_phones']), type: EditableFieldType.phone, maxLines: 2),
        EditableInfoField(label: 'Κτίριο', fieldKey: 'building', value: _text(row['building'])),
        EditableInfoField(label: 'Όροφος', fieldKey: 'level', value: _text(row['level']), type: EditableFieldType.number),
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

    return EquipmentViewModel(
      sourceRow: sourceRow,
      sections: <InfoSectionData>[
        equipment,
        model,
        contract,
        owner,
        department,
      ].where((section) => section.items.isNotEmpty).toList(growable: false),
    );
  }

  final List<InfoSectionData> sections;
  final Map<String, Object?> _sourceRow;

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
    final normalized = text
        .replaceAll('€', '')
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .trim();
    final number = num.tryParse(normalized);
    if (number == null) return text;
    return NumberFormat.currency(locale: 'el', symbol: '€').format(number);
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
  });

  final String label;
  final String? value;
  final int maxLines;
}

enum EditableFieldType {
  text,
  email,
  date,
  number,
  phone,
  code,
}

class EditableInfoField {
  const EditableInfoField({
    required this.label,
    required this.fieldKey,
    this.value,
    this.type = EditableFieldType.text,
    this.maxLines = 1,
    this.autofocus = false,
  });

  final String label;
  final String fieldKey;
  final String? value;
  final EditableFieldType type;
  final int maxLines;
  final bool autofocus;
}

class EquipmentResultCard extends StatefulWidget {
  const EquipmentResultCard({
    super.key,
    required this.viewModel,
    this.onSaveSection,
  });

  final EquipmentViewModel viewModel;
  final SaveEquipmentSection? onSaveSection;

  @override
  State<EquipmentResultCard> createState() => _EquipmentResultCardState();
}

class _EquipmentResultCardState extends State<EquipmentResultCard> {
  bool _hovered = false;
  late EquipmentViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel;
  }

  @override
  void didUpdateWidget(covariant EquipmentResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      _viewModel = widget.viewModel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = _viewModel.sections;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: _hovered ? 3 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Padding(
          padding: _kCardPadding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              if (sections.isEmpty) {
                return Text(
                  'Δεν υπάρχουν διαθέσιμες πληροφορίες.',
                  style: theme.textTheme.bodyMedium,
                );
              }
              if (!maxWidth.isFinite || maxWidth < _kFallbackMinWidth) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: _kFallbackMinWidth),
                    child: _VerticalSections(sections: sections),
                  ),
                );
              }
              if (maxWidth >= _kDesktopBreakpoint) {
                return _DesktopSections(
                  sections: sections,
                  onEditSection: widget.onSaveSection == null ? null : _editSection,
                );
              }
              if (maxWidth >= _kTabletBreakpoint) {
                return _GridSections(
                  sections: sections,
                  columns: maxWidth >= 1000 ? 3 : 2,
                  maxWidth: maxWidth,
                  onEditSection: widget.onSaveSection == null ? null : _editSection,
                );
              }
              return _VerticalSections(
                sections: sections,
                onEditSection: widget.onSaveSection == null ? null : _editSection,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _editSection(InfoSectionData section) async {
    final save = widget.onSaveSection;
    final id = section.recordId;
    if (save == null || id == null || section.editableFields.isEmpty) return;

    final updatedFields = await showDialog<Map<String, Object?>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EditSectionDialog<InfoSectionData>(
        section: section,
        onSave: (fields) => save(
          id: id,
          sectionType: section.type,
          updatedFields: fields,
        ),
      ),
    );
    if (updatedFields == null || updatedFields.isEmpty || !mounted) return;
    setState(() {
      _viewModel = _viewModel.copyWithUpdatedFields(updatedFields);
    });
  }
}

class _DesktopSections extends StatelessWidget {
  const _DesktopSections({required this.sections, this.onEditSection});

  final List<InfoSectionData> sections;
  final ValueChanged<InfoSectionData>? onEditSection;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            Flexible(
              flex: 1,
              fit: FlexFit.tight,
              child: InfoColumnSection(
                section: sections[index],
                onEdit: onEditSection,
              ),
            ),
            if (index != sections.length - 1)
              SizedBox(
                height: double.infinity,
                child: VerticalDivider(
                  width: _kSectionSpacing,
                  thickness: 1,
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.55),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _GridSections extends StatelessWidget {
  const _GridSections({
    required this.sections,
    required this.columns,
    required this.maxWidth,
    this.onEditSection,
  });

  final List<InfoSectionData> sections;
  final int columns;
  final double maxWidth;
  final ValueChanged<InfoSectionData>? onEditSection;

  @override
  Widget build(BuildContext context) {
    final itemWidth = (maxWidth - (_kSectionSpacing * (columns - 1))) / columns;
    return Wrap(
      spacing: _kSectionSpacing,
      runSpacing: _kSectionSpacing,
      children: [
        for (final section in sections)
          SizedBox(
            width: itemWidth,
            child: InfoColumnSection(section: section, onEdit: onEditSection),
          ),
      ],
    );
  }
}

class _VerticalSections extends StatelessWidget {
  const _VerticalSections({required this.sections, this.onEditSection});

  final List<InfoSectionData> sections;
  final ValueChanged<InfoSectionData>? onEditSection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          InfoColumnSection(section: sections[index], onEdit: onEditSection),
          if (index != sections.length - 1) ...[
            const SizedBox(height: _kSectionSpacing),
            Divider(
              height: 1,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.55),
            ),
            const SizedBox(height: _kSectionSpacing),
          ],
        ],
      ],
    );
  }
}

class InfoColumnSection extends StatelessWidget {
  const InfoColumnSection({
    super.key,
    required this.section,
    this.onEdit,
  });

  final InfoSectionData section;
  final ValueChanged<InfoSectionData>? onEdit;

  @override
  Widget build(BuildContext context) {
    final color = section.type.color;
    final theme = Theme.of(context);
    final items = section.items;
    final rows = items.map((item) => _InfoItemRow(item: item)).toList();

    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: color.withValues(alpha: 0.34), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(section.type.icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  section.type.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: section.canEdit
                    ? 'Επεξεργασία ${section.type.title}'
                    : 'Δεν υπάρχουν επεξεργάσιμα πεδία',
                onPressed: section.canEdit && onEdit != null
                    ? () => onEdit!(section)
                    : null,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: 32,
            height: 2,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                rows[index],
                if (index != rows.length - 1)
                  const SizedBox(height: _kRowSpacing),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class EditSectionDialog<T> extends StatefulWidget {
  const EditSectionDialog({
    super.key,
    required this.section,
    required this.onSave,
  });

  final InfoSectionData section;
  final Future<EquipmentSectionSaveResult> Function(
    Map<String, Object?> updatedFields,
  ) onSave;

  @override
  State<EditSectionDialog<T>> createState() => _EditSectionDialogState<T>();
}

class _EditSectionDialogState<T> extends State<EditSectionDialog<T>> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  late final Map<String, Object?> originalData;
  late Map<String, Object?> currentData;
  bool _saving = false;

  bool get hasChanges => !mapEquals(originalData, currentData);

  @override
  void initState() {
    super.initState();
    originalData = {
      for (final field in widget.section.editableFields)
        field.fieldKey: field.value ?? '',
    };
    currentData = Map<String, Object?>.from(originalData);
    for (final field in widget.section.editableFields) {
      _controllers[field.fieldKey] = TextEditingController(
        text: field.value ?? '',
      )..addListener(() {
          currentData = <String, Object?>{
            ...currentData,
            field.fieldKey: _controllers[field.fieldKey]!.text,
          };
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.section.type.color;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestClose();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _requestClose();
          },
        },
        child: AlertDialog(
          title: Row(
            children: [
              Icon(widget.section.type.icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text('Επεξεργασία ${widget.section.type.title}')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final field in widget.section.editableFields) ...[
                      _EditField(
                        field: field,
                        controller: _controllers[field.fieldKey]!,
                        changed: currentData[field.fieldKey] !=
                            originalData[field.fieldKey],
                        validator: (value) => _validateField(field, value),
                        onPickDate: field.type == EditableFieldType.date
                            ? () => _pickDate(field)
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _requestClose,
              child: const Text('Άκυρο'),
            ),
            FilledButton.icon(
              onPressed: hasChanges && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Αποθήκευση'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Απόρριψη αλλαγών;'),
        content: const Text('Θέλεις να απορρίψεις αλλαγές;'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Συνέχεια επεξεργασίας'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Απόρριψη'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickDate(EditableInfoField field) async {
    final initial = _parseDate(_controllers[field.fieldKey]?.text) ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _controllers[field.fieldKey]?.text = _formatIsoDate(picked);
  }

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    setState(() => _saving = true);
    final changedFields = _changedFields();
    final result = await widget.onSave(changedFields);
    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pop(changedFields);
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? 'Η αποθήκευση απέτυχε.')),
    );
  }

  Map<String, Object?> _changedFields() {
    final changed = <String, Object?>{};
    for (final field in widget.section.editableFields) {
      final current = currentData[field.fieldKey];
      if (current == originalData[field.fieldKey]) continue;
      changed[field.fieldKey] = _normalizeForStorage(field, current);
    }
    return changed;
  }

  Object? _normalizeForStorage(EditableInfoField field, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return switch (field.type) {
      EditableFieldType.code => int.tryParse(text),
      EditableFieldType.number when field.fieldKey == 'level' =>
        int.tryParse(text),
      EditableFieldType.date => _parseDate(text) == null
          ? text
          : _formatIsoDate(_parseDate(text)!),
      _ => text,
    };
  }

  String? _validateField(EditableInfoField field, String? value) {
    final text = value?.trim() ?? '';
    if (_isPrimaryKeyField(field.fieldKey) && text.isEmpty) {
      return 'Ο κωδικός δεν μπορεί να είναι κενός.';
    }
    if (text.isEmpty) return null;
    switch (field.type) {
      case EditableFieldType.email:
        return null;
      case EditableFieldType.date:
        final date = _parseDate(text);
        if (date != null && field.fieldKey == 'end_of_guarantee_date') {
          final start = _parseDate(currentData['receiving_date']);
          if (start != null && date.isBefore(start)) {
            return 'Η λήξη δεν μπορεί να προηγείται της παραλαβής.';
          }
        }
        return null;
      case EditableFieldType.number:
        return null;
      case EditableFieldType.phone:
        return null;
      case EditableFieldType.code:
        return int.tryParse(text) == null ? 'Μη έγκυρος κωδικός.' : null;
      case EditableFieldType.text:
        return null;
    }
  }

  bool _isPrimaryKeyField(String fieldKey) {
    return fieldKey == 'code' ||
        (widget.section.type == InfoSectionType.model && fieldKey == 'model_id') ||
        (widget.section.type == InfoSectionType.contract && fieldKey == 'contract_id') ||
        (widget.section.type == InfoSectionType.owner && fieldKey == 'owner_id') ||
        (widget.section.type == InfoSectionType.department && fieldKey == 'office_id');
  }

  DateTime? _parseDate(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;
    final parts = text.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  String _formatIsoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.field,
    required this.controller,
    required this.changed,
    required this.validator,
    this.onPickDate,
  });

  final EditableInfoField field;
  final TextEditingController controller;
  final bool changed;
  final String? Function(String?) validator;
  final VoidCallback? onPickDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: changed
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextFormField(
        controller: controller,
        autofocus: field.autofocus,
        maxLines: field.maxLines,
        keyboardType: _keyboardType(field.type),
        validator: validator,
        decoration: InputDecoration(
          labelText: field.label,
          border: const OutlineInputBorder(),
          suffixIcon: onPickDate == null
              ? null
              : IconButton(
                  tooltip: 'Επιλογή ημερομηνίας',
                  icon: const Icon(Icons.calendar_today_outlined),
                  onPressed: onPickDate,
                ),
        ),
      ),
    );
  }

  TextInputType _keyboardType(EditableFieldType type) {
    return switch (type) {
      EditableFieldType.email => TextInputType.emailAddress,
      EditableFieldType.date => TextInputType.datetime,
      EditableFieldType.number => TextInputType.number,
      EditableFieldType.phone => TextInputType.phone,
      EditableFieldType.code => TextInputType.number,
      EditableFieldType.text => TextInputType.text,
    };
  }
}

class _InfoItemRow extends StatelessWidget {
  const _InfoItemRow({required this.item});

  final InfoItem item;

  @override
  Widget build(BuildContext context) {
    return CopyableField(
      label: item.label,
      value: item.value ?? '',
      maxLines: item.maxLines,
    );
  }
}

class CopyableField extends StatelessWidget {
  const CopyableField({
    super.key,
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(_kLabelWidth),
        1: FlexColumnWidth(),
        2: FixedColumnWidth(30),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SelectableText(
              value,
              maxLines: maxLines,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            IconButton(
              tooltip: 'Αντιγραφή $label',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              icon: const Icon(Icons.copy_outlined, size: 15),
              onPressed: () => _copyValue(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _copyValue(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    final content = 'Αντιγράφηκε $label: $value';
    final message = content.length > 80 ? '${content.substring(0, 77)}...' : content;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
