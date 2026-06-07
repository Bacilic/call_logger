import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/utils/portable_backup_availability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const availability = PortableBackupAvailability(
    hasMapImages: false,
    hasToolImages: true,
    hasLoadedLexicon: false,
    hasLampDbInPortableDataBase: false,
  );

  group('DatabaseBackupSettings effective portable bundle', () {
    test('disabled-but-ON lexicon and lamp do not lock zip', () {
      const settings = DatabaseBackupSettings(
        destinationDirectory: '',
        namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
        zipOutput: false,
        includeMapImagesInBackup: false,
        includeToolImages: false,
        includeLexicon: true,
        includeLampDb: true,
        backupOnExit: false,
        interval: DatabaseBackupInterval.never,
        backupDays: <int>[],
        backupTime: '09:00',
        lastBackupStatus: 'none',
        retentionMaxCopiesEnabled: false,
        retentionMaxCopies: 30,
        retentionMaxAgeEnabled: false,
        retentionMaxAgeDays: 60,
      );

      expect(settings.includesPortableBundleInZip, isTrue);
      expect(
        settings.effectiveIncludesPortableBundleInZip(availability),
        isFalse,
      );
    });

    test('enabled tool images with availability lock zip', () {
      const settings = DatabaseBackupSettings(
        destinationDirectory: '',
        namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
        zipOutput: false,
        includeMapImagesInBackup: false,
        includeToolImages: true,
        includeLexicon: true,
        includeLampDb: true,
        backupOnExit: false,
        interval: DatabaseBackupInterval.never,
        backupDays: <int>[],
        backupTime: '09:00',
        lastBackupStatus: 'none',
        retentionMaxCopiesEnabled: false,
        retentionMaxCopies: 30,
        retentionMaxAgeEnabled: false,
        retentionMaxAgeDays: 60,
      );

      expect(
        settings.effectiveIncludesPortableBundleInZip(availability),
        isTrue,
      );
      expect(settings.effectiveIncludeToolImages(availability), isTrue);
      expect(settings.effectiveIncludeLexicon(availability), isFalse);
      expect(settings.effectiveIncludeLampDb(availability), isFalse);
    });
  });
}
