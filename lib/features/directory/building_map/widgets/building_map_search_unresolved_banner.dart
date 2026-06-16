import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/building_map_providers.dart';

/// Banner πάνω από τον καμβά όταν η αναζήτηση βρίσκει τμήμα χωρίς σχεδιασμένη περιοχή.
class BuildingMapSearchUnresolvedBanner extends ConsumerWidget {
  const BuildingMapSearchUnresolvedBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(buildingMapSearchUnresolvedNoticeProvider);
    if (notice == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final editMode = ref.watch(buildingMapUiEditModeProvider);
    final canDraw =
        editMode && notice.departmentId != null && notice.departmentId! > 0;

    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  notice.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    height: 1.35,
                  ),
                ),
              ),
              if (canDraw)
                TextButton(
                  onPressed: () {
                    ref
                        .read(buildingMapSearchUnresolvedNoticeProvider.notifier)
                        .clear();
                    ref
                        .read(buildingMapToolProvider.notifier)
                        .setMode(MapToolMode.draw);
                  },
                  child: const Text('Σχεδίαση'),
                ),
              IconButton(
                tooltip: 'Κλείσιμο',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                onPressed: () => ref
                    .read(buildingMapSearchUnresolvedNoticeProvider.notifier)
                    .clear(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
