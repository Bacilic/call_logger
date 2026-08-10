import 'dart:io';

import 'package:call_logger/features/database/utils/backup_destination_folder_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BackupDestinationFolderValidator', () {
    test(
      'missing directory is reported distinctly from invalid path',
      () async {
        final missing = p.join(
          Directory.systemTemp.path,
          'call_logger_missing_dir_test_xyz',
        );
        final result = await BackupDestinationFolderValidator.validate(missing);
        expect(result.kind, BackupDestinationValidationKind.missingDirectory);
        expect(result.errorMessage, 'Ο φάκελος δεν υπάρχει');
      },
    );

    test('empty path is ok', () async {
      final result = await BackupDestinationFolderValidator.validate('   ');
      expect(result.kind, BackupDestinationValidationKind.ok);
    });

    test('inspectDestinationContent folderMissing', () async {
      final missing = p.join(
        Directory.systemTemp.path,
        'call_logger_content_missing_xyz',
      );
      final result =
          await BackupDestinationFolderValidator.inspectDestinationContent(
            destinationDirectory: missing,
            dbBaseName: 'call_logger',
          );
      expect(result.kind, BackupDestinationContentKind.folderMissing);
    });

    test('inspectDestinationContent folderEmptyNoFiles', () async {
      final dir = await Directory(
        p.join(
          Directory.systemTemp.path,
          'call_logger_content_empty_${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create(recursive: true);
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final result =
          await BackupDestinationFolderValidator.inspectDestinationContent(
            destinationDirectory: dir.path,
            dbBaseName: 'call_logger',
          );
      expect(result.kind, BackupDestinationContentKind.folderEmptyNoFiles);
    });

    test('inspectDestinationContent folderOk', () async {
      final dir = await Directory(
        p.join(
          Directory.systemTemp.path,
          'call_logger_content_ok_${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create(recursive: true);
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final file = File(p.join(dir.path, '2026-06-06_18-12_call_logger.zip'));
      await file.writeAsString('x');
      final result =
          await BackupDestinationFolderValidator.inspectDestinationContent(
            destinationDirectory: dir.path,
            dbBaseName: 'call_logger',
          );
      expect(result.kind, BackupDestinationContentKind.folderOk);
      expect(result.matchingBackupFileCount, 1);
      expect(result.latestBackupModified, isNotNull);
    });

    test('isBackupArtifactFileName', () {
      expect(
        BackupDestinationFolderValidator.isBackupArtifactFileName(
          '2026-06-06_18-12_call_logger.zip',
          'call_logger',
        ),
        isTrue,
      );
      expect(
        BackupDestinationFolderValidator.isBackupArtifactFileName(
          'random.txt',
          'call_logger',
        ),
        isFalse,
      );
    });
  });

  // Άφταστη διαδρομή δικτύου (UNC εκτός σύνδεσης, OS error 53): στα Windows το
  // exists()/existsSync() δεν απαντά «false» — ΠΕΤΑΕΙ PathNotFoundException.
  // Το πραγματικό περιστατικό: βάση νοσοκομείου με προορισμό \\gnk.local\...
  // ανοιγμένη στο σπίτι έριχνε ολόκληρη την εκκίνηση στην οθόνη σφάλματος.
  // Συμβόλαιο: ο validator ΤΑΞΙΝΟΜΕΙ την αδυναμία πρόσβασης, δεν την προωθεί.
  group('άφταστη διαδρομή δικτύου', () {
    const unc = r'\\unreachable-host.local\share\Backups';

    test('inspectDestinationContent → folderMissing όταν το exists πετάει', () async {
      final result = await IOOverrides.runZoned(
        () => BackupDestinationFolderValidator.inspectDestinationContent(
          destinationDirectory: unc,
          dbBaseName: 'Hospital',
        ),
        createDirectory: (path) => _UnreachableDirectory(path),
      );

      expect(result.kind, BackupDestinationContentKind.folderMissing);
      expect(result.dbBaseName, 'Hospital');
    });

    test('inspectDestinationContent → folderMissing όταν το δίκτυο κοπεί '
        'στη μέση της απαρίθμησης', () async {
      final result = await IOOverrides.runZoned(
        () => BackupDestinationFolderValidator.inspectDestinationContent(
          destinationDirectory: unc,
          dbBaseName: 'Hospital',
        ),
        createDirectory: (path) =>
            _UnreachableDirectory(path, existsSucceeds: true),
      );

      expect(result.kind, BackupDestinationContentKind.folderMissing);
    });

    test('findLatestBackupZip → null αντί για εξαίρεση', () async {
      final zip = await IOOverrides.runZoned(
        () => BackupDestinationFolderValidator.findLatestBackupZip(
          destinationDirectory: unc,
          dbBaseName: 'Hospital',
        ),
        createDirectory: (path) => _UnreachableDirectory(path),
      );

      expect(zip, isNull);
    });

    test('validate → «Ο φάκελος δεν υπάρχει», ίδιο μήνυμα με τον χαμένο '
        'φάκελο', () async {
      final result = await IOOverrides.runZoned(
        () => BackupDestinationFolderValidator.validate(unc),
        createDirectory: (path) => _UnreachableDirectory(path),
      );

      expect(result.kind, BackupDestinationValidationKind.missingDirectory);
      expect(result.errorMessage, 'Ο φάκελος δεν υπάρχει');
    });
  });
}

/// Φάκελος σε διαδρομή δικτύου που δεν αποκρίνεται: κάθε προσπέλαση πετάει
/// ό,τι ακριβώς πετάει το dart:io στα Windows για UNC εκτός σύνδεσης.
class _UnreachableDirectory implements Directory {
  _UnreachableDirectory(this.path, {this.existsSucceeds = false});

  @override
  final String path;

  /// true = το exists περνά και το σκάσιμο έρχεται από το list (κομμένο δίκτυο
  /// στη μέση της απαρίθμησης).
  final bool existsSucceeds;

  Never _networkGone() => throw PathNotFoundException(
    path,
    const OSError('Η διαδρομή του δικτύου δεν εντοπίστηκε.', 53),
    'Exists failed',
  );

  @override
  Future<bool> exists() async => existsSucceeds ? true : _networkGone();

  @override
  bool existsSync() => existsSucceeds ? true : _networkGone();

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream<FileSystemEntity>.error(
    PathNotFoundException(
      path,
      const OSError('Η διαδρομή του δικτύου δεν εντοπίστηκε.', 53),
      'Directory listing failed',
    ),
  );

  /// Καμία άλλη λειτουργία δεν ανήκει στο μονοπάτι που ελέγχεται.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Μη αναμενόμενη κλήση: ${invocation.memberName}');
}
