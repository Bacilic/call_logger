import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/backup_destination_folder_validator.dart';
import '../utils/backup_destination_location_warnings.dart';
import '../utils/backup_location_hints.dart';

/// Το πλαίσιο της διαδρομής προορισμού: πεδίο, αναζήτηση και όσα πρέπει να
/// ξέρει ο χρήστης για τον φάκελο που διάλεξε.
///
/// Δεν διαβάζει ρυθμίσεις και δεν γράφει πουθενά — δέχεται έτοιμα δεδομένα
/// και ανακοινώνει τις ενέργειες του χρήστη.
class BackupTabDestinationSection extends StatelessWidget {
  const BackupTabDestinationSection({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.errorText,
    required this.onPickFolder,
    required this.onCommit,
    required this.locationCaptionsFuture,
    required this.destinationContentFuture,
    required this.warningContextFuture,
    required this.configuredDestination,
    required this.showSystemDriveWarning,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final VoidCallback onPickFolder;

  /// Ο χρήστης δήλωσε ότι τελείωσε με το πεδίο (Enter ή απώλεια εστίασης).
  final VoidCallback onCommit;

  final Future<List<BackupCaptionSegment>> locationCaptionsFuture;
  final Future<BackupDestinationContentResult> destinationContentFuture;
  final Future<({String dbPath, int eligibleWindowsVolumeCount})>
  warningContextFuture;

  /// Η **αποθηκευμένη** διαδρομή — όχι το κείμενο του πεδίου.
  final String configuredDestination;

  final bool showSystemDriveWarning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LocationCaptions(future: locationCaptionsFuture),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildField(theme)),
            const SizedBox(width: 8),
            SizedBox(
              height: 38,
              child: FilledButton.tonalIcon(
                onPressed: onPickFolder,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Αναζήτηση'),
              ),
            ),
          ],
        ),
        if (configuredDestination.trim().isNotEmpty)
          _MissingFolderBanner(
            future: destinationContentFuture,
            destination: configuredDestination,
          ),
        if (Platform.isWindows) ...[
          const SizedBox(height: 4),
          Text(
            'Στον διάλογο επιλογής (Windows) χρησιμοποιήστε «Νέος φάκελος» '
            'για δημιουργία φακέλου (π.χ. backups σε εξωτερικό δίσκο). '
            'Μπορείτε επίσης να πληκτρολογήσετε διαδρομή και να επιβεβαιώσετε '
            'με Enter — αν λείπει ο φάκελος, θα σας ζητηθεί δημιουργία.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        _LocationRiskWarnings(
          future: warningContextFuture,
          typedDestination: controller.text.trim(),
          suppressed: errorText != null,
        ),
        if (showSystemDriveWarning) ...[
          const SizedBox(height: 8),
          _WarningRow(
            color: theme.colorScheme.error,
            text:
                'Ο φάκελος είναι στον τόμο C: (συστήματος). '
                'Σε βλάβη δίσκου ή επανεγκατάσταση Windows το αντίγραφο '
                'μπορεί να χαθεί μαζί με τα δεδομένα.',
          ),
        ],
      ],
    );
  }

  Widget _buildField(ThemeData theme) {
    OutlineInputBorder border(Color color) =>
        OutlineInputBorder(borderSide: BorderSide(width: 1, color: color));

    return TextField(
      focusNode: focusNode,
      controller: controller,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        labelText: 'Φάκελος προορισμού',
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        isDense: true,
        errorText: errorText,
        errorMaxLines: 2,
        errorStyle: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        enabledBorder: border(theme.colorScheme.outline),
        focusedBorder: border(theme.colorScheme.primary),
        errorBorder: border(theme.colorScheme.error),
        focusedErrorBorder: border(theme.colorScheme.error),
        disabledBorder: border(
          theme.colorScheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
      maxLines: 1,
      onEditingComplete: onCommit,
      onSubmitted: (_) => onCommit(),
    );
  }
}

/// Οι υποδείξεις «πού να βάλετε τα αντίγραφα», με έμφαση στα ονόματα δίσκων.
class _LocationCaptions extends StatelessWidget {
  const _LocationCaptions({required this.future});

