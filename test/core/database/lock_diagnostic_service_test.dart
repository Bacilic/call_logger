// Το διαγνωστικό κλειδώματος δεν ενώνει ποτέ διαδρομή μέσα σε εντολή.
//
// Ως τις 02/10/2026 η διαδρομή της βάσης γραφόταν μέσα στο κείμενο μιας
// εντολής PowerShell, με διαφυγή που μάλιστα διπλασίαζε τις ανάποδες
// καθέτους — ο έλεγχος έψαχνε κάτι που δεν υπάρχει και απαντούσε πάντα «δεν
// εντοπίστηκε». Τώρα το σενάριο είναι σταθερό και οι διαδρομές φτάνουν ως
// δεδομένα.
//
//   flutter test test/core/database/lock_diagnostic_service_test.dart

import 'dart:convert';

import 'package:call_logger/core/database/lock_diagnostic_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

String _decodedScript() {
  final args = LockDiagnosticService.powerShellArguments();
  final encoded = args[args.indexOf('-EncodedCommand') + 1];
  final bytes = base64.decode(encoded);
  final units = <int>[
    for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
  ];
  return String.fromCharCodes(units);
}

void main() {
  const hostile = r"C:\Temp\O'Brien & Co\$x\Hospital.db";

  test('η διαδρομή δεν εμφανίζεται πουθενά στην εντολή', () {
    final args = LockDiagnosticService.powerShellArguments();

    expect(
      args.any((a) => a.contains('Hospital.db')) ||
          _decodedScript().contains('Hospital.db'),
      isFalse,
      reason: greekExpectMsg(
        'Το σενάριο είναι σταθερό — η διαδρομή δεν μπορεί να γίνει εντολή',
      ),
    );
  });

  test('η διαδρομή φτάνει αυτούσια, χωρίς διαφυγή', () {
    final env = LockDiagnosticService.powerShellEnvironment([
      hostile,
      '$hostile-wal',
    ]);

    expect(
      env[LockDiagnosticService.targetsEnvironmentVariable]!.split('\n'),
      [hostile, '$hostile-wal'],
      reason: greekExpectMsg(
        'Ούτε διπλασιασμένες κάθετοι ούτε διπλά εισαγωγικά: ο έλεγχος '
        'ψάχνει ακριβώς τη διαδρομή της βάσης',
      ),
    );
  });

  test('το σενάριο διαβάζει τις διαδρομές από το ίδιο περιβάλλον', () {
    expect(
      _decodedScript(),
      contains('\$env:${LockDiagnosticService.targetsEnvironmentVariable}'),
    );
  });
}
