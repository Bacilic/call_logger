import 'dart:convert';

import '../../features/calls/utils/equipment_remote_param_key.dart';
import '../../features/database/services/database_backup_audit.dart';
import 'audit_service.dart';

/// Κοινή λογική «Τι άλλαξε» για audit UI, search_text και migrations.
abstract final class AuditDiffHelper {
  /// Πεδία που αποκλείονται από diff UI, search_text και migrations.
  static const Set<String> excludedFields = {
    'is_deleted',
    'integrity_fix',
    'via',
    'trigger',
  };

  /// Ονομαστικές ετικέτες πεδίων (σύνοψη «N αλλαγές: …»).
  static const Map<String, String> _titleLabels = {
    'name': 'όνομα',
    'email': 'email',
    'phone': 'τηλέφωνο',
    'status': 'κατάσταση',
    'priority': 'προτεραιότητα',
    'due_date': 'προθεσμία',
    'title': 'τίτλος',
    'description': 'περιγραφή',
    'solution_notes': 'λύση',
    'department_id': 'τμήμα',
    'department_text': 'τμήμα',
    'equipment_id': 'εξοπλισμός',
    'equipment_text': 'εξοπλισμός',
    'caller_id': 'χρήστης',
    'caller_text': 'χρήστης',
    'phone_text': 'τηλέφωνο',
    'category_text': 'κατηγορία',
    'category_id': 'κατηγορία',
    'issue': 'θέμα',
    'solution': 'λύση',
    'type': 'τύπος',
    'remote_params': 'Παράμετροι απομακρυσμένης',
    'linked_users': 'συνδεδεμένοι χρήστες',
    'linked_equipment': 'εξοπλισμός',
    'linked_phone_numbers': 'τηλέφωνα',
    'linked_user_id': 'χρήστης',
    'color': 'χρώμα',
    'building': 'κτίριο',
    'map_floor': 'όροφος',
    'floor_id': 'όροφος',
    'notes': 'σημειώσεις',
    'map_x': 'θέση',
    'map_y': 'θέση',
    'map_width': 'πλάτος',
    'map_height': 'ύψος',
    'map_rotation': 'περιστροφή',
    'map_label_offset_x': 'μετατόπιση ετικέτας',
    'map_label_offset_y': 'μετατόπιση ετικέτας',
    'map_label_font_scale': 'κλίμακα ετικέτας',
    'map_label_width': 'πλάτος ετικέτας',
    'map_label_height': 'ύψος ετικέτας',
    'map_anchor_offset_x': 'μετατόπιση άγκυρας',
    'map_anchor_offset_y': 'μετατόπιση άγκυρας',
    'map_custom_name': 'προσαρμοσμένο όνομα',
    'map_hidden': 'ορατότητα',
    'user_text': 'χρήστης',
    'duration': 'Διάρκεια',
    'is_priority': 'Προτεραιότητα',
    'date': 'Ημερομηνία',
    'time': 'Ώρα',
    'lansweeper_state': 'Κατάσταση Lansweeper',
    'code_equipment': 'Κωδικός εξοπλισμού',
    'destination': 'Προορισμός',
    'output_path': 'Διαδρομή αρχείου',
    'scheduled_time': 'Προγραμματισμένη ώρα',
    'trigger_el': 'Έναυσμα',
    'outcome': 'Αποτέλεσμα',
    'skip_reason': 'Λόγος παράλειψης',
    'missed_deadline': 'Χαμένη προθεσμία',
    'rows_merged': 'Συγχωνευμένες γραμμές',
    'rows_deleted': 'Διαγραμμένες γραμμές',
    'selected_ids_count': 'Επιλεγμένες εγγραφές',
    'removed': 'Αφαιρέθηκαν',
    'cutoff': 'Όριο ημερομηνίας',
    'path': 'Διαδρομή',
    'previous_renamed_to': 'Προηγούμενη μετονομασία',
    'table': 'Πίνακας',
    'affected_ids': 'Επηρεαζόμενα ids',
    'fields': 'Πεδία',
  };

