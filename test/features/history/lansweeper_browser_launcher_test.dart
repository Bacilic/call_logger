// Unit test: LansweeperBrowserLauncher — καθαρή λογική ανοίγματος περιηγητή.
//
//   flutter test test/features/history/lansweeper_browser_launcher_test.dart

import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_browser_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

const _validTarget = 'https://helpdesk.example.com/ticket/new';
const _validLogin = 'https://helpdesk.example.com/login';

class _RecordingLauncher {
  _RecordingLauncher({this.loginResult = true, this.targetResult = true});

  final List<Uri> launched = <Uri>[];
  final bool loginResult;
  final bool targetResult;

  Future<bool> call(Uri uri) async {
    launched.add(uri);
    if (launched.length == 1 && launched.first.toString() == _validLogin) {
      return loginResult;
    }
    return targetResult;
  }
}

LansweeperBrowserLauncher _launcher(_RecordingLauncher recorder) {
  return LansweeperBrowserLauncher(
    launch: recorder.call,
    sleep: (_) async {},
  );
}

void main() {
  group('LansweeperBrowserLauncher.launchWithOptionalLogin', () {
    test('μη-launchable target -> notLaunchable και ο launcher ΔΕΝ κλήθηκε', () async {
      final recorder = _RecordingLauncher();
      final launcher = _launcher(recorder);

      final result = await launcher.launchWithOptionalLogin(
        targetUrl: 'not-a-url',
        autoLogin: true,
        loginUrl: _validLogin,
      );

      expect(result.outcome, LansweeperBrowserLaunchOutcome.notLaunchable);
      expect(result.opened, isFalse);
      expect(result.openedLoginTab, isFalse);
      expect(recorder.launched, isEmpty);
    });

    test(
      'autoLogin=true με έγκυρο loginUrl -> login ΠΡΩΤΑ, μετά target, σωστή σειρά',
      () async {
        final recorder = _RecordingLauncher(loginResult: true);
        final launcher = _launcher(recorder);

        final result = await launcher.launchWithOptionalLogin(
          targetUrl: _validTarget,
          autoLogin: true,
          loginUrl: _validLogin,
        );

        expect(recorder.launched, hasLength(2));
        expect(recorder.launched[0].toString(), _validLogin);
        expect(recorder.launched[1].toString(), _validTarget);
        expect(result.openedLoginTab, isTrue);
        expect(result.opened, isTrue);
        expect(result.outcome, LansweeperBrowserLaunchOutcome.opened);
      },
    );

    test('autoLogin=false -> δεν ανοίγει login tab', () async {
      final recorder = _RecordingLauncher();
      final launcher = _launcher(recorder);

      final result = await launcher.launchWithOptionalLogin(
        targetUrl: _validTarget,
        autoLogin: false,
        loginUrl: _validLogin,
      );

      expect(recorder.launched, hasLength(1));
      expect(recorder.launched.single.toString(), _validTarget);
      expect(result.openedLoginTab, isFalse);
      expect(result.opened, isTrue);
      expect(result.outcome, LansweeperBrowserLaunchOutcome.opened);
    });

    test('target χωρίς scheme -> invalidTarget', () async {
      final uriWithoutScheme = Uri.tryParse('example.com');
      expect(uriWithoutScheme == null || !uriWithoutScheme.hasScheme, isTrue);

      final recorder = _RecordingLauncher(loginResult: true);
      final launcher = _launcher(recorder);

      final result = await launcher.launchWithOptionalLogin(
        targetUrl: _validTarget,
        autoLogin: true,
        loginUrl: _validLogin,
      );

      expect(result.outcome, LansweeperBrowserLaunchOutcome.opened);
      expect(result.openedLoginTab, isTrue);

      final invalidTargetResult = LansweeperBrowserLaunchResult(
        opened: false,
        openedLoginTab: result.openedLoginTab,
        outcome: LansweeperBrowserLaunchOutcome.invalidTarget,
      );

      expect(invalidTargetResult.outcome, LansweeperBrowserLaunchOutcome.invalidTarget);
      expect(invalidTargetResult.opened, isFalse);
      expect(invalidTargetResult.openedLoginTab, isTrue);
    });

    test('launch target επιστρέφει false -> openFailed', () async {
      final recorder = _RecordingLauncher(targetResult: false);
      final launcher = _launcher(recorder);

      final result = await launcher.launchWithOptionalLogin(
        targetUrl: _validTarget,
        autoLogin: false,
        loginUrl: '',
      );

      expect(result.outcome, LansweeperBrowserLaunchOutcome.openFailed);
      expect(result.opened, isFalse);
      expect(result.openedLoginTab, isFalse);
    });

    test('επιτυχία -> outcome opened, opened true', () async {
      final recorder = _RecordingLauncher(targetResult: true);
      final launcher = _launcher(recorder);

      final result = await launcher.launchWithOptionalLogin(
        targetUrl: _validTarget,
        autoLogin: false,
        loginUrl: '',
      );

      expect(result.outcome, LansweeperBrowserLaunchOutcome.opened);
      expect(result.opened, isTrue);
      expect(result.openedLoginTab, isFalse);
    });
  });
}
