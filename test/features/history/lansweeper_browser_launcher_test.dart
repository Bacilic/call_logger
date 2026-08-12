// Unit test: LansweeperBrowserLauncher — καθαρή λογική ανοίγματος περιηγητή.
//
//   flutter test test/features/history/lansweeper_browser_launcher_test.dart

import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_browser_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

const _validTarget = 'https://helpdesk.example.com/ticket/new';

class _RecordingLauncher {
  _RecordingLauncher({this.targetResult = true});

  final List<Uri> launched = <Uri>[];
  final bool targetResult;

  Future<bool> call(Uri uri) async {
    launched.add(uri);
    return targetResult;
  }
}

void main() {
  group('LansweeperBrowserLauncher.launchTarget', () {
    test(
      'μη-launchable target -> notLaunchable και ο launcher ΔΕΝ κλήθηκε',
      () async {
        final recorder = _RecordingLauncher();
        final launcher = LansweeperBrowserLauncher(launch: recorder.call);

        final result = await launcher.launchTarget('not-a-url');

        expect(result.outcome, LansweeperBrowserLaunchOutcome.notLaunchable);
        expect(result.opened, isFalse);
        expect(recorder.launched, isEmpty);
      },
    );

    test('launch target επιστρέφει false -> openFailed', () async {
      final recorder = _RecordingLauncher(targetResult: false);
      final launcher = LansweeperBrowserLauncher(launch: recorder.call);

      final result = await launcher.launchTarget(_validTarget);

      expect(result.outcome, LansweeperBrowserLaunchOutcome.openFailed);
      expect(result.opened, isFalse);
    });

    test('επιτυχία -> outcome opened, ΜΙΑ κλήση με το target', () async {
      final recorder = _RecordingLauncher(targetResult: true);
      final launcher = LansweeperBrowserLauncher(launch: recorder.call);

      final result = await launcher.launchTarget(_validTarget);

      expect(recorder.launched, hasLength(1));
      expect(recorder.launched.single.toString(), _validTarget);
      expect(result.outcome, LansweeperBrowserLaunchOutcome.opened);
      expect(result.opened, isTrue);
    });
  });
}