  /// Γενικές ετικέtes πεδίων (γενική πτώση — «Αλλαγή … από»).
  static const Map<String, String> _detailLabels = {
    'name': 'ονόματος',
    'email': 'email',
    'phone': 'τηλεφώνου',
    'status': 'κατάστασης',
    'priority': 'προτεραιότητας',
    'due_date': 'προθεσμίας',
    'title': 'τίτλου',
    'description': 'περιγραφής',
    'solution_notes': 'λύσης',
    'department_id': 'τμήματος',
    'department_text': 'τμήματος',
    'equipment_id': 'εξοπλισμού',
    'equipment_text': 'εξοπλισμού',
    'caller_id': 'χρήστη',
    'caller_text': 'χρήστη',
    'phone_text': 'τηλεφώνου',
    'category_text': 'κατηγορίας',
    'category_id': 'κατηγορίας',
    'issue': 'θέματος',
    'solution': 'λύσης',
    'type': 'τύπου',
    'remote_params': 'παραμέτρων απομακρυσμένης',
    'linked_users': 'συνδεδεμένων χρηστών',
    'linked_equipment': 'συνδεδεμένου εξοπλισμού',
    'linked_phone_numbers': 'τηλεφώνων',
    'linked_user_id': 'χρήστη',
    'color': 'χρώματος',
    'building': 'κτιρίου',
    'map_floor': 'ορόφου',
    'floor_id': 'ορόφου',
    'notes': 'σημειώσεων',
    'map_x': 'θέσης Χ',
    'map_y': 'θέσης Υ',
    'map_width': 'πλάτους',
    'map_height': 'ύψους',
    'map_rotation': 'περιστροφής',
    'map_label_offset_x': 'μετατόπισης ετικέτας Χ',
    'map_label_offset_y': 'μετατόπισης ετικέτας Υ',
    'map_label_font_scale': 'κλίμακας ετικέτας',
    'map_label_width': 'πλάτους ετικέτας',
    'map_label_height': 'ύψους ετικέτας',
    'map_anchor_offset_x': 'μετατόπισης άγκυρας Χ',
    'map_anchor_offset_y': 'μετατόπισης άγκυρας Υ',
    'map_custom_name': 'προσαρμοσμένου ονόματος',
    'map_hidden': 'ορατότητας',
    'user_text': 'χρήστη',
    'duration': 'διάρκειας',
    'is_priority': 'προτεραιότητας',
    'date': 'ημερομηνίας',
    'time': 'ώρας',
    'lansweeper_state': 'κατάστασης Lansweeper',
    'code_equipment': 'κωδικού εξοπλισμού',
    'destination': 'προορισμού',
    'output_path': 'διαδρομής αρχείου',
    'scheduled_time': 'προγραμματισμένης ώρας',
    'trigger_el': 'εναύσματος',
    'outcome': 'αποτελέσματος',
    'skip_reason': 'λόγου παράλειψης',
    'missed_deadline': 'χαμένης προθεσμίας',
    'rows_merged': 'συγχωνευμένων γραμμών',
    'rows_deleted': 'διαγραμμένων γραμμών',
    'selected_ids_count': 'επιλεγμένων εγγραφών',
    'removed': 'αφαιρεθέντων',
    'cutoff': 'ορίου ημερομηνίας',
    'path': 'διαδρομής',
    'previous_renamed_to': 'προηγούμενης μετονομασίας',
    'table': 'πίνακα',
    'affected_ids': 'επηρεαζόμενων ids',
    'fields': 'πεδίων',
  };

