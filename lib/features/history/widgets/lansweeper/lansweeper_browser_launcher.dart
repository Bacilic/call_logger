import 'lansweeper_url_rules.dart';

typedef LansweeperUrlLauncher = Future<bool> Function(Uri uri);

enum LansweeperBrowserLaunchOutcome { notLaunchable, openFailed, opened }

class LansweeperBrowserLaunchResult {
  const LansweeperBrowserLaunchResult({
    required this.opened,
    required this.outcome,
  });

  final bool opened;
  final LansweeperBrowserLaunchOutcome outcome;
}

/// Επικυρώνει και ανοίγει URL του Help Desk στον εξωτερικό περιηγητή.
///
/// Το Lansweeper αναλαμβάνει μόνο του τη σύνδεση: αποσυνδεδεμένος χρήστης
/// ανακατευθύνεται στο login και μετά επιστρέφει στη σελίδα που ζήτησε.
class LansweeperBrowserLauncher {
  LansweeperBrowserLauncher({required this.launch});

  final LansweeperUrlLauncher launch;

  Future<LansweeperBrowserLaunchResult> launchTarget(String targetUrl) async {
    if (!LansweeperUrlRules.isBrowserLaunchableUrl(targetUrl)) {
      return const LansweeperBrowserLaunchResult(
        opened: false,
        outcome: LansweeperBrowserLaunchOutcome.notLaunchable,
      );
    }

    final uri = Uri.parse(targetUrl.trim());
    final opened = await launch(uri);
    return LansweeperBrowserLaunchResult(
      opened: opened,
      outcome: opened
          ? LansweeperBrowserLaunchOutcome.opened
          : LansweeperBrowserLaunchOutcome.openFailed,
    );
  }
}
