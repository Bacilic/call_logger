import 'lansweeper_url_rules.dart';

typedef LansweeperUrlLauncher = Future<bool> Function(Uri uri);

enum LansweeperBrowserLaunchOutcome {
  notLaunchable,
  invalidTarget,
  openFailed,
  opened,
}

class LansweeperBrowserLaunchResult {
  const LansweeperBrowserLaunchResult({
    required this.opened,
    required this.openedLoginTab,
    required this.outcome,
  });

  final bool opened;
  final bool openedLoginTab;
  final LansweeperBrowserLaunchOutcome outcome;
}

class LansweeperBrowserLauncher {
  LansweeperBrowserLauncher({
    required this.launch,
    this.loginSettleDelay = const Duration(milliseconds: 450),
    Future<void> Function(Duration duration)? sleep,
  }) : sleep = sleep ?? ((Duration duration) => Future<void>.delayed(duration));

  final LansweeperUrlLauncher launch;
  final Duration loginSettleDelay;
  final Future<void> Function(Duration duration) sleep;

  Future<LansweeperBrowserLaunchResult> launchWithOptionalLogin({
    required String targetUrl,
    required bool autoLogin,
    required String loginUrl,
  }) async {
    if (!LansweeperUrlRules.isBrowserLaunchableUrl(targetUrl)) {
      return const LansweeperBrowserLaunchResult(
        opened: false,
        openedLoginTab: false,
        outcome: LansweeperBrowserLaunchOutcome.notLaunchable,
      );
    }

    var openedLoginTab = false;
    final loginPageRaw = loginUrl.trim();
    if (autoLogin &&
        LansweeperUrlRules.isBrowserLaunchableUrl(loginPageRaw)) {
      final loginUri = Uri.tryParse(loginPageRaw);
      if (loginUri != null && loginUri.hasScheme) {
        openedLoginTab = await launch(loginUri);
        await sleep(loginSettleDelay);
      }
    }

    final uri = Uri.tryParse(targetUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return LansweeperBrowserLaunchResult(
        opened: false,
        openedLoginTab: openedLoginTab,
        outcome: LansweeperBrowserLaunchOutcome.invalidTarget,
      );
    }

    final opened = await launch(uri);
    return LansweeperBrowserLaunchResult(
      opened: opened,
      openedLoginTab: openedLoginTab,
      outcome: opened
          ? LansweeperBrowserLaunchOutcome.opened
          : LansweeperBrowserLaunchOutcome.openFailed,
    );
  }
}
