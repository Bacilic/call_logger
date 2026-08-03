// Περίληψη και συγκεντρωτικά για τη μαζική διαγραφή εξοπλισμού.
//
// Μόνο μοντέλα και λογική παρουσίασης — οι αναγνώσεις ζουν στο
// `core/database/equipment_deletion_summary_repository.dart`.

import '../../../core/utils/asset_history_labels.dart';
import 'bulk_deletion_summary.dart';

/// Πάνω από αυτό το μήκος το μικρό όνομα συντομεύεται σε αρχικά.
const int _kOwnerNameCompactThreshold = 18;

/// Περίληψη εξοπλισμού για τον διάλογο επιβεβαίωσης διαγραφής.
class EquipmentDeletionSummary {
  const EquipmentDeletionSummary({
    required this.equipmentId,
    required this.code,
    this.ownerName,
    this.departmentName,
    this.phone,
    this.callCount = 0,
    this.taskCount = 0,
    this.lastCallAt,
    this.lastTaskAt,
  });

  final int equipmentId;
  final String code;

  /// Ο υπάλληλος-κάτοχος, αν υπάρχει.
  final String? ownerName;

  /// Το τμήμα του εξοπλισμού — παίρνει τη θέση του κατόχου όταν δεν υπάρχει
  /// υπάλληλος. Χωρίς αυτό ο εξοπλισμός είναι σκέτος αριθμός στην οθόνη.
  final String? departmentName;

  final String? phone;

  /// Κλήσεις ιστορικού που τον αναφέρουν — και με δεσμό, και μόνο ως κείμενο.
  final int callCount;

  /// Εκκρεμότητες που τον αναφέρουν. Δεν είναι «ιστορικό»: είναι ανοιχτή
  /// δουλειά, γι' αυτό μετριούνται χωριστά.
  final int taskCount;

  final DateTime? lastCallAt;
  final DateTime? lastTaskAt;

  /// Πόσα ίχνη χρήσης αφήνει πίσω του συνολικά.
  int get traceCount => callCount + taskCount;

  bool get hasTraces => traceCount > 0;

  /// «2113 → Αναστασία Φούφα» ή «2113 → τμήμα Αιμοδοσία».
  String get titleLine => '$code → $ownerLabel';

  /// Ο κάτοχος όπως εμφανίζεται: υπάλληλος, αλλιώς τμήμα.
  String get ownerLabel =>
      equipmentOwnerLabel(ownerName: ownerName, departmentName: departmentName);

  /// Τι αφήνει πίσω του, μία γραμμή ανά είδος· παραλείπει τα μηδενικά.
  List<String> buildTraceLines() {
    final p = phone?.trim() ?? '';
    return [
      if (p.isNotEmpty) 'τηλ. $p',
      if (callCount > 0) callHistoryLabel(callCount, lastUsedAt: lastCallAt),
      if (taskCount > 0) taskHistoryLabel(taskCount, lastUsedAt: lastTaskAt),
    ];
  }
}

/// «Αναστασία Φούφα» → «Αν. Φούφα»: αρχικά στα μικρά ονόματα, ακέραιο το
/// επώνυμο — αυτό είναι που ξεχωρίζει τον υπάλληλο.
String compactPersonName(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length < 2) return fullName.trim();
  final surname = parts.removeLast();
  final initials = parts
      .map((p) => '${p.substring(0, p.length >= 2 ? 2 : 1)}.')
      .join(' ');
  return '$initials $surname';
}

/// Ποιος «κρατά» τον εξοπλισμό: ο υπάλληλος, αλλιώς το τμήμα.
///
/// Χωρίς κάτοχο ο εξοπλισμός εμφανίζεται ως σκέτος κωδικός και ο χρήστης δεν
/// έχει τρόπο να καταλάβει τι διαγράφει.
String equipmentOwnerLabel({String? ownerName, String? departmentName}) {
  final owner = ownerName?.trim() ?? '';
  if (owner.isNotEmpty) {
    return owner.length > _kOwnerNameCompactThreshold
        ? compactPersonName(owner)
        : owner;
  }
  final dept = departmentName?.trim() ?? '';
  if (dept.isNotEmpty) return 'τμήμα $dept';
  return 'χωρίς κάτοχο και τμήμα';
}

/// Συγκεντρωτικά πλήθη για τη σύνοψη της μαζικής διαγραφής εξοπλισμού.
class EquipmentDeletionTotals {
  const EquipmentDeletionTotals({
    required this.equipmentCount,
    required this.withOwnerCount,
    required this.callCount,
    required this.taskCount,
  });

  /// Τα συγκεντρωτικά βγαίνουν από τις **ίδιες** περιλήψεις που βλέπει ο
  /// χρήστης — έτσι η σύνοψη δεν μπορεί ποτέ να διαφωνήσει με τη λίστα.
  factory EquipmentDeletionTotals.fromSummaries(
    List<EquipmentDeletionSummary> summaries,
  ) {
    var withOwner = 0;
    var calls = 0;
    var tasks = 0;
    for (final s in summaries) {
      if ((s.ownerName?.trim() ?? '').isNotEmpty) withOwner++;
      calls += s.callCount;
      tasks += s.taskCount;
    }
    return EquipmentDeletionTotals(
      equipmentCount: summaries.length,
      withOwnerCount: withOwner,
      callCount: calls,
      taskCount: tasks,
    );
  }

  final int equipmentCount;

  /// Πόσοι έχουν υπάλληλο-κάτοχο — αυτοί αφήνουν κάποιον χωρίς το μηχάνημά του.
  final int withOwnerCount;

  /// Συνολικές κλήσεις ιστορικού που δείχνουν σε αυτούς.
  final int callCount;

  /// Συνολικές εκκρεμότητες που δείχνουν σε αυτούς.
  final int taskCount;

  /// «13 εξοπλισμοί · 2 με κάτοχο · 5 κλήσεις ιστορικού · 1 εκκρεμότητα».
  String headline({int? initiallySelected}) {
    return buildBulkDeletionHeadline(
      subject: SummaryCount(equipmentCount, 'εξοπλισμός', 'εξοπλισμοί'),
      initiallySelected: initiallySelected,
      details: [
        SummaryCount(withOwnerCount, 'με κάτοχο', 'με κάτοχο'),
        SummaryCount(callCount, 'κλήση ιστορικού', 'κλήσεις ιστορικού'),
        SummaryCount(taskCount, 'εκκρεμότητα', 'εκκρεμότητες'),
      ],
    );
  }
}
