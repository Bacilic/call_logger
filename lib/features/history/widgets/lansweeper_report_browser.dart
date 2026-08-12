import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/lansweeper_sync_service.dart';
import '../providers/lansweeper_settings_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import 'lansweeper/lansweeper_ai_presenter.dart';
import 'lansweeper/lansweeper_browser_launcher.dart';
import 'lansweeper/lansweeper_url_rules.dart';
import 'lansweeper_report_dialog.dart';

/// Άνοιγμα σελίδων Lansweeper στον περιηγητή (ticket, φόρμα).
///
/// Συνεργάτης του [LansweeperReportDialogState] (Σύνθεση).
class LansweeperReportBrowser {
  LansweeperReportBrowser(this.host);

  final LansweeperReportDialogState host;

  Future<bool> _launchHelpdeskBrowserUrl(
    String targetUrl, {
    required String invalidUrlMessage,
    required String openFailureMessage,
  }) async {
    final launcher = LansweeperBrowserLauncher(
      launch: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    );

    final result = await launcher.launchTarget(targetUrl);

    switch (result.outcome) {
      case LansweeperBrowserLaunchOutcome.notLaunchable:
        if (host.mounted) {
          host.showDialogSnackBar(SnackBar(content: Text(invalidUrlMessage)));
        }

      case LansweeperBrowserLaunchOutcome.openFailed:
        if (host.mounted) {
          host.showDialogSnackBar(SnackBar(content: Text(openFailureMessage)));
        }

      case LansweeperBrowserLaunchOutcome.opened:
        break;
    }

    return result.opened;
  }

  Future<void> openTicketViewInBrowser(String ticketId) async {
    final templateRaw = host.lansweeperTicketViewUrlController.text.trim();

    final template = templateRaw.isNotEmpty
        ? templateRaw
        : host.ref.read(lansweeperTicketViewUrlProvider);

    final url = LansweeperUrlRules.buildTicketViewUrl(template, ticketId);

    if (url == null) {
      if (!host.mounted) return;

      host.showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε έγκυρο URL προβολής ticket στις ρυθμίσεις Lansweeper.',
          ),
        ),
      );

      return;
    }

    await _launchHelpdeskBrowserUrl(
      url,

      invalidUrlMessage: 'Μη έγκυρο URL προβολής ticket.',

      openFailureMessage: 'Αποτυχία ανοίγματος ticket στον περιηγητή.',
    );
  }

  Future<void> copyAndOpen({
    required String ticketFormUrl,
    required List<int> callIds,
    int? durationSeconds,
  }) async {
    if (!LansweeperUrlRules.isBrowserLaunchableUrl(ticketFormUrl)) {
      if (!host.mounted) return;

      host.showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε έγκυρο URL φόρμας νέου αιτήματος στις ρυθμίσεις Lansweeper.',
          ),
        ),
      );

      return;
    }

    final title = host.titleController.text.trim();

    final notes = host.notesController.text.trim();

    final solution = host.solutionController.text.trim();

    final description = LansweeperSyncService.buildTicketDescription(
      notes: notes,

      solution: solution,

      durationSeconds: durationSeconds,
    );

    final clipboardParts = <String>[
      if (title.isNotEmpty) title,

      if (description.isNotEmpty) description,
    ];

    // Πρώτα η εγγραφή, μετά το πρόχειρο: το κείμενο φεύγει σε λίγο στον
    // περιηγητή και η εφαρμογή δεν το ξαναβλέπει. Η σειρά δεν είναι θέμα
    // γούστου — μετά το πρώτο `await` ο διάλογος μπορεί να έχει κλείσει, οπότε
    // η εγγραφή θα έχανε το `ref` και μαζί ολόκληρη τη δουλειά του καθαρισμού.
    await host.ref
        .read(lansweeperSyncProvider.notifier)
        .persistRefinedTexts(
          callIds: callIds,
          problem: notes,
          solution: solution,
          source: LansweeperAiPresenter.refinedSource(
            aiProblem: host.aiSuggestedNotes,
            aiSolution: host.aiSuggestedSolution,
            problem: notes,
            solution: solution,
          ),
        );

    await Clipboard.setData(ClipboardData(text: clipboardParts.join('\n\n')));

    if (!host.mounted) return;

    host.showDialogSnackBar(
      const SnackBar(
        content: Text('Αντιγράφηκαν τίτλος, σημειώσεις και λύση.'),
      ),
    );

    await _launchHelpdeskBrowserUrl(
      ticketFormUrl,

      invalidUrlMessage: 'Μη έγκυρο URL φόρμας εισιτηρίου.',

      openFailureMessage: 'Αποτυχία ανοίγματος URL φόρμας.',
    );
  }
}