  /// Ετικέτες για search_text (χωρίς τόνους).
  static const Map<String, String> _searchLabels = {
    'name': 'ονομα',
    'email': 'email',
    'phone': 'τηλεφωνο',
    'status': 'κατασταση',
    'priority': 'προτεραιοτητα',
    'due_date': 'προθεσμια',
    'title': 'τιτλος',
    'description': 'περιγραφη',
    'solution_notes': 'λυση',
    'department_id': 'τμημα',
    'department_text': 'τμημα',
    'equipment_id': 'εξοπλισμος',
    'equipment_text': 'εξοπλισμος',
    'caller_id': 'χρηστης',
    'caller_text': 'χρηστης',
    'phone_text': 'τηλεφωνο',
    'category_text': 'κατηγορια',
    'category_id': 'κατηγορια',
    'issue': 'θεμα',
    'solution': 'λυση',
    'type': 'τυπος',
    'remote_params': 'παραμετροι απομακρυσμενης',
    'linked_users': 'συνδεδεμενοι χρηστες',
    'linked_equipment': 'συνδεδεμενος εξοπλισμος',
    'linked_phone_numbers': 'τηλεφωνα',
    'linked_user_id': 'χρηστης',
    'color': 'χρωμα',
    'building': 'κτηριο',
    'map_floor': 'οροφος',
    'floor_id': 'οροφος',
    'notes': 'σημειωσεις',
    'map_x': 'θεσης χ',
    'map_y': 'θεσης υ',
    'map_width': 'πλατους',
    'map_height': 'υψους',
    'map_rotation': 'περιστροφης',
    'map_label_offset_x': 'μετατοπισης ετικετας χ',
    'map_label_offset_y': 'μετατοπισης ετικετας υ',
    'map_label_font_scale': 'κλιμακας ετικετας',
    'map_label_width': 'πλατους ετικετας',
    'map_label_height': 'υψους ετικετας',
    'map_anchor_offset_x': 'μετατοπισης αγκυρας χ',
    'map_anchor_offset_y': 'μετατοπισης αγκυρας υ',
    'map_custom_name': 'προσαρμοσμενου ονοματος',
    'map_hidden': 'ορατοτητας',
    'user_text': 'χρηστης',
    'duration': 'διαρκεια',
    'is_priority': 'προτεραιοτητα',
    'date': 'ημερομηνια',
    'time': 'ωρα',
    'lansweeper_state': 'κατασταση lansweeper',
    'code_equipment': 'κωδικος εξοπλισμου',
    'destination': 'προορισμος',
    'output_path': 'διαδρομη αρχειου',
    'scheduled_time': 'προγραμματισμενη ωρα',
    'trigger_el': 'εναυσμα',
    'outcome': 'αποτελεσμα',
    'skip_reason': 'λογος παραλειψης',
    'missed_deadline': 'χαμενη προθεσμια',
    'rows_merged': 'συγχωνευμενες γραμμες',
    'rows_deleted': 'διαγραμμενες γραμμες',
    'selected_ids_count': 'επιλεγμενες εγγραφες',
    'removed': 'αφαιρεθηκαν',
    'cutoff': 'οριο ημερομηνιας',
    'path': 'διαδρομη',
    'previous_renamed_to': 'προηγουμενη μετονομασια',
    'table': 'πινακας',
    'affected_ids': 'επηρεαζομενα ids',
    'fields': 'πεδια',
  };

  /// Παράγωγα πεδία που κρύβονται όταν υπάρχει κύριο πεδίο.
  static bool shouldSkipDerivativeField(String field, Set<String> keys) {
    if (field == 'floor_id' && keys.contains('map_floor')) return true;
    if (field == 'department_text' && keys.contains('department_id')) {
      return true;
    }
    if (field == 'caller_text' && keys.contains('caller_id')) return true;
    if (field == 'trigger' && keys.contains('trigger_el')) return true;
    return false;
  }

  static bool _isEmptyCollection(dynamic value) {
    if (value == null) return true;
    if (value is List) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    if (value is String) {
      final t = value.trim();
      if (t.isEmpty) return true;
    }
    return false;
  }

  static bool _hasMeaningfulCollectionChange(
    String field,
    dynamic oldValue,
    dynamic newValue,
  ) {
    const collectionFields = {
      'linked_phone_numbers',
      'linked_equipment',
      'linked_users',
    };
    if (!collectionFields.contains(field)) return true;
    return !(_isEmptyCollection(oldValue) && _isEmptyCollection(newValue));
  }

  static bool _isEmptyLike(dynamic value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    if (value is List) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    return false;
  }

