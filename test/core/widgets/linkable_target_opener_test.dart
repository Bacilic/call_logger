import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/utils/linkable_text_parser.dart';
import 'package:call_logger/core/widgets/linkable_target_opener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uncTarget = r'\\10.10.212.23\oki4410';

  group('LinkableTargetOpener — μη προσβάσιμες διαδρομές', () {
    test('εξαίρεση των Windows (errno 53) γίνεται pathUnreachable '
        'με το μήνυμα του λειτουργικού, χωρίς να πεταχτεί παραπέρα', () async {
      final opener = LinkableTargetOpener(
        fileExists: (_) async => false,
        directoryExists: (_) async => throw FileSystemException(
          'Exists failed',
          uncTarget,
          const OSError('Η διαδρομή του δικτύου δεν εντοπίστηκε', 53),
        ),
        revealFileInExplorer: (_) async =>
            fail('δεν πρέπει να ανοίξει Explorer'),
        openFolderInExplorer: (_) async =>
            fail('δεν πρέπει να ανοίξει Explorer'),
        launchUrl: (_) async => fail('δεν πρέπει να κληθεί browser'),
      );

      final outcome = await opener.open(
        target: uncTarget,
        kind: LinkableTextKind.uncPath,
      );

      expect(outcome.result, LinkOpenResult.pathUnreachable);
      expect(outcome.osMessage, 'Η διαδρομή του δικτύου δεν εντοπίστηκε');
    });

    test('έλεγχος ύπαρξης που δεν απαντά ποτέ κόβεται στο όριο χρόνου '
        'και γίνεται pathUnreachable', () async {
      final opener = LinkableTargetOpener(
        fileExists: (_) => Completer<bool>().future,
        directoryExists: (_) => Completer<bool>().future,
        revealFileInExplorer: (_) async =>
            fail('δεν πρέπει να ανοίξει Explorer'),
        openFolderInExplorer: (_) async =>
            fail('δεν πρέπει να ανοίξει Explorer'),
        launchUrl: (_) async => fail('δεν πρέπει να κληθεί browser'),
        filesystemProbeTimeout: const Duration(milliseconds: 50),
      );

      final outcome = await opener.open(
        target: uncTarget,
        kind: LinkableTextKind.uncPath,
      );

      expect(outcome.result, LinkOpenResult.pathUnreachable);
      expect(outcome.osMessage, isNull);
    });

    test('ανύπαρκτη διαδρομή με γρήγορη απάντηση παραμένει pathNotFound',
        () async {
      final opener = LinkableTargetOpener(
        fileExists: (_) async => false,
        directoryExists: (_) async => false,
        revealFileInExplorer: (_) async =>
            fail('δεν πρέπει να ανοίξει Explorer'),
        openFolderInExplorer: (_) async =>
            fail('δεν πρέπει να ανοίξει Explorer'),
        launchUrl: (_) async => fail('δεν πρέπει να κληθεί browser'),
      );

      final outcome = await opener.open(
        target: r'C:\anyparkto\arxeio.txt',
        kind: LinkableTextKind.localPath,
      );

      expect(outcome.result, LinkOpenResult.pathNotFound);
    });
  });

  group('LinkableTargetOpener — επιτυχές άνοιγμα', () {
    test('υπάρχον αρχείο ανοίγει με εμφάνιση στον Explorer', () async {
      String? revealed;
      final opener = LinkableTargetOpener(
        fileExists: (_) async => true,
        directoryExists: (_) async => false,
        revealFileInExplorer: (path) async => revealed = path,
        openFolderInExplorer: (_) async => fail('περίμενα εμφάνιση αρχείου'),
        launchUrl: (_) async => fail('δεν πρέπει να κληθεί browser'),
      );

      final outcome = await opener.open(
        target: r'C:\fakelos\arxeio.txt',
        kind: LinkableTextKind.localPath,
      );

      expect(outcome.result, LinkOpenResult.opened);
      expect(revealed, r'C:\fakelos\arxeio.txt');
    });

    test('υπάρχων φάκελος ανοίγει στον Explorer', () async {
      String? openedFolder;
      final opener = LinkableTargetOpener(
        fileExists: (_) async => false,
        directoryExists: (_) async => true,
        revealFileInExplorer: (_) async => fail('περίμενα άνοιγμα φακέλου'),
        openFolderInExplorer: (path) async => openedFolder = path,
        launchUrl: (_) async => fail('δεν πρέπει να κληθεί browser'),
      );

      final outcome = await opener.open(
        target: uncTarget,
        kind: LinkableTextKind.uncPath,
      );

      expect(outcome.result, LinkOpenResult.opened);
      expect(openedFolder, uncTarget);
    });
  });

  group('LinkableTargetOpener.messageFor', () {
    test('το μήνυμα των Windows προτιμάται όταν υπάρχει', () {
      final message = LinkableTargetOpener.messageFor(
        (
          result: LinkOpenResult.pathUnreachable,
          osMessage: 'Η διαδρομή του δικτύου δεν εντοπίστηκε',
        ),
        uncTarget,
      );

      expect(message, contains(uncTarget));
      expect(message, contains('Η διαδρομή του δικτύου δεν εντοπίστηκε'));
    });

    test('χωρίς μήνυμα λειτουργικού δίνεται ειλικρινής εξήγηση μη απόκρισης',
        () {
      final message = LinkableTargetOpener.messageFor(
        (result: LinkOpenResult.pathUnreachable, osMessage: null),
        uncTarget,
      );

      expect(message, contains('δεν αποκρίνεται'));
      expect(message, isNot(contains('δεν βρέθηκε')));
    });

    test('το «δεν βρέθηκε» μένει μόνο για σίγουρα ανύπαρκτες διαδρομές', () {
      final message = LinkableTargetOpener.messageFor(
        (result: LinkOpenResult.pathNotFound, osMessage: null),
        uncTarget,
      );

      expect(message, 'Η διαδρομή δεν βρέθηκε: $uncTarget');
    });

    test('επιτυχία δεν παράγει μήνυμα', () {
      final message = LinkableTargetOpener.messageFor(
        (result: LinkOpenResult.opened, osMessage: null),
        uncTarget,
      );

      expect(message, isNull);
    });
  });
}
