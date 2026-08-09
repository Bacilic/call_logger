import 'package:flutter/material.dart';

import '../../../core/services/shutdown_trace_incident.dart';

/// Ειδοποίηση για το τελευταίο προβληματικό κλείσιμο της εφαρμογής.
///
/// Εμφανίζεται ΜΟΝΟ όταν ο ιχνηλάτης άφησε αρχείο — δηλαδή όταν κάτι πήγε
/// στραβά. Στη φυσιολογική ζωή της εφαρμογής η ενότητα «Καταγραφή σφαλμάτων»
/// δεν δείχνει τίποτα εδώ.
class ShutdownIncidentNotice extends StatelessWidget {
  const ShutdownIncidentNotice({
    super.key,
    required this.incident,
    required this.onOpenFile,
  });

  final ShutdownTraceIncident incident;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Colors.orange.shade800;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.timer_outlined, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    incident.describe(),
                    style: theme.textTheme.bodyMedium?.copyWith(color: color),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Ανοίξτε το αρχείο για λεπτομέρειες: ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onOpenFile,
                          child: Text(
                            incident.fileName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              decoration: TextDecoration.underline,
                              decorationColor: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
