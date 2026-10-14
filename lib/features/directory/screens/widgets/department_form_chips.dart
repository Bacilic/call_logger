import 'package:flutter/material.dart';

import '../../../../core/services/lansweeper_department_accounts.dart';
import '../../../../core/services/lansweeper_identity_diagnosis.dart';
import '../../../../core/widgets/compact_tooltip.dart';
import '../../services/catalog_validation_service.dart';

/// Τα «κουτάκια» της φόρμας τμήματος: κοινόχρηστα τηλέφωνα/εξοπλισμός και
/// λογαριασμοί Lansweeper. Αυτοτελή — παίρνουν μόνο ό,τι τους δίνεται.

/// Chip λογαριασμού Lansweeper με σήμανση εγκυρότητας:
/// 🟩 έγκυρο · 🟧 έγκυρο με ύποπτο τομέα (διαφέρει από του πράκτορα) ·
/// 🟥 άκυρο, με το ΣΤΟΧΕΥΜΕΝΟ λάθος στο tooltip (οικονομία χώρου — δεν
/// υπάρχει πια συγκεντρωτικό κόκκινο κείμενο κάτω από τα chips).
///
/// Κλικ στο σώμα = επεξεργασία (το κείμενο επιστρέφει στο πεδίο)· το X
/// παραμένει η αφαίρεση.
class LansweeperAccountChip extends StatelessWidget {
  const LansweeperAccountChip({
    super.key,
    required this.account,
    required this.referenceDomain,
    required this.onEdit,
    required this.onRemove,
  });

  final LansweeperAccount account;

  /// Τομέας αναφοράς για την πορτοκαλί υποψία (βλ.
  /// [lansweeperReferenceDomain]) — null = χωρίς μέτρο σύγκρισης.
  final String? referenceDomain;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final diagnosis = diagnoseLansweeperIdentity(account.username);
    final mismatch = diagnosis.isValid
        ? lansweeperDomainMismatchHint(account.username, referenceDomain)
        : null;

    final Color background;
    final String statusLine;
    if (!diagnosis.isValid) {
      background = Colors.red.shade100;
      statusLine = diagnosis.suggestion == null
          ? diagnosis.problem!
          : '${diagnosis.problem!}\n${diagnosis.suggestion!}';
    } else if (mismatch != null) {
      background = Colors.orange.shade100;
      statusLine = mismatch;
    } else {
      background = Colors.lightGreen.shade100;
      statusLine = diagnosis.kind == LansweeperIdentityKind.email
          ? 'Έγκυρο email'
          : 'Έγκυρο αναγνωριστικό τομέα';
    }

    return CompactTooltip(
      message:
          '$statusLine\n\nΚλικ για επεξεργασία — το κείμενο '
          'επιστρέφει στο πεδίο',
      waitDuration: const Duration(milliseconds: 350),
      child: InputChip(
        label: Text(account.toInputText()),
        backgroundColor: background,
        onPressed: onEdit,
        deleteIcon: const Icon(Icons.cancel),
        deleteButtonTooltipMessage: 'Διαγραφή',
        onDeleted: onRemove,
      ),
    );
  }
}

/// Chip κοινόχρηστου τηλεφώνου/εξοπλισμού: ενεργό, νεοπροστεθέν ή προς αφαίρεση.
class RemovableSharedChip extends StatelessWidget {
  const RemovableSharedChip({
    super.key,
    required this.label,
    required this.isNewlyAdded,
    required this.isPendingRemoval,
    required this.onToggle,
    this.onPressed,
    this.diagnosis = CatalogChipDiagnosis.ok,
  });

  final String label;
  final bool isNewlyAdded;
  final bool isPendingRemoval;
  final VoidCallback onToggle;

  /// Προαιρετικό κλικ στο σώμα του chip (π.χ. «φέρε το προς επεξεργασία»).
  /// Το X παραμένει η διαγραφή/αναίρεση, ανεξάρτητα από αυτό.
  final VoidCallback? onPressed;

  /// Πόσο ύποπτη είναι η τιμή. Φοριέται ως **εικονίδιο**, όχι ως φόντο: το
  /// φόντο μιλά ήδη για την κατάσταση του chip (πράσινο = μόλις προστέθηκε,
  /// κόκκινο = θα αφαιρεθεί) και δύο νοήματα στο ίδιο χρώμα θα ακύρωναν
  /// και τα δύο.
  final CatalogChipDiagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final chip = InputChip(
      onPressed: onPressed,
      avatar: _severityIcon(),
      label: Text(
        label,
        style: isPendingRemoval
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      backgroundColor: isPendingRemoval
          ? Colors.red.shade100
          : (isNewlyAdded ? Colors.lightGreen.shade100 : null),
      deleteIcon: Icon(isPendingRemoval ? Icons.undo : Icons.cancel),
      deleteButtonTooltipMessage: isPendingRemoval
          ? 'Θα αφαιρεθεί στην αποθήκευση — κλικ για επαναφορά'
          : 'Διαγραφή',
      onDeleted: onToggle,
    );

    if (!diagnosis.hasRemark) return chip;
    return CompactTooltip(
      message: diagnosis.message,
      waitDuration: const Duration(milliseconds: 350),
      child: chip,
    );
  }

  /// Το σπάνιο ψιθυρίζει, το απίθανο μιλά — καμία ένδειξη για το συνηθισμένο.
  Widget? _severityIcon() {
    return switch (diagnosis.severity) {
      CatalogChipSeverity.ok => null,
      CatalogChipSeverity.suspicious => Icon(
        Icons.info_outline,
        size: 18,
        color: Colors.orange.shade800,
      ),
      CatalogChipSeverity.wrong => Icon(
        Icons.error_outline,
        size: 18,
        color: Colors.red.shade700,
      ),
    };
  }
}
