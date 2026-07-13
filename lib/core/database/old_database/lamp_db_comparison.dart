import 'package:call_logger/core/database/old_database/lamp_old_db_validator.dart';

/// Στιγμιότυπο στατιστικών ενός αρχείου βάσης Λάμπας.
class LampDbSnapshot {
  const LampDbSnapshot({
    required this.exists,
    this.modified,
    this.sizeBytes,
    this.equipmentCount,
    this.issuesCount,
  });

  final bool exists;
  final DateTime? modified;
  final int? sizeBytes;
  final int? equipmentCount;
  final int? issuesCount;
}

/// Ουδέτερες ενημερωτικές ειδοποιήσεις σύγκρισης ανάγνωσης έναντι εξόδου.
List<String> buildLampDbComparisonNotifications({
  required LampDbSnapshot read,
  required LampDbSnapshot output,
  required String readPath,
  required String outputPath,
}) {
  if (LampOldDbValidator.pathsReferToSameFile(readPath, outputPath)) {
    return const <String>[];
  }

  final notifications = <String>[];

  if (!read.exists && output.exists) {
    notifications.add(
      'Δεν έχει οριστεί ή δεν βρέθηκε η βάση ανάγνωσης, ενώ υπάρχει φρέσκια βάση εξόδου.',
    );
  }

  if (read.exists && output.exists) {
    final readModified = read.modified;
    final outputModified = output.modified;
    if (readModified != null &&
        outputModified != null &&
        outputModified.isAfter(readModified)) {
      notifications.add(
        'Η βάση εξόδου είναι πιο πρόσφατη (${_formatDateTime(outputModified)}) '
        'από τη βάση ανάγνωσης (${_formatDateTime(readModified)}).',
      );
    }

    final readEquipment = read.equipmentCount;
    final outputEquipment = output.equipmentCount;
    if (readEquipment != null &&
        outputEquipment != null &&
        readEquipment != outputEquipment) {
      notifications.add(
        'Διαφορά στο πλήθος εξοπλισμού: ανάγνωση $readEquipment, έξοδος $outputEquipment.',
      );
    }

    final readIssues = read.issuesCount;
    final outputIssues = output.issuesCount;
    if (readIssues != null &&
        outputIssues != null &&
        readIssues != outputIssues) {
      notifications.add(
        'Διαφορά στο πλήθος προβλημάτων (data_issues): ανάγνωση $readIssues, έξοδος $outputIssues.',
      );
    }
  }

  return notifications;
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hour:$minute';
}