  /// Κοινός κανόνας: εμφάνιση πεδίου στο «Τι άλλαξε» και στο `search_text`.
  static bool shouldIncludeField(
    String field,
    dynamic oldValue,
    dynamic newValue,
  ) {
    if (excludedFields.contains(field)) return false;
    if (EquipmentRemoteParamKey.isRemoteParamStashKey(field)) return false;
    if (!_hasMeaningfulCollectionChange(field, oldValue, newValue)) {
      return false;
    }
    return !AuditService.valuesEqual(oldValue, newValue);
  }

  /// Ετικέτα πεδίου για `search_text` (κανονικοποιημένη, χωρίς τόνους).
  static String fieldSearchLabel(String entityType, String field) {
    final label = _searchLabels[field];
    if (label != null) return label;
    return humanizeFieldKey(field);
  }

  /// Ετικέτα πεδίου για σύνοψη «N αλλαγές: …» (ονομαστική).
  static String fieldTitleLabel(String entityType, String field) {
    final label = _titleLabels[field];
    if (label != null) return label;
    return humanizeFieldKey(field);
  }

  /// Ετικέτα πεδίου για γραμμές diff («Αλλαγή … από»).
  static String fieldDetailLabel(String entityType, String field) {
    final label = _detailLabels[field];
    if (label != null) return label;
    return humanizeFieldKey(field);
  }

  /// Αναγνώσιμη μορφή κλειδιού πεδίου χωρίς underscores (fallback ετικέτας).
  static String humanizeFieldKey(String field) {
    final t = field.trim();
    if (t.isEmpty) return t;
    if (t.startsWith('__') && t.endsWith('__')) {
      return t.replaceAll('_', ' ').trim();
    }
    return t.replaceAll('_', ' ');
  }

  /// Ανθρώπινη τιμή πεδίου audit (UI + search_text).
  static String humanizeFieldValue(
    String field,
    dynamic value, {
    Map<String, dynamic> sideMap = const {},
    bool forSearch = false,
  }) {
    if (value == null || _isEmptyLike(value)) {
      return forSearch ? '' : 'κενό';
    }

    if (field == 'trigger_el') {
      return value.toString().trim();
    }

    if (field == 'outcome') {
      return _humanizeBackupOutcome(value.toString(), forSearch: forSearch);
    }

    if (field == 'skip_reason') {
      final msg = DatabaseBackupAudit.skipReasonMessageEl(value.toString());
      return forSearch
          ? msg.toLowerCase().replaceAll('ά', 'α').replaceAll('έ', 'ε')
          : msg;
    }

    if (field == 'is_priority') {
      final n = value is bool ? (value ? 1 : 0) : int.tryParse('$value') ?? 0;
      if (forSearch) return n != 0 ? 'ναι' : 'οχι';
      return n != 0 ? 'Ναι' : 'Όχι';
    }

    if (field == 'status') {
      final s = value.toString().trim().toLowerCase();
      const map = <String, String>{
        'pending': 'εκκρεμης',
        'completed': 'ολοκληρωμενη',
        'closed': 'κλειστη',
        'open': 'ανοιχτη',
        'in_progress': 'σε εξελιξη',
      };
      const display = <String, String>{
        'pending': 'Εκκρεμής',
        'completed': 'Ολοκληρωμένη',
        'closed': 'Κλειστή',
        'open': 'Ανοιχτή',
        'in_progress': 'Σε εξέλιξη',
      };
      return forSearch
          ? (map[s] ?? s)
          : (display[s] ?? value.toString().trim());
    }

    if (field == 'priority') {
      final s = value.toString().trim().toLowerCase();
      const map = <String, String>{
        'low': 'χαμηλη',
        'normal': 'κανονικη',
        'medium': 'μεσαια',
        'high': 'υψηλη',
        'urgent': 'επειγουσα',
      };
      const display = <String, String>{
        'low': 'Χαμηλή',
        'normal': 'Κανονική',
        'medium': 'Μεσαία',
        'high': 'Υψηλή',
        'urgent': 'Επείγουσα',
      };
      return forSearch
          ? (map[s] ?? s)
          : (display[s] ?? value.toString().trim());
    }

    if (field == 'color') {
      final r = value.toString().trim().toUpperCase();
      const known = <String, String>{
        '#1976D2': 'μπλε',
        '#EF5350': 'κοκκινο',
        '#4CAF50': 'πρασινο',
        '#FFC107': 'κιτρινο',
        '#9C27B0': 'μωβ',
      };
      const display = <String, String>{
        '#1976D2': 'Μπλε',
        '#EF5350': 'Κόκκινο',
        '#4CAF50': 'Πράσινο',
        '#FFC107': 'Κίτρινο',
        '#9C27B0': 'Μωβ',
      };
      return forSearch
          ? (known[r] ?? value.toString().trim())
          : (display[r] != null ? '${display[r]} $r' : value.toString().trim());
    }

    if (field == 'map_floor') {
      final t = value.toString().trim();
      if (t.isEmpty) return forSearch ? 'χωρις οροφο' : 'χωρίς όροφο';
      return t;
    }

    if (field == 'lansweeper_state') {
      final s = value.toString().trim().toLowerCase();
      const display = <String, String>{
        'unsent': 'Μη αποσταλμένο',
        'sent': 'Απεστάλη',
        'failed': 'Αποτυχία',
      };
      return forSearch
          ? (display[s]?.toLowerCase() ?? s)
          : (display[s] ?? value.toString().trim());
    }

    if (value is List) {
      return forSearch
          ? '${value.length} στοιχεια'
          : '${value.length} στοιχεία';
    }
    if (value is Map) {
      return forSearch ? 'δομημενα δεδομενα' : 'δομημένα δεδομένα';
    }

    return value.toString().trim();
  }

