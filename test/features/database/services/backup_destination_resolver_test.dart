// Η επικύρωση του φακέλου προορισμού, χωρίς οθόνη.
//
// Πριν τη διάσπαση η λογική ζούσε μέσα στην καρτέλα και δεν μπορούσε να
// ελεγχθεί καθόλου: ο μόνος τρόπος να δεις τι κάνει ήταν να την πατήσεις.
//
//   flutter test test/features/database/services/backup_destination_resolver_test.dart

import 'dart:io';

import 'package:call_logger/features/database/services/backup_destination_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

late Directory _root;

/// Καταγράφει αν — και για ποια διαδρομή — ζητήθηκε άδεια δημιουργίας.
class _ConfirmSpy {
  _ConfirmSpy(this.answer);

  final bool answer;
  final List<String> asked = [];

  Future<bool> call(String folderPath) async {
    asked.add(folderPath);
    return answer;
  }
}

void main() {
  setUp(() => _root = Directory.systemTemp.createTempSync('dest_resolver'));
  tearDown(() {
    if (_root.existsSync()) _root.deleteSync(recursive: true);
  });

  test('υπαρκτός φάκελος περνά χωρίς να ρωτηθεί τίποτα', () async {
    final spy = _ConfirmSpy(true);
    final resolution = await resolveBackupDestination(
      _root.path,
      confirmCreate: spy.call,
    );

    expect(resolution.isValid, isTrue);
    expect(resolution.errorMessage, isNull);
    expect(spy.asked, isEmpty, reason: 'Δεν υπάρχει τίποτα να δημιουργηθεί');
  });

  test('φάκελος που λείπει δημιουργείται μετά από «ναι»', () async {
    final target = p.join(_root.path, 'backups');
    final spy = _ConfirmSpy(true);

    final resolution = await resolveBackupDestination(
      target,
      confirmCreate: spy.call,
    );

    expect(resolution.isValid, isTrue);
    expect(spy.asked, [target]);
    expect(
      Directory(target).existsSync(),
      isTrue,
      reason: 'Το «ναι» πρέπει να φτιάχνει τον φάκελο στ αλήθεια',
    );
  });

  test('φωλιασμένη διαδρομή δημιουργείται ολόκληρη', () async {
    final target = p.join(_root.path, 'a', 'b', 'backups');
    final resolution = await resolveBackupDestination(
      target,
      confirmCreate: _ConfirmSpy(true).call,
    );

    expect(resolution.isValid, isTrue);
    expect(Directory(target).existsSync(), isTrue);
  });

  test('στο «άκυρο» δεν δημιουργείται τίποτα — και το λέει ως ακύρωση', () async {
    final target = p.join(_root.path, 'backups');
    final resolution = await resolveBackupDestination(
      target,
      confirmCreate: _ConfirmSpy(false).call,
    );

    expect(resolution.isValid, isFalse);
    expect(resolution.outcome, BackupDestinationOutcome.cancelled);
    expect(
      Directory(target).existsSync(),
      isFalse,
      reason: 'Ακύρωση σημαίνει ότι δεν γράφτηκε τίποτα στον δίσκο',
    );
  });

  test('κενή διαδρομή περνά χωρίς ερώτηση — «δεν ορίστηκε» δεν είναι σφάλμα', () async {
    final spy = _ConfirmSpy(true);
    final resolution = await resolveBackupDestination(
      '   ',
      confirmCreate: spy.call,
    );

    expect(resolution.isValid, isTrue);
    expect(spy.asked, isEmpty);
  });

  group('αρχείο στη θέση φακέλου', () {
    test('απορρίπτεται ΧΩΡΙΣ να προσφερθεί δημιουργία', () async {
      final file = File(p.join(_root.path, 'όχι-φάκελος.txt'))
        ..writeAsStringSync('x');
      final spy = _ConfirmSpy(true);

      final resolution = await resolveBackupDestination(
        file.path,
        confirmCreate: spy.call,
      );

      expect(resolution.isValid, isFalse);
      expect(
        spy.asked,
        isEmpty,
        reason:
            'Ο φάκελος δεν «λείπει» — υπάρχει αρχείο στη θέση του, και η '
            'δημιουργία είναι αδύνατη. Η ερώτηση δίνει ελπίδα που δεν υπάρχει.',
      );
    });

    test('το μήνυμα λέει ότι δεν είναι φάκελος, όχι ότι λείπει', () async {
      final file = File(p.join(_root.path, 'όχι-φάκελος.txt'))
        ..writeAsStringSync('x');

      final resolution = await resolveBackupDestination(
        file.path,
        confirmCreate: _ConfirmSpy(false).call,
      );

      expect(resolution.errorMessage, 'Η διαδρομή δεν είναι φάκελος');
    });

    test('το αρχείο του χρήστη μένει άθικτο', () async {
      final file = File(p.join(_root.path, 'όχι-φάκελος.txt'))
        ..writeAsStringSync('x');

      await resolveBackupDestination(
        file.path,
        confirmCreate: _ConfirmSpy(true).call,
      );

      expect(file.readAsStringSync(), 'x');
    });
  });

  group('το μήνυμα του ανύπαρκτου δίσκου', () {
    test('λέει ποιος δίσκος φταίει', () {
      final message = missingVolumeMessage(r'Ω:\backups');
      expect(message, contains('δεν μπορεί να δημιουργηθεί'));
    });

    test('χωρίς γράμμα δίσκου μιλά γενικά για τη διαδρομή', () {
      final message = missingVolumeMessage(r'\\server\share\backups');
      expect(message, contains('Ο δίσκος της διαδρομής δεν είναι διαθέσιμος'));
    });
  });
}
