import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/features/database/services/database_path_switch_runner.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHooks implements DatabasePathSwitchHooks {
  final List<String> calls = <String>[];
  int applyCallCount = 0;
  int reportCallCount = 0;
  String? appliedPath;
  DatabaseInitRunnerResult? reportedRunner;

  @override
  void declareSwitchBegin() => calls.add('declareSwitchBegin');

  @override
  void declareSwitchEnd() => calls.add('declareSwitchEnd');

  @override
  Future<void> showVerifyingIndicator() async {
    calls.add('showVerifyingIndicator');
  }

  @override
  Future<void> hideVerifyingIndicator() async {
    calls.add('hideVerifyingIndicator');
  }

  @override
  Future<void> reportVerificationFailure(DatabaseInitRunnerResult runner) async {
    calls.add('reportVerificationFailure');
    reportCallCount++;
    reportedRunner = runner;
  }

  @override
  Future<void> applySwitchToSession(String path) async {
    calls.add('applySwitchToSession');
    applyCallCount++;
    appliedPath = path;
  }
}

void main() {
  const path = r'C:\data\call_logger.db';

  test(
    'αποτυχημένη επαλήθευση: δεν καλεί applySwitchToSession και επιστρέφει false',
    () async {
      final hooks = _FakeHooks();
      final runner = DatabaseInitRunnerResult(
        result: DatabaseInitResult.fileNotFound(path),
        isLocalDevMode: false,
      );

      final ok = await runDatabasePathSwitch(
        path: path,
        hooks: hooks,
        verify: (_) async => (ok: false, runner: runner),
      );

      expect(ok, isFalse);
      expect(hooks.applyCallCount, 0);
      expect(hooks.reportCallCount, 1);
      expect(hooks.reportedRunner, same(runner));
    },
  );

  test(
    'επιτυχημένη επαλήθευση: καλεί applySwitchToSession μία φορά και επιστρέφει true',
    () async {
      final hooks = _FakeHooks();
      final runner = DatabaseInitRunnerResult(
        result: DatabaseInitResult.success(path),
        isLocalDevMode: false,
      );

      final ok = await runDatabasePathSwitch(
        path: path,
        hooks: hooks,
        verify: (_) async => (ok: true, runner: runner),
      );

      expect(ok, isTrue);
      expect(hooks.applyCallCount, 1);
      expect(hooks.appliedPath, path);
      expect(hooks.reportCallCount, 0);
    },
  );

  test(
    'εξαίρεση επαληθευτή: hide + declareSwitchEnd τρέχουν, apply όχι, εξαίρεση προωθείται',
    () async {
      final hooks = _FakeHooks();

      await expectLater(
        () => runDatabasePathSwitch(
          path: path,
          hooks: hooks,
          verify: (_) async => throw StateError('verify blew up'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(hooks.calls, contains('hideVerifyingIndicator'));
      expect(hooks.calls, contains('declareSwitchEnd'));
      expect(hooks.applyCallCount, 0);
    },
  );

  test(
    'επιτυχής σειρά κλήσεων: begin → show → hide → apply → end',
    () async {
      final hooks = _FakeHooks();
      final runner = DatabaseInitRunnerResult(
        result: DatabaseInitResult.success(path),
        isLocalDevMode: false,
      );

      await runDatabasePathSwitch(
        path: path,
        hooks: hooks,
        verify: (_) async => (ok: true, runner: runner),
      );

      expect(hooks.calls, [
        'declareSwitchBegin',
        'showVerifyingIndicator',
        'hideVerifyingIndicator',
        'applySwitchToSession',
        'declareSwitchEnd',
      ]);
    },
  );
}
