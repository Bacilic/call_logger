import '../../../core/services/lookup_service.dart';

/// Τι βρήκε η γρήγορη καταχώρηση ορφανών και τι πρόκειται να γράψει.
///
/// Είναι **μόνο δεδομένα**: κανένα ερώτημα στη βάση, καμία εγγραφή. Η ροή
/// εκτέλεσης το φτιάχνει μία φορά στην αρχή και το κουβαλά ως τη λήξη, ώστε
/// «τι θα γραφτεί» να απαντιέται **μία φορά** — ο δεύτερος υπολογισμός της
/// ίδιας ερώτησης μέσα στην εκτέλεση ήταν ακριβώς εκείνος που ξέχασε τον
/// φρουρό του Είδους και χρέωνε μηχανήματα σε εταιρείες.
class OrphanQuickAddPlan {
  const OrphanQuickAddPlan({
    required this.departmentText,
    required this.departmentId,
    required this.phone,
    required this.equipmentCode,
    required this.phoneUsage,
    required this.equipmentUsage,
    required this.phoneNeedsShared,
    required this.equipmentNeedsShared,
    required this.departmentExistedBefore,
    required this.phoneExistedBefore,
    required this.equipmentExistedBefore,
  });

  /// Το όνομα τμήματος όπως γράφτηκε στη φόρμα (χωρίς περιττά κενά).
  final String departmentText;

  /// Το τμήμα της φόρμας όταν αναγνωρίστηκε· `null` όταν πρέπει να δημιουργηθεί.
  final int? departmentId;

  /// Οι τιμές των πεδίων — `null` όταν το πεδίο είναι κενό.
  final String? phone;
  final String? equipmentCode;

  /// Τι γνωρίζει ήδη ο κατάλογος για τις δύο τιμές.
  final PhoneUsageCheck? phoneUsage;
  final EquipmentUsageCheck? equipmentUsage;

  /// Η **μοναδική** απάντηση στο «τι θα γραφτεί», όπως την έδωσε η οθόνη.
  final bool phoneNeedsShared;
  final bool equipmentNeedsShared;

  /// Τι υπήρχε στη βάση πριν από την καταχώρηση — καθορίζει αν γεννιέται
  /// εκκρεμότητα «νέα οντότητα».
  final bool departmentExistedBefore;
  final bool phoneExistedBefore;
  final bool equipmentExistedBefore;

  /// True όταν η καταχώρηση θα γράψει έστω κάτι.
  bool get writesAnything => phoneNeedsShared || equipmentNeedsShared;

  /// True όταν εμφανίστηκε έστω μία ολοκαίνουργια οντότητα στη φόρμα.
  bool get hasNewEntity =>
      (departmentText.isNotEmpty && !departmentExistedBefore) ||
      (phone != null && !phoneExistedBefore) ||
      (equipmentCode != null && !equipmentExistedBefore);

  /// Το τηλέφωνο συγκρούεται όταν πρόκειται να γραφτεί **και** ο κατάλογος το
  /// ξέρει ήδη αλλού — σε κατόχους ή σε άλλο τμήμα.
  ///
  /// Η σύγκρουση ρωτιέται **μόνο για ό,τι όντως γράφεται**: ένα πεδίο που η
  /// κρίση άφησε έξω δεν ζητά έγκριση και δεν μπαίνει στο μήνυμα.
  bool get phoneConflicts {
    final usage = phoneUsage;
    if (!phoneNeedsShared || usage == null) return false;
    return usage.hasUserOwners || _livesElsewhere(usage.departmentId);
  }

  bool get equipmentConflicts {
    final usage = equipmentUsage;
    if (!equipmentNeedsShared || usage == null) return false;
    return usage.hasUserOwners || _livesElsewhere(usage.departmentId);
  }

  bool get hasConflict => phoneConflicts || equipmentConflicts;

  /// True όταν ο κατάλογος ξέρει την τιμή σε **άλλο** τμήμα από της φόρμας.
  bool _livesElsewhere(int? usageDepartmentId) =>
      usageDepartmentId != null &&
      departmentId != null &&
      usageDepartmentId != departmentId;
}

/// Το κείμενο που ζητά την έγκρισή του χρήστη πριν από την καταχώρηση.
///
/// Επιστρέφει `null` όταν καμία σύγκρουση δεν χρειάζεται έγκριση.
String? orphanQuickAddConflictMessage(OrphanQuickAddPlan plan) {
  if (!plan.hasConflict) return null;

  final lines = <String>['Εντοπίστηκαν πιθανές συγκρούσεις για Shared Policy.'];

  if (plan.phoneConflicts) {
    final usage = plan.phoneUsage!;
    if (usage.hasUserOwners) {
      lines.add(
        'Το τηλέφωνο ${usage.phone} ανήκει ήδη στους: ${usage.userNames.join(', ')}.',
      );
    }
    if (usage.departmentId != null && usage.departmentName != null) {
      lines.add(
        'Το τηλέφωνο ${usage.phone} έχει ήδη τοποθεσία τμήμα: ${usage.departmentName}.',
      );
    }
  }

  if (plan.equipmentConflicts) {
    final usage = plan.equipmentUsage!;
    if (usage.hasUserOwners) {
      lines.add(
        'Ο εξοπλισμός ${usage.code} ανήκει ήδη στους: ${usage.userNames.join(', ')}.',
      );
    }
    if (usage.departmentId != null && usage.departmentName != null) {
      lines.add(
        'Ο εξοπλισμός ${usage.code} έχει ήδη τοποθεσία τμήμα: ${usage.departmentName}.',
      );
    }
  }

  final where = plan.departmentText.isEmpty ? '—' : plan.departmentText;
  lines.add('Θέλετε να καταχωρηθούν ΚΑΙ ως κοινόχρηστα στο τμήμα $where;');
  return lines.join('\n');
}

/// Το μήνυμα που ανακοινώνει τι έγινε — **ό,τι γράφτηκε, τίποτε άλλο**.
///
/// Το [departmentName] είναι το τμήμα όπως λέγεται μετά την καταχώρηση: αν
/// δημιουργήθηκε τώρα, κερδίζει το όνομα του καταλόγου, όχι της πληκτρολόγησης.
String orphanQuickAddSuccessMessage({
  required bool phoneWritten,
  required bool equipmentWritten,
  required String departmentName,
}) {
  final added = <String>[
    if (phoneWritten) 'τηλέφωνο',
    if (equipmentWritten) 'εξοπλισμός',
  ];
  if (added.isEmpty) return 'Δεν υπήρχε στοιχείο προς καταχώρηση.';
  return 'Καταχωρήθηκε ${added.join(' και ')} ως κοινόχρηστο '
      'στο τμήμα $departmentName.';
}
