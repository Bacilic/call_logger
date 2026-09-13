import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../models/database_backup_settings.dart';
import '../utils/portable_backup_availability.dart';

/// «Τι μπαίνει στο πλήρες αντίγραφο»: οι τέσσερις διακόπτες των φορητών.
///
/// Κάθε διακόπτης είναι ανενεργός όταν δεν υπάρχει τίποτα να μπει — με
/// υπόδειξη που λέει γιατί, αντί να αφήνει τον χρήστη να πατά κάτι που δεν
/// κάνει τίποτα.
class BackupTabContentsSection extends StatelessWidget {
  const BackupTabContentsSection({
    super.key,
    required this.settings,
    required this.availabilityFuture,
    required this.onToggleMapImages,
    required this.onToggleToolImages,
    required this.onToggleLexicon,
    required this.onToggleLampDb,
  });

  final DatabaseBackupSettings settings;
  final Future<PortableBackupAvailability> availabilityFuture;
  final ValueChanged<bool> onToggleMapImages;
  final ValueChanged<bool> onToggleToolImages;
  final ValueChanged<bool> onToggleLexicon;
  final ValueChanged<bool> onToggleLampDb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Τι μπαίνει στο πλήρες αντίγραφο',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Η βάση αντιγράφεται κάθε φορά (.db). Τα παρακάτω μπαίνουν σε '
          'πλήρες αντίγραφο (.zip) ΜΟΝΟ όταν κάτι τους αλλάξει — αλλιώς '
          'παίρνεται γρήγορο, μόνο με τη βάση, και ο δίσκος δεν γεμίζει '
          'πανομοιότυπα αρχεία.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        FutureBuilder<PortableBackupAvailability>(
          future: availabilityFuture,
          builder: (context, snapshot) {
            final avail = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PortableBackupSwitch(
                  title: 'Συμπερίληψη εικόνων χαρτών',
                  subtitle: Text(
                    PortableBackupAvailability.mapsImagesSubtitle(),
                  ),
                  value: settings.includeMapImagesInBackup,
                  enabled: avail?.hasMapImages ?? false,
                  disabledTooltip: 'Δεν υπάρχουν αποθηκευμένες εικόνες χαρτών',
                  onChanged: onToggleMapImages,
                ),
                PortableBackupSwitch(
                  title: 'Εικονίδια εργαλείων',
                  subtitle: Text(
                    'Zip με φάκελο ${AppConfig.portableImagesDirName} '
                    '(στη ρίζα εφαρμογής)',
                  ),
                  value: settings.includeToolImages,
                  enabled: avail?.hasToolImages ?? false,
                  disabledTooltip:
                      'Δεν υπάρχουν αποθηκευμένα εικονίδια εργαλείων',
                  onChanged: onToggleToolImages,
                ),
                PortableBackupSwitch(
                  title: 'Λεξικό',
                  subtitle: Text(
                    'Zip με φάκελο ${AppConfig.portableDictionariesDirName}',
                  ),
                  value: settings.includeLexicon,
                  enabled: avail?.hasLoadedLexicon ?? false,
                  disabledTooltip: 'Δεν υπάρχει φορτωμένο λεξικό',
                  onChanged: onToggleLexicon,
                ),
                PortableBackupSwitch(
                  title: 'Βάση Λάμπας',
                  subtitle: Text(
                    'Zip με αρχείο .db από '
                    '${AppConfig.portableDataBaseDirName}',
                  ),
                  value: settings.includeLampDb,
                  enabled: avail?.hasLampDbInPortableDataBase ?? false,
                  disabledTooltip:
                      'Δεν υπάρχει βάση Λάμπας στον φάκελο της εφαρμογής',
                  onChanged: onToggleLampDb,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Διακόπτης φορητού περιεχομένου που εξηγεί γιατί δεν πατιέται.
class PortableBackupSwitch extends StatelessWidget {
  const PortableBackupSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.disabledTooltip,
    required this.onChanged,
  });

  final String title;
  final Widget subtitle;
  final bool value;
  final bool enabled;
  final String disabledTooltip;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tile = SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle,
      value: value,
      onChanged: enabled ? onChanged : null,
    );
    if (enabled) return tile;
    return Tooltip(
      message: disabledTooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: tile,
    );
  }
}
