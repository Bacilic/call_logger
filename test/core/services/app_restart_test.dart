// Unit tests: η επανεκκίνηση περνά από το κανονικό κλείσιμο, και η νέα
// εφαρμογή ξεκινά αφού τελειώσει η παλιά.
//
//   flutter test test/core/services/app_restart_test.dart

import 'package:call_logger/core/config/app_config.dart';
import 'package:call_logger/core/services/app_restart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ορίσματα της νέας εφαρμογής', () {
    test('κρατά το προφίλ και προσθέτει «περίμενε την παλιά»', () {
      expect(relaunchArguments(const ['--profile', 'dev'], processId: 4321), [
        '--profile',
        'dev',
        '--after-exit-of=4321',
      ]);
    });

    test('δεν κουβαλά την αναμονή μιας προηγούμενης επανεκκίνησης', () {
      expect(relaunchArguments(const ['--after-exit-of=11'], processId: 22), [
        '--after-exit-of=22',
      ]);
    });

    test('η οδηγία αναμονής γίνεται δεκτή στην εκκίνηση', () {
      final parsed = AppConfig.validateCliArguments(const [
        '--profile',
        'dev',
        '--after-exit-of=4321',
      ]);
      expect(parsed.isValid, isTrue);
      expect(parsed.profile, 'dev');
      expect(parsed.waitForProcessId, 4321);
    });

    test('αλλοιωμένη οδηγία αναμονής είναι άκυρο όρισμα', () {
      expect(
        AppConfig.validateCliArguments(const ['--after-exit-of=x']).isValid,
        isFalse,
      );
    });
  });

  group('αναμονή της παλιάς εφαρμογής', () {
    test('περιμένει όσο ζει και συνεχίζει μόλις κλείσει', () async {
      var checks = 0;
      final gone = await waitUntilProcessGone(
        4321,
        isAlive: (_) => ++checks < 3,
        delay: (_) async {},
      );
      expect(gone, isTrue);
      expect(checks, 3);
    });

    test('δεν κρατά την εκκίνηση για πάντα: συνεχίζει μετά το όριο', () async {
      var waited = Duration.zero;
      final gone = await waitUntilProcessGone(
        4321,
        isAlive: (_) => true,
        timeout: const Duration(seconds: 30),
        pollInterval: const Duration(milliseconds: 200),
        delay: (d) async => waited += d,
      );
      expect(gone, isFalse);
      expect(waited, const Duration(seconds: 30));
    });
  });
}