  static String _humanizeBackupOutcome(String raw, {required bool forSearch}) {
    switch (raw.trim().toLowerCase()) {
      case 'success':
        return forSearch ? 'επιτυχια' : 'Επιτυχία';
      case 'failed':
        return forSearch ? 'αποτυχια' : 'Αποτυχία';
      case 'skipped':
        return forSearch ? 'παραλειφθηκε' : 'Παραλείφθηκε';
      case 'missed':
        return forSearch ? 'χαθηκε' : 'Χάθηκε';
      default:
        return raw.trim();
    }
  }

  /// Σειρά εμφάνισης πεδίων στο «Τι άλλαξε».
  static List<String> orderedDiffKeys(String entityType, Set<String> keys) {
    final order = switch (entityType) {
      'call' => const [
          'status',
          'category_text',
          'category_id',
          'caller_text',
          'caller_id',
          'phone_text',
          'department_text',
          'equipment_text',
          'equipment_id',
          'issue',
          'duration',
          'is_priority',
          'date',
          'time',
          'lansweeper_state',
        ],
      'task' => const [
          'status',
          'priority',
          'due_date',
          'solution_notes',
          'title',
          'description',
          'department_text',
          'user_text',
          'equipment_text',
          'phone_text',
        ],
      'department' => const [
          'name',
          'color',
          'building',
          'map_floor',
          'floor_id',
          'notes',
          'map_x',
          'map_y',
          'map_width',
          'map_height',
          'map_rotation',
        ],
      'user' => const [
          'department_id',
          'department_text',
          'email',
          'phone',
          'linked_phone_numbers',
          'linked_equipment',
        ],
      'equipment' => const [
          'department_id',
          'type',
          'code_equipment',
          'remote_params',
          'linked_users',
        ],
      'phone' => const ['linked_user_id', 'department_id'],
      'backup' => const [
          'trigger_el',
          'outcome',
          'destination',
          'output_path',
          'scheduled_time',
          'skip_reason',
        ],
      'maintenance' => const [
          'rows_merged',
          'rows_deleted',
          'table',
          'removed',
          'cutoff',
          'path',
        ],
      _ => const <String>[],
    };
    final out = <String>[];
    for (final k in order) {
      if (keys.contains(k)) out.add(k);
    }
    final rest = keys.where((k) => !out.contains(k)).toList()..sort();
    out.addAll(rest);
    return out;
  }

