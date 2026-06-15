// Επίλυση προβλημάτων ETL: προεπισκόπηση, επιβεβαιώσεις, εφαρμογή διορθώσεων.
import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_data_issue_type_labels.dart';
import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/database/old_database/resolution_log_entry.dart';
import '../widgets/lamp_issue_manual_review_dialog.dart';
import '../widgets/lamp_resolution_progress_dialog.dart';
import '../widgets/lamp_unresolved_resolution_dialog.dart';
import 'lamp_path_management.dart';
import 'lamp_screen_host.dart';
import 'lamp_search_controller.dart';

class LampIssueResolutionController {
  LampIssueResolutionController({
    required this.host,
    required this.path,
    required this.search,
    required this.issuesList,
    required this.issueCountFor,
  });

  final LampScreenHost host;
  final LampPathController path;
  final LampSearchController search;
  final List<Map<String, Object?>> Function() issuesList;
  final int Function(LampIssueType issueType) issueCountFor;

  LampIssueType? resolvingIssueType;

  bool canResolveIssueType(LampIssueType issueType) =>
      search.readPathReadyForQuery &&
      resolvingIssueType == null &&
      issueCountFor(issueType) > 0;

  Future<void> runIssueResolution(LampIssueType issueType) async {
    if (resolvingIssueType != null) return;
    final dbPath = path.readDbController.text.trim();
    if (!search.readPathReadyForQuery || dbPath.isEmpty) {
      host.showSnack('Η βάση προς ανάγνωση δεν είναι έτοιμη.', isError: true);
      return;
    }

    resolvingIssueType = issueType;
    host.notifyState();
    try {
      host.showSnack('Ανάλυση προτάσεων: ${issueType.label}…');
      final proposals = await host.shared.issueResolutionService.analyzeIssues(
        databasePath: dbPath,
        issueType: issueType,
      );
      if (!host.mounted) return;
      if (proposals.isEmpty) {
        host.showSnack(
          'Δεν υπάρχουν ανοικτές προτάσεις για '
          '${lampDataIssueTypeDisplayLabel(issueType.issueType)}.',
        );
        return;
      }

      final proceed = await askResolutionPreview(issueType, proposals);
      if (proceed != true || !host.mounted) return;

      final mayRunDestructive = proposals.any(
        (proposal) =>
            proposalDefaultActionIsDestructive(proposal) ||
            proposalHasDestructiveOption(proposal),
      );
      if (mayRunDestructive) {
        final destructiveOk = await askDestructiveResolutionConfirmation();
        if (destructiveOk != true || !host.mounted) return;
      }

      final screenContext = host.context;
      if (!screenContext.mounted) return;

      final cancelToken = ResolutionCancelToken();
      final logController = ResolutionLogController();
      final apply = await showDialog<LampIssueResolutionApplyResult>(
        context: screenContext,
        barrierDismissible: false,
        builder: (dialogContext) => LampResolutionProgressDialog(
          title: issueType.label,
          logController: logController,
          cancelToken: cancelToken,
          apply: () => executeIssueResolutionOrchestration(
            dialogContext: dialogContext,
            databasePath: dbPath,
            issueType: issueType,
            proposals: proposals,
            logController: logController,
            cancelToken: cancelToken,
          ),
        ),
      );
      await host.loadIssues();
      if (!host.mounted) return;
      if (apply == null) {
        host.showSnack(
          'Η επίλυση δεν επέστρεψε τελικό αποτέλεσμα. Δείτε την αναφορά για λεπτομέρειες.',
          isError: true,
          duration: const Duration(seconds: 8),
        );
        return;
      }
      final errorSuffix = apply.errors.isEmpty
          ? ''
          : ' · Σφάλματα: ${apply.errors.length}';
      host.showSnack(
        'Επίλυση ${lampDataIssueTypeDisplayLabel(issueType.issueType)}: '
        'εφαρμόστηκαν ${apply.totalChanged} ενέργειες '
        '(auto: ${apply.resolved}, manual: ${apply.manualApplied}, νέες: ${apply.created})$errorSuffix.',
        isError: apply.errors.isNotEmpty,
        duration: const Duration(seconds: 8),
      );
    } catch (e) {
      if (!host.mounted) return;
      host.showSnack('Η επίλυση απέτυχε: $e', isError: true);
    } finally {
      if (host.mounted) {
        resolvingIssueType = null;
        host.notifyState();
      }
    }
  }

  bool proposalDefaultActionIsDestructive(
    LampIssueResolutionProposal proposal,
  ) {
    final operation = proposal.metadata['operation']?.toString();
    return operation != null && operation.startsWith('delete_duplicate');
  }

