// Υπάρχει ο φάκελος ενημερώσεων; Καθαρή λογική, χωρίς οθόνη.
//
//   flutter test test/core/updates/update_folder_presence_test.dart

import 'dart:io';

import 'package:call_logger/core/updates/update_folder_presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('probeUpdateFolderPresence', () {
    test('κενή διαδρομή δεν είναι σφάλμα', () async {
      expect(
        await probeUpdateFolderPresence('', exists: (_) async => false),
        UpdateFolderPresence.unset,
        reason:
            'Κενό πεδίο σημαίνει «χρησιμοποίησε το update_source.json δίπλα '
            'στο εκτελέσιμο» — έγκυρη επιλογή, όχι λάθος.',
      );
    });

    test('μόνο κενά μετρούν ως κενή διαδρομή', () async {
      expect(
        await probeUpdateFolderPresence('   ', exists: (_) async => false),
        UpdateFolderPresence.unset,
      );
    });

    test('υπαρκτός φάκελος', () async {
      expect(
        await probeUpdateFolderPresence(
          r'C:\Updates',
          exists: (_) async => true,
        ),
        UpdateFolderPresence.present,
      );
    });

    test('ανύπαρκτος φάκελος', () async {
      expect(
        await probeUpdateFolderPresence(
          r'C:\Updates',
          exists: (_) async => false,
        ),
        UpdateFolderPresence.missing,
      );
    });

    test('η διαδρομή ελέγχεται χωρίς τα περιττά κενά της', () async {
      String? seen;
      await probeUpdateFolderPresence(
        '  C:\\Updates  ',
        exists: (path) async {
          seen = path;
          return true;
        },
      );
      expect(seen, r'C:\Updates');
    });

    test('άφταστη διαδρομή δικτύου μετρά ως «δεν βρέθηκε»', () async {
      expect(
        await probeUpdateFolderPresence(
          r'\\server\share',
          exists: (_) async => throw const FileSystemException('offline'),
        ),
        UpdateFolderPresence.missing,
        reason:
            'Στα Windows το exists() ΠΕΤΑΕΙ αντί να απαντήσει false. Για τον '
            'χρήστη η κατάσταση είναι μία: ο φάκελος δεν είναι εκεί τώρα.',
      );
    });

    test('οποιοδήποτε άλλο σφάλμα δεν σωπαίνει', () async {
      expect(
        await probeUpdateFolderPresence(
          'κάτι',
          exists: (_) async => throw ArgumentError('bad'),
        ),
        UpdateFolderPresence.missing,
      );
    });
  });
}