  /// Ετικέτες πεδίων που άλλαξαν (για σύνοψη πολλαπλών αλλαγών).
  static List<String> changedFieldTitleLabels({
    required String entityType,
    required Map<String, dynamic> oldMap,
    required Map<String, dynamic> newMap,
  }) {
    final allKeys = oldMap.keys.toSet().union(newMap.keys.toSet());
    final keys = orderedDiffKeys(entityType, allKeys);
    final out = <String>[];
    for (final key in keys) {
      if (shouldSkipDerivativeField(key, allKeys)) continue;
      final oldValue = oldMap[key];
      final newValue = newMap[key];
      if (!shouldIncludeField(key, oldValue, newValue)) continue;
      final label = fieldTitleLabel(entityType, key);
      if (out.isEmpty || out.last != label) {
        out.add(label);
      }
    }
    return out;
  }

  /// Σύνθεση diff από αλυσίδα γραμμών audit (παλιότερη → νεότερη).
  static ({Map<String, dynamic> oldDiff, Map<String, dynamic> newDiff})
      computeChainedDiff(
    List<({Map<String, dynamic>? oldMap, Map<String, dynamic>? newMap})> chain,
  ) {
    Map<String, dynamic>? baselineOld;
    Map<String, dynamic>? finalNew;
    for (final step in chain) {
      if (baselineOld == null && step.oldMap != null && step.oldMap!.isNotEmpty) {
        baselineOld = Map<String, dynamic>.from(step.oldMap!);
      }
      if (step.newMap != null && step.newMap!.isNotEmpty) {
        finalNew = Map<String, dynamic>.from(step.newMap!);
      }
    }
    baselineOld ??= const <String, dynamic>{};
    finalNew ??= const <String, dynamic>{};

    final oldDiff = <String, dynamic>{};
    final newDiff = <String, dynamic>{};
    final allKeys = baselineOld.keys.toSet().union(finalNew.keys.toSet());
    for (final key in allKeys) {
      final oldValue = baselineOld[key];
      final newValue = finalNew[key];
      if (!shouldIncludeField(key, oldValue, newValue)) continue;
      oldDiff[key] = oldValue;
      newDiff[key] = newValue;
    }
    return (oldDiff: oldDiff, newDiff: newDiff);
  }

  /// Μορφή λεπτομερειών «N αλλαγές: …» (Φάση 1).
  static String buildMultiChangeDetails({
    required String entityType,
    required int entityId,
    required Map<String, dynamic> oldDiff,
    required Map<String, dynamic> newDiff,
    String? baseDetails,
  }) {
    final labels = changedFieldTitleLabels(
      entityType: entityType,
      oldMap: oldDiff,
      newMap: newDiff,
    );
    final base = (baseDetails ?? '${entityType}s id=$entityId').trim();
    if (labels.isEmpty) return base;
    if (labels.length == 1) return base;
    return '$base · ${labels.length} αλλαγές: ${labels.join(', ')}';
  }

  // ignore: unintended_html_in_doc_comment
  /// Μετατροπή τιμής remote_params σε Map<String, String> (χωρίς stash).
  static Map<String, String> parseRemoteParamsMap(dynamic value) {
    Map<String, dynamic>? raw;
    if (value == null) return const {};
    if (value is Map) {
      raw = value.map((k, v) => MapEntry(k.toString(), v));
    } else if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          raw = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {}
    }
    if (raw == null || raw.isEmpty) return const {};

