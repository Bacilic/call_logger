part of 'lansweeper_report_dialog.dart';

mixin LansweeperReportBrowserMixin on LansweeperReportDialogStateHost {
  Future<({bool opened, bool openedLoginTab})> _launchHelpdeskBrowserUrl(
    String targetUrl, {
    required String invalidUrlMessage,
    required String openFailureMessage,
  }) async {
    if (!LansweeperUrlRules.isBrowserLaunchableUrl(targetUrl)) {
      if (mounted) {
        _showDialogSnackBar(SnackBar(content: Text(openFailureMessage)));
      }
      return (opened: false, openedLoginTab: false);
    }

    final autoLogin = ref.read(lansweeperHelpdeskAutoLoginProvider);
    final loginPageRaw = ref.read(lansweeperHelpdeskLoginUrlProvider).trim();
    var openedLoginTab = false;
    if (autoLogin &&
        LansweeperUrlRules.isBrowserLaunchableUrl(loginPageRaw)) {
      final loginUri = Uri.tryParse(loginPageRaw);
      if (loginUri != null && loginUri.hasScheme) {
        openedLoginTab = await launchUrl(
          loginUri,
          mode: LaunchMode.externalApplication,
        );
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }

    final uri = Uri.tryParse(targetUrl.trim());
    if (uri == null || !uri.hasScheme) {
      if (mounted) {
        _showDialogSnackBar(SnackBar(content: Text(invalidUrlMessage)));
      }
      return (opened: false, openedLoginTab: openedLoginTab);
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showDialogSnackBar(SnackBar(content: Text(openFailureMessage)));
    }
    return (opened: opened, openedLoginTab: openedLoginTab);
  }

  @override
  Future<void> _openTicketViewInBrowser(String ticketId) async {
    final templateRaw = _lansweeperTicketViewUrlController.text.trim();
    final template = templateRaw.isNotEmpty
        ? templateRaw
        : ref.read(lansweeperTicketViewUrlProvider);
    final url = LansweeperUrlRules.buildTicketViewUrl(template, ticketId);
    if (url == null) {
      if (!mounted) return;
      _showDialogSnackBar(
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
    if (!mounted) return;
    if (result.openedLoginTab) {
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ανοίχτηκαν καρτέλες στον περιηγητή· αν χρειάζεται, συνδεθείτε στη σελίδα σύνδεσης και επιστρέψτε στο ticket.',
          ),
        ),
      );
    } else if (!result.opened) {
      _showDialogSnackBar(
        const SnackBar(
          content: Text('Αποτυχία ανοίγματος ticket στον περιηγητή.'),
        ),
      );
    }
  }

  Future<void> _copyAndOpen({
    required String ticketFormUrl,
    int? durationSeconds,
  }) async {
    if (!LansweeperUrlRules.isBrowserLaunchableUrl(ticketFormUrl)) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε έγκυρο URL φόρμας νέου αιτήματος στις ρυθμίσεις Lansweeper.',
          ),
        ),
      );
      return;
    }

    final title = _titleController.text.trim();
    final notes = _notesController.text.trim();
    final solution = _solutionController.text.trim();
    final description = LansweeperSyncService.buildTicketDescription(
      notes: notes,
      solution: solution,
      durationSeconds: durationSeconds,
    );
    final clipboardParts = <String>[
      if (title.isNotEmpty) title,
      if (description.isNotEmpty) description,
    ];
    await Clipboard.setData(
      ClipboardData(text: clipboardParts.join('\n\n')),
    );

    if (!mounted) return;
    _showDialogSnackBar(
      const SnackBar(
        content: Text('Αντιγράφηκαν τίτλος, σημειώσεις και λύση.'),
      ),
    );

    final result = await _launchHelpdeskBrowserUrl(
      ticketFormUrl,
      invalidUrlMessage: 'Μη έγκυρο URL φόρμας εισιτηρίου.',
      openFailureMessage: 'Αποτυχία ανοίγματος URL φόρμας.',
    );
    if (mounted && result.openedLoginTab) {
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ανοίχτηκαν καρτέλες στον περιηγητή· αν χρειάζεται, συνδεθείτε στη σελίδα σύνδεσης και επιστρέψτε στη φόρμα αιτήματος.',
          ),
        ),
      );
    }
  }
}
