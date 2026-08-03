import '../../../core/utils/transfer_action_messages.dart';
import 'lamp_migration_service.dart';

/// Κείμενα του διαλόγου διενέξεων του οδηγού μεταφοράς Λάμπας.
///
/// Ζουν εκτός widget ώστε να ελέγχονται ως καθαρές συναρτήσεις και να τηρούν το
/// ίδιο συμβόλαιο με τον διάλογο σύγκρουσης τηλεφώνου του Καταλόγου: ποιος
/// χάνει τον αριθμό/εξοπλισμό και ποιος τον παίρνει, με ονόματα.

/// Ποιος θα πάρει την οντότητα, όπως τον δηλώνει η φόρμα του οδηγού.
///
/// Κενό κείμενο σημαίνει «κανείς» — π.χ. εξοπλισμός που αποδεσμεύεται χωρίς νέο
/// κάτοχο· τα μηνύματα το λένε ρητά αντί να υπονοήσουν παραλήπτη.
String lampConflictAssignTargetLabel({
  required LampTransferTarget target,
  required Map<String, String> formValues,
}) {
  String value(String key) => (formValues[key] ?? '').trim();

  final department = value('department_name');
  String withDepartment(String name) =>
      department.isEmpty ? name : '$name ($department)';

  switch (target) {
    case LampTransferTarget.owner:
      final name = [
        value('first_name'),
        value('last_name'),
      ].where((part) => part.isNotEmpty).join(' ');
      if (name.isEmpty) return withDepartment('τον υπάλληλο που καταχωρείτε');
      return withDepartment(name);
    case LampTransferTarget.department:
      final name = value('name');
      return name.isEmpty ? 'το τμήμα που καταχωρείτε' : 'το τμήμα $name';
    case LampTransferTarget.equipment:
      final owner = value('owner_name');
      return owner.isEmpty ? '' : withDepartment(owner);
  }
}

/// «Το τηλέφωνο 2914 είναι κοινόχρηστο στο τμήμα Φαρμακείο και ανήκει σε: …»
String lampConflictTitle(LampOwnerConflict conflict) {
  final entity = switch (conflict.kind) {
    LampOwnerConflictKind.equipment => 'Ο εξοπλισμός ${conflict.value}',
    LampOwnerConflictKind.phone => 'Το τηλέφωνο ${conflict.value}',
  };
  final parts = <String>[
    if (conflict.hasSharedDepartment)
      'είναι κοινόχρηστο στο τμήμα ${conflict.sharedDepartmentName!.trim()}',
    if (conflict.hasUserOwners)
      'ανήκει σε: ${ownerNamesForMessage(conflict.currentOwners)}',
  ];
  if (parts.isEmpty) return entity;
  return '$entity ${parts.join(' και ')}';
}

/// «Αφαίρεση από Φαρμακείο (κοινόχρηστο) και από Βασίλης Πρόβος (Φαρμακείο)
/// και σύνδεση με Μαρία Παπαλαμπροπούλου (Γραμματεία)».
String lampConflictTransferLabel(
  LampOwnerConflict conflict, {
  required String targetLabel,
}) {
  return removeAndAssignMessage(
    sources: [
      if (conflict.hasSharedDepartment)
        sharedDepartmentSource(conflict.sharedDepartmentName),
      if (conflict.hasUserOwners)
        ownerNamesForMessage(
          conflict.currentOwners,
          ifEmpty: 'τους τωρινούς κατόχους',
        ),
    ],
    target: targetLabel,
  );
}

/// Η διέξοδος που αφήνει τα πράγματα όπως είναι.
String lampConflictSkipLabel(LampOwnerConflict conflict) {
  return switch (conflict.kind) {
    LampOwnerConflictKind.equipment =>
      'Καμία αλλαγή — καταχώρηση χωρίς τον εξοπλισμό ${conflict.value}',
    LampOwnerConflictKind.phone =>
      'Καμία αλλαγή — καταχώρηση χωρίς το τηλέφωνο ${conflict.value}',
  };
}