    final out = <String, String>{};
    for (final entry in raw.entries) {
      if (EquipmentRemoteParamKey.isRemoteParamStashKey(entry.key)) continue;
      if (EquipmentRemoteParamKey.isReservedKey(entry.key) &&
          entry.key != EquipmentRemoteParamKey.exclusiveToolKey) {
        continue;
      }
      out[entry.key] = '${entry.value ?? ''}'.trim();
    }
    return out;
  }

  static String remoteToolDisplayName(
    int toolId,
    Map<int, String> toolNames,
  ) {
    final name = toolNames[toolId]?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Εργαλείο #$toolId';
  }

  static String? _formatExclusiveToolChange({
    required String? oldRaw,
    required String? newRaw,
    required Map<int, String> toolNames,
  }) {
    final oldId = int.tryParse(oldRaw?.trim() ?? '');
    final newId = int.tryParse(newRaw?.trim() ?? '');
    if (oldId == null && newId == null) return null;
    if (oldId == null && newId != null) {
      return 'Μόνο ένα εργαλείο: προστέθηκε ${remoteToolDisplayName(newId, toolNames)}';
    }
    if (oldId != null && newId == null) {
      return 'Μόνο ένα εργαλείο: αφαιρέθηκε ${remoteToolDisplayName(oldId, toolNames)}';
    }
    if (oldId != null && newId != null) {
      final oldName = remoteToolDisplayName(oldId, toolNames);
      final newName = remoteToolDisplayName(newId, toolNames);
      if (oldName == newName) return null;
      return 'Μόνο ένα εργαλείο: $oldName → $newName';
    }
    return null;
  }

  static String? _formatToolParamChange({
    required String toolLabel,
    required String? oldVal,
    required String? newVal,
  }) {
    final oldEmpty = oldVal == null || oldVal.trim().isEmpty;
    final newEmpty = newVal == null || newVal.trim().isEmpty;
    if (oldEmpty && newEmpty) return null;
    if (oldEmpty && !newEmpty) {
      return '$toolLabel: προστέθηκε $newVal';
    }
    if (!oldEmpty && newEmpty) {
      return '$toolLabel: αφαιρέθηκε';
    }
    if (oldVal == newVal) return null;
    return '$toolLabel: $oldVal → $newVal';
  }

  /// Diff παραμέτρων απομακρυσμένης ανά εργαλείο (UI).
  static List<String> describeRemoteParamsDiffLines({
    required dynamic oldValue,
    required dynamic newValue,
    Map<int, String> toolNames = const {},
  }) {
    final oldMap = parseRemoteParamsMap(oldValue);
    final newMap = parseRemoteParamsMap(newValue);
    final lines = <String>[];

    final exclusiveLine = _formatExclusiveToolChange(
      oldRaw: oldMap[EquipmentRemoteParamKey.exclusiveToolKey],
      newRaw: newMap[EquipmentRemoteParamKey.exclusiveToolKey],
      toolNames: toolNames,
    );
    if (exclusiveLine != null) lines.add(exclusiveLine);

    final toolIds = <int>{};
    for (final key in {...oldMap.keys, ...newMap.keys}) {
      if (key == EquipmentRemoteParamKey.exclusiveToolKey) continue;
      final id = int.tryParse(key);
      if (id != null) toolIds.add(id);
    }

    final sortedIds = toolIds.toList()..sort();
    for (final id in sortedIds) {
      final key = '$id';
      final line = _formatToolParamChange(
        toolLabel: remoteToolDisplayName(id, toolNames),
        oldVal: oldMap[key],
        newVal: newMap[key],
      );
      if (line != null) lines.add(line);
    }
    return lines;
  }

  /// Κείμενο remote_params για search_text (χωρίς τόνους).
  static String remoteParamsSearchText({
    required dynamic oldValue,
    required dynamic newValue,
    Map<int, String> toolNames = const {},
  }) {
    final lines = describeRemoteParamsDiffLines(
      oldValue: oldValue,
      newValue: newValue,
      toolNames: toolNames,
    );
    if (lines.isEmpty) return '';
    return lines
        .join(' ')
        .toLowerCase()
        .replaceAll('ά', 'α')
        .replaceAll('έ', 'ε')
        .replaceAll('ή', 'η')
        .replaceAll('ί', 'ι')
        .replaceAll('ό', 'ο')
        .replaceAll('ύ', 'υ')
        .replaceAll('ώ', 'ω');
  }

  /// Μήνυμα όταν όλες οι αλλαγές είναι ήδη στη σύνοψη (πλαίσιο λεπτομερειών).
  static const String allChangesInSummaryMessage =
      'Όλες οι αλλαγές φαίνονται στη σύνοψη';
}
