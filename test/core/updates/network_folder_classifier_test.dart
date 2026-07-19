import 'dart:async';

import 'package:call_logger/core/updates/network_folder_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NetworkFolderClassifier classifier({
    Future<bool?> Function(String driveLetter)? driveTypeResolver,
    Future<List<String>> Function()? localSharesProvider,
    bool Function()? isWindows,
  }) {
    return NetworkFolderClassifier(
      driveTypeResolver:
          driveTypeResolver ?? ((_) async => false),
      localSharesProvider: localSharesProvider ?? (() async => <String>[]),
      isWindows: isWindows ?? (() => true),
    );
  }

  test('UNC path → networkUnc', () async {
    final c = classifier(
      driveTypeResolver: (_) async => fail('driveType δεν πρέπει να κληθεί για UNC'),
      localSharesProvider: () async =>
          fail('shares δεν πρέπει να κληθεί για UNC'),
    );

    expect(
      await c.classify(r'\\server\share\call_logger_updates'),
      NetworkFolderKind.networkUnc,
    );
  });

  test('drive letter with remote driveType → networkMappedDrive', () async {
    String? seenLetter;
    final c = classifier(
      driveTypeResolver: (letter) async {
        seenLetter = letter;
        return true;
      },
    );

    expect(
      await c.classify(r'Z:\team\updates'),
      NetworkFolderKind.networkMappedDrive,
    );
    expect(seenLetter, 'Z');
  });

  test('local path exact share match → localShared', () async {
    final c = classifier(
      localSharesProvider: () async => [r'C:\updates'],
    );

    expect(
      await c.classify(r'C:\updates'),
      NetworkFolderKind.localShared,
    );
  });

  test('local path under share → localShared', () async {
    final c = classifier(
      localSharesProvider: () async => [r'C:\updates'],
    );

    expect(
      await c.classify(r'C:\updates\call_logger'),
      NetworkFolderKind.localShared,
    );
  });

  test('local path outside any share → localOnly', () async {
    final c = classifier(
      localSharesProvider: () async => [r'C:\updates'],
    );

    expect(
      await c.classify(r'C:\private\folder'),
      NetworkFolderKind.localOnly,
    );
  });

  test(
    'administrative drive-root share (C\$ → C:\\) must NOT count as shared',
    () async {
      // Αναπαραγωγή πραγματικής εξόδου Get-SmbShare: το admin share C$
      // έχει path τη ρίζα του δίσκου και θα κάλυπτε ΚΑΘΕ φάκελο του C:.
      final c = classifier(
        localSharesProvider: () async => [r'C:\', r'C:\Windows'],
      );

      expect(
        await c.classify(r'C:\Users\Bacilic\Desktop\Updates'),
        NetworkFolderKind.localOnly,
      );
    },
  );

  test(
    'real share alongside admin shares → still localShared for that folder',
    () async {
      // Μικτή λίστα: admin shares + ένας πραγματικός κοινόχρηστος φάκελος.
      final c = classifier(
        localSharesProvider: () async => [r'C:\', r'C:\Windows', r'C:\updates'],
      );

      expect(
        await c.classify(r'C:\updates\call_logger'),
        NetworkFolderKind.localShared,
      );
      expect(
        await c.classify(r'C:\Users\Bacilic\Desktop\Updates'),
        NetworkFolderKind.localOnly,
      );
    },
  );

  test(
    'shares empty or throw → non-shared local is localOnly; impossible is unknown',
    () async {
      final emptyShares = classifier(
        localSharesProvider: () async => <String>[],
      );
      expect(
        await emptyShares.classify(r'C:\private\folder'),
        NetworkFolderKind.localOnly,
      );

      final throwingShares = classifier(
        localSharesProvider: () async =>
            throw TimeoutException('simulated timeout'),
      );
      expect(
        await throwingShares.classify(r'D:\local\only'),
        NetworkFolderKind.localOnly,
      );

      final nonWindows = classifier(isWindows: () => false);
      expect(
        await nonWindows.classify(r'C:\anything'),
        NetworkFolderKind.unknown,
      );

      final emptyPath = classifier();
      expect(await emptyPath.classify('   '), NetworkFolderKind.unknown);

      final throwingDrive = classifier(
        driveTypeResolver: (_) async => throw StateError('ffi failed'),
      );
      expect(
        await throwingDrive.classify(r'C:\foo'),
        NetworkFolderKind.unknown,
      );
    },
  );
}