  bool proposalHasDestructiveOption(LampIssueResolutionProposal proposal) {
    for (final option in proposal.options) {
      final operation = option.metadata['operation']?.toString();
      if (operation != null && operation.startsWith('delete_duplicate')) {
        return true;
      }
    }
    return false;
  }

  LampIssueResolutionApplyResult emptyApplyResult() {
    return LampIssueResolutionApplyResult(
      resolved: 0,
      manualApplied: 0,
      created: 0,
      unresolved: 0,
      errors: <String>[],
    );
  }

  LampIssueResolutionApplyResult singleUnresolvedApplyResult() {
    return LampIssueResolutionApplyResult(
      resolved: 0,
      manualApplied: 0,
      created: 0,
      unresolved: 1,
      errors: <String>[],
    );
  }

  LampIssueResolutionApplyResult mergeApplyResults(
    LampIssueResolutionApplyResult a,
    LampIssueResolutionApplyResult b,
  ) {
    return LampIssueResolutionApplyResult(
      resolved: a.resolved + b.resolved,
      manualApplied: a.manualApplied + b.manualApplied,
      created: a.created + b.created,
      unresolved: a.unresolved + b.unresolved,
      errors: <String>[...a.errors, ...b.errors],
    );
  }

  Future<LampIssueResolutionApplyResult> executeIssueResolutionOrchestration({
    required BuildContext dialogContext,
    required String databasePath,
    required LampIssueType issueType,
    required List<LampIssueResolutionProposal> proposals,
    required ResolutionLogController logController,
    required ResolutionCancelToken cancelToken,
  }) async {
    var merged = emptyApplyResult();
    var skipRemainingUnresolved = false;

    void emit(ResolutionLogEntry entry) => logController.add(entry);

    emit(
      ResolutionLogEntry.info(
        'Σειριακή εκτέλεση ${proposals.length} προτάσεων: αυτόματες διορθώσεις '
        'όπου είναι διαθέσιμες και διάλογος χρήστη όπου απαιτείται απόφαση.',
      ),
    );

    for (final proposal in proposals) {
      if (cancelToken.isCancelled) {
        emit(
          ResolutionLogEntry.warning(
            'Η διαδικασία σταμάτησε πριν ολοκληρωθεί η σειρά προτάσεων.',
          ),
        );
        break;
      }
      if (!dialogContext.mounted) {
        break;
      }

      if (proposal.canApplyAutomatically) {
        final step = await host.shared.issueResolutionService.applySingleDecision(
          databasePath: databasePath,
          decision: LampIssueResolutionDecision(proposal: proposal),
          onLog: emit,
          cancelToken: cancelToken,
        );
        merged = mergeApplyResults(merged, step);
        continue;
      }

      if (proposal.proposedAction == LampIssueResolutionAction.manualReview) {
        final manualDecisions = await showLampIssueManualReviewDialog(
          context: dialogContext,
          issueType: issueType,
          proposals: <LampIssueResolutionProposal>[proposal],
        );
        if (!dialogContext.mounted) {
          break;
        }

        if (manualDecisions == null) {
          cancelToken.cancel();
          emit(
            ResolutionLogEntry.warning(
              'Ακυρώθηκε το χειροκίνητο βήμα — διακόπτεται η επίλυση.',
            ),
          );
          break;
        }
        if (manualDecisions.isEmpty) {
          emit(
            ResolutionLogEntry.info(
              'Παραβλήθηκε η χειροκίνητη πρόταση (γραμμή ${proposal.row ?? '-'}).',
            ),
          );
          continue;
        }

        for (final decision in manualDecisions) {
          final step = await host.shared.issueResolutionService.applySingleDecision(
            databasePath: databasePath,
            decision: decision,
            onLog: emit,
            cancelToken: cancelToken,
          );
          merged = mergeApplyResults(merged, step);
        }
        continue;
      }

      if (proposal.proposedAction == LampIssueResolutionAction.unresolved) {
        var shouldRecordUnresolved = true;
        if (!skipRemainingUnresolved) {
          final outcome = await showLampUnresolvedResolutionDialog(
            context: dialogContext,
            proposal: proposal,
          );
          if (!dialogContext.mounted) {
            break;
          }
          switch (outcome) {
            case null:
            case LampUnresolvedCancelAll():
              cancelToken.cancel();
              shouldRecordUnresolved = false;
              emit(
                ResolutionLogEntry.warning(
                  'Ακυρώθηκε η διαδικασία κατά την επισκόπηση ανεπίλυτων προτάσεων.',
                ),
              );
              break;
            case LampUnresolvedSkipAll():
              skipRemainingUnresolved = true;
              emit(
                ResolutionLogEntry.info(
                  'Ο χρήστης επέλεξε μαζική παράλειψη για τις υπόλοιπες ανεπίλυτες προτάσεις.',
                ),
              );
              emit(
                ResolutionLogEntry.info(
                  'Παραλείφθηκε ανεπίλυτη πρόταση στη γραμμή ${proposal.row ?? '-'} '
                  '(στήλη ${proposal.column ?? '-'}).',
                ),
              );
              break;
            case LampUnresolvedSkipCurrent():
              emit(
                ResolutionLogEntry.info(
                  'Παραλείφθηκε ανεπίλυτη πρόταση στη γραμμή ${proposal.row ?? '-'} '
                  '(στήλη ${proposal.column ?? '-'}).',
                ),
              );
              break;
          }
        } else {
          emit(
            ResolutionLogEntry.info(
              'Μαζική παράλειψη ανεπίλυτης πρότασης στη γραμμή ${proposal.row ?? '-'} '
              '(στήλη ${proposal.column ?? '-'}).',
            ),
          );
        }
        if (shouldRecordUnresolved) {
          merged = mergeApplyResults(merged, singleUnresolvedApplyResult());
        }
      }
    }

    if (cancelToken.isCancelled) {
      emit(
        ResolutionLogEntry.warning(
          'Παραλείφθηκαν τα υπόλοιπα βήματα λόγω ακύρωσης.',
        ),
      );
    }
    return merged;
  }

