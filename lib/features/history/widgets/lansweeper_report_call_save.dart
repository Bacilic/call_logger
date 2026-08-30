import 'package:flutter/material.dart';

import '../../../core/database/calls_lansweeper_repository.dart';
import '../../../core/services/lansweeper_sync_service.dart';
import '../providers/lansweeper_sync_provider.dart';
import 'lansweeper/lansweeper_ai_presenter.dart';
import 'lansweeper/lansweeper_report_item_mapper.dart';
import 'lansweeper_report_dialog.dart';

/// «Αποθήκευση στην κλήση»: τα κείμενα της φόρμας γράφονται πάνω στην κλήση
/// και **τίποτα άλλο δεν συμβαίνει**.
///
/// Η τέταρτη έξοδος της φόρμας, για τις φορές που ο χειριστής θέλει το
/// δουλεμένο κείμενο αλλά όχι αίτημα στο Lansweeper. Οι άλλες τρεις είτε
/// σημαδεύουν την κλήση ως καταχωρημένη (άμεση καταχώρηση, επαναϋποβολή) είτε
/// φεύγουν στον περιηγητή (αντιγραφή & άνοιγμα)· εδώ η κλήση **μένει στην ουρά
/// ως ακαταχώρητη**.
///
/// Συνεργάτης του [LansweeperReportDialogState] (Σύνθεση).
class LansweeperReportCallSave {
  LansweeperReportCallSave(this.host);

  final LansweeperReportDialogState host;

  /// Γιατί δεν μπορεί να γίνει τώρα· `null` σημαίνει «μπορεί».
  ///
  /// Καθαρή λογική, χωρίς εξάρτηση από τον διάλογο: η ίδια απόφαση κρίνει και
  /// το κουμπί και την ίδια την αποθήκευση, ώστε να μη γίνει ποτέ κάτι που το
  /// κουμπί δηλώνει αδύνατο.
  static String? disabledReasonFor({
    required int selectedCount,
    required String notes,
    required String solution,
    required bool hasChanges,
  }) {
    if (selectedCount == 0) {
      return 'Επιλέξτε πρώτα την κλήση στην οποία θα γραφτεί το κείμενο.';
    }
    if (notes.trim().isEmpty && solution.trim().isEmpty) {
      return 'Συμπληρώστε περιγραφή ή λύση — δεν υπάρχει κείμενο να σωθεί.';
    }
    // Χωρίς αυτόν τον όρο το κουμπί δεχόταν κάθε πάτημα και απαντούσε
    // «αποθηκεύτηκε» ενώ δεν είχε αλλάξει τίποτα — και άφηνε κάθε φορά νέα
    // εγγραφή στο ιστορικό της κλήσης για μηδενική δουλειά.
    if (!hasChanges) {
      return 'Το κείμενο είναι ήδη αποθηκευμένο — δεν υπάρχει καμία αλλαγή.';
    }
    return null;
  }

  /// Το κείμενο που θα γραφτεί ως Περιγραφή, με τον τίτλο μπροστά όταν αξίζει.
  ///
  /// Ο αυτόματος τίτλος υπολογίζεται από την **πρώτη** επιλεγμένη κλήση, όπως
  /// και η προσυμπλήρωση του πεδίου: είναι το μέτρο σύγκρισης για το «έγραψε ο
  /// χρήστης δικό του τίτλο;».
  String _issueFor(List<ReportCallItem> selected) {
    final primary = selected.first.call;
    return LansweeperSyncService.buildCallIssue(
      title: host.titleController.text,
      autoTitle: LansweeperSyncService.autoTicketTitle(
        category: primary.category ?? '',
        id: primary.id,
      ),
      notes: host.notesController.text,
    );
  }

  /// Υπάρχει έστω μία επιλεγμένη κλήση που θα άλλαζε πραγματικά;
  ///
  /// Αρκεί μία: όταν το ίδιο κείμενο γράφεται σε πολλές κλήσεις μαζί, η μία που
  /// υπολείπεται είναι λόγος να γίνει η εγγραφή.
  bool _hasChanges(List<ReportCallItem> selected) {
    if (selected.isEmpty) return false;
    final issue = _issueFor(selected);
    final solution = host.solutionController.text;
    return selected.any(
      (item) => CallsLansweeperRepository.wouldChangeTexts(
        problem: issue,
        solution: solution,
        currentIssue: item.call.issue,
        currentSolution: item.call.solution,
      ),
    );
  }

  /// Η ίδια απόφαση για τα **τρέχοντα** πεδία της φόρμας.
  String? saveDisabledReason(List<ReportCallItem> selected) =>
      disabledReasonFor(
        selectedCount: selected.length,
        notes: host.notesController.text,
        solution: host.solutionController.text,
        hasChanges: _hasChanges(selected),
      );

  Future<void> saveToCall(List<ReportCallItem> selected) async {
    if (saveDisabledReason(selected) != null) return;

    final callIds = selected
        .map((item) => item.call.id)
        .whereType<int>()
        .toList();
    if (callIds.isEmpty) return;

    final notes = host.notesController.text;
    final solution = host.solutionController.text;
    final issue = _issueFor(selected);

    await host.ref
        .read(lansweeperSyncProvider.notifier)
        .persistRefinedTexts(
          callIds: callIds,
          problem: issue,
          solution: solution,
          // Η προέλευση κρίνεται από τα ίδια κείμενα που κρίνει και η αποστολή
          // προς το Lansweeper — ο τίτλος δεν αλλάζει το αν το κείμενο ήρθε από
          // την ΤΝ ή από τα χέρια του χρήστη.
          source: LansweeperAiPresenter.refinedSource(
            aiProblem: host.aiSuggestedNotes,
            aiSolution: host.aiSuggestedSolution,
            problem: notes,
            solution: solution,
          ),
        );

    if (!host.mounted) return;
    host.showDialogSnackBar(
      SnackBar(
        content: Text(
          callIds.length == 1
              ? 'Το κείμενο αποθηκεύτηκε στην κλήση. Παραμένει ακαταχώρητη '
                    'στο Lansweeper.'
              : 'Το κείμενο αποθηκεύτηκε σε ${callIds.length} κλήσεις. '
                    'Παραμένουν ακαταχώρητες στο Lansweeper.',
        ),
      ),
    );
  }
}