  final Future<List<BackupCaptionSegment>> future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<BackupCaptionSegment>>(
      future: future,
      builder: (context, snapshot) {
        final color = snapshot.hasError
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant;
        final style = theme.textTheme.bodySmall?.copyWith(color: color);
        if (snapshot.hasError) {
          return Text(
            'Δεν ήταν δυνατή η φόρτωση υποδείξεων τοποθεσίας.',
            style: style,
          );
        }
        if (!snapshot.hasData) {
          return Text('Φόρτωση υποδείξεων τοποθεσίας…', style: style);
        }
        return Text.rich(
          TextSpan(
            style: style,
            children: [
              for (final segment in snapshot.data!)
                TextSpan(
                  text: segment.text,
                  style: segment.bold
                      ? const TextStyle(fontWeight: FontWeight.bold)
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// «Ο φάκελος προορισμού δεν βρέθηκε» — αποσυνδεδεμένος δίσκος ή διαγραφή.
class _MissingFolderBanner extends StatelessWidget {
  const _MissingFolderBanner({
    required this.future,
    required this.destination,
  });

  final Future<BackupDestinationContentResult> future;
  final String destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<BackupDestinationContentResult>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        if (snapshot.data!.kind != BackupDestinationContentKind.folderMissing) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Material(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                'Ο φάκελος προορισμού δεν βρέθηκε:\n$destination\n'
                'Πιθανή αιτία: αποσυνδεδεμένος δίσκος ή διαγραφή. '
                'Τα αρχεία αντιγράφου στον δίσκο μπορεί να μην είναι '
                'διαθέσιμα.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Οι δύο προειδοποιήσεις συστέγασης: ίδιος φάκελος με τη βάση, ίδιος τόμος.
///
/// Σιωπούν όσο το πεδίο έχει σφάλμα — η διαδρομή δεν ισχύει ακόμη, και δύο
/// αντικρουόμενα μηνύματα για το ίδιο πεδίο αλληλοακυρώνονται.
class _LocationRiskWarnings extends StatelessWidget {
  const _LocationRiskWarnings({
    required this.future,
    required this.typedDestination,
    required this.suppressed,
  });

  final Future<({String dbPath, int eligibleWindowsVolumeCount})> future;
  final String typedDestination;
  final bool suppressed;

  @override
  Widget build(BuildContext context) {
    if (suppressed || typedDestination.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<({String dbPath, int eligibleWindowsVolumeCount})>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final ctx = snapshot.data!;
        final colocated =
            BackupDestinationLocationWarnings.colocatedWithDatabase(
              databaseFilePath: ctx.dbPath,
              destinationDirectory: typedDestination,
            );
        final sameVolume = BackupDestinationLocationWarnings.sameWindowsVolume(
          databasePath: ctx.dbPath,
          destinationDirectory: typedDestination,
        );
        // Ο ίδιος τόμος αξίζει προειδοποίηση μόνο όταν υπάρχει αλλού να πάει.
        final showSameVolume =
            sameVolume && ctx.eligibleWindowsVolumeCount >= 2;
        if (!colocated && !showSameVolume) return const SizedBox.shrink();

        final orange = Colors.deepOrange.shade800;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (colocated) ...[
              const SizedBox(height: 8),
              _WarningRow(
                color: orange,
                text:
                    'Ο φάκελος προορισμού του αντιγράφου ασφαλείας (backup) '
                    'βρίσκεται στον ίδιο χώρο με τα αρχεία της βάσης (ίδιος '
                    'φάκελος ή υποφάκελός του). Σε απώλεια, διαγραφή ή βλάβη '
                    'του μέσου ενδέχεται να χαθούν μαζί τα δεδομένα και το '
                    'αντίγραφο.',
              ),
            ],
            if (showSameVolume) ...[
              const SizedBox(height: 8),
              _WarningRow(
                color: orange,
                text:
                    'Το αντίγραφο αποθηκεύεται στον ίδιο τόμο (volume) με τη '
                    'βάση. Σε βλάβη δίσκου ενδέχεται να επηρεαστούν και τα '
                    'δύο.',
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Εικονίδιο προειδοποίησης και κείμενο, στο ίδιο χρώμα.
class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