  Future<bool?> askDestructiveResolutionConfirmation() {
    return showDialog<bool>(
      context: host.context,
      builder: (context) => AlertDialog(
        title: const Text('Επιβεβαίωση διαγραφής διπλοεγγραφών'),
        content: const Text(
          'Έχετε επιλέξει ενέργεια που διαγράφει δευτερεύουσες εγγραφές εξοπλισμού. '
          'Πριν τη διαγραφή θα μεταφερθούν τυχόν παιδιά του δείκτη κύριου εξοπλισμού '
          'στην κύρια εγγραφή, αλλά η ενέργεια δεν έχει άμεση αναίρεση από την εφαρμογή. '
          'Θέλετε να συνεχίσετε;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Συνέχεια με διαγραφή'),
          ),
        ],
      ),
    );
  }

  String issueColumnDisplayForPreview(String? column) {
    if (column == null || column.isEmpty) return '-';
    switch (column.trim().toLowerCase()) {
      case 'office':
        return 'γραφείο';
      case 'owner':
        return 'υπάλληλος';
      case 'model':
        return 'μοντέλο';
      case 'contract':
        return 'συμβόλαιο';
      case 'set_master':
        return 'κύριος εξοπλισμός';
      default:
        return column;
    }
  }

  Future<bool?> askResolutionPreview(
    LampIssueType issueType,
    List<LampIssueResolutionProposal> proposals,
  ) {
    final autoCount = proposals
        .where((p) => p.proposedAction == LampIssueResolutionAction.autoFix)
        .length;
    final createCount = proposals
        .where((p) => p.proposedAction == LampIssueResolutionAction.createNew)
        .length;
    final manualCount = proposals
        .where(
          (p) => p.proposedAction == LampIssueResolutionAction.manualReview,
        )
        .length;
    final unresolvedCount = proposals
        .where((p) => p.proposedAction == LampIssueResolutionAction.unresolved)
        .length;
    final applicableCount = autoCount + createCount + manualCount;
    final preview = proposals
        .take(8)
        .map(
          (p) =>
              '- γραμμή=${p.row ?? '-'} στήλη=${issueColumnDisplayForPreview(p.column)} · '
              '${p.proposedAction.labelEl} · ${p.proposedMatch ?? p.notes}',
        )
        .join('\n');
    return showDialog<bool>(
      context: host.context,
      builder: (context) => AlertDialog(
        title: Text(issueType.label),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  'Βρέθηκαν ${proposals.length} προτάσεις.\n\n'
                  '- Αυτόματη διόρθωση: $autoCount\n'
                  '- Νέα εγγραφή: $createCount\n'
                  '- Χειροκίνητη επισκόπηση: $manualCount\n'
                  '- Ανεπίλυτο: $unresolvedCount\n\n'
                  'Δείγμα:\n$preview'
                  '${proposals.length > 8 ? '\n...και ${proposals.length - 8} ακόμα.' : ''}\n\n'
                  'Οι ενέργειες αυτόματης διόρθωσης και νέας εγγραφής θα εφαρμοστούν μόνο μετά '
                  'από αυτή την επιβεβαίωση. Οι περιπτώσεις χειροκίνητης ή ανεπίλυτης '
                  'επισκόπησης θα ανοίξουν σειριακά σε επόμενα παράθυρα επιλογών.',
                ),
                if (applicableCount == 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Οι προτάσεις αυτής της ομάδας είναι μόνο «ανεπίλυτο». Η «Συνέχεια» '
                    'θα ανοίξει τον οδηγό επίλυσης για επισκόπηση, χωρίς αυτόματες αλλαγές.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
  }
}
