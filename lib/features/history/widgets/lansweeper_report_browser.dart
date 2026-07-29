import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/lansweeper_sync_service.dart';
import '../providers/lansweeper_settings_provider.dart';
import 'lansweeper/lansweeper_browser_launcher.dart';
import 'lansweeper/lansweeper_url_rules.dart';
import 'lansweeper_report_dialog.dart';

/// Άνοιγμα σελίδων Lansweeper στον περιηγητή (ticket, φόρμα, προαιρετικό login).
///
/// Συνεργάτης του [LansweeperReportDialogState] (Σύνθεση).
class LansweeperReportBrowser {
  LansweeperReportBrowser(this.host);

  final LansweeperReportDialogState host;

  Future<({bool opened, bool openedLoginTab})> _launchHelpdeskBrowserUrl(
    String targetUrl, {
    required String invalidUrlMessage,
    required String openFailureMessage,
  }) async {
    final autoLogin = host.ref.read(lansweeperHelpdeskAutoLoginProvider);

    final loginPageRaw = host.ref.read(lansweeperHelpdeskLoginUrlProvider);

    final launcher = LansweeperBrowserLauncher(
      launch: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    );

    final result = await launcher.launchWithOptionalLogin(
      targetUrl: targetUrl,

      autoLogin: autoLogin,

      loginUrl: loginPageRaw,
    );

    switch (result.outcome) {
      case LansweeperBrowserLaunchOutcome.notLaunchable:
      case LansweeperBrowserLaunchOutcome.openFailed:
        if (host.mounted) {
          host.showDialogSnackBar(SnackBar(content: Text(openFailureMessage)));
        }

      case LansweeperBrowserLaunchOutcome.invalidTarget:
        if (host.mounted) {
          host.showDialogSnackBar(SnackBar(content: Text(invalidUrlMessage)));
        }

      case LansweeperBrowserLaunchOutcome.opened:
        break;
    }

    return (opened: result.opened, openedLoginTab: result.openedLoginTab);
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

    final result = await _launchHelpdeskBrowserUrl(
      url,

      invalidUrlMessage: 'Μη έγκυρο URL προβολής ticket.',

      openFailureMessage: 'Αποτυχία ανοίγματος ticket στον περιηγητή.',
    );

    if (!host.mounted) return;

    if (result.openedLoginTab) {
      host.showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ανοίχτηκαν καρτέλες στον περιηγητή· αν χρειάζεται, συνδεθείτε στη σελίδα σύνδεσης και επιστρέψτε στο ticket.',
          ),
        ),
      );
    } else if (!result.opened) {
      host.showDialogSnackBar(
        const SnackBar(
          content: Text('Αποτυχία ανοίγματος ticket στον περιηγητή.'),
        ),
      );
    }
  }

  Future<void> copyAndOpen({
    required String ticketFormUrl,
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

    await Clipboard.setData(ClipboardData(text: clipboardParts.join('\n\n')));

    if (!host.mounted) return;

    host.showDialogSnackBar(
      const SnackBar(
        content: Text('Αντιγράφηκαν τίτλος, σημειώσεις και λύση.'),
      ),
    );

    final result = await _launchHelpdeskBrowserUrl(
      ticketFormUrl,

      invalidUrlMessage: 'Μη έγκυρο URL φόρμας εισιτηρίου.',

      openFailureMessage: 'Αποτυχία ανοίγματος URL φόρμας.',
    );

    if (host.mounted && result.openedLoginTab) {
      host.showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ανοίχτηκαν καρτέλες στον περιηγητή· αν χρειάζεται, συνδεθείτε στη σελίδα σύνδεσης και επιστρέψτε στη φόρμα αιτήματος.',
          ),
        ),
      );
    }
  }
}
