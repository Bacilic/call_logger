import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_version_provider.dart';
import '../version_display.dart';
import 'changelog_dialog.dart';

/// Κλικ για άνοιγμα του ιστορικού αλλαγών. Για έκδοση 0.x.y δείχνει ένδειξη βήτα.
class VersionChip extends ConsumerWidget {
  const VersionChip({super.key, required this.extended});

  /// Όταν false, συντομευμένη ετικέτα για στενό NavigationRail.
  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVer = ref.watch(appVersionProvider);
    final scheme = Theme.of(context).colorScheme;

    return asyncVer.when(
      loading: () => SizedBox(
        width: extended ? 48 : 36,
        height: 22,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.outline,
            ),
          ),
        ),
      ),
      error: (_, _) => Tooltip(
        message: 'Έκδοση μη διαθέσιμη',
        child: Icon(Icons.error_outline, size: 18, color: scheme.error),
      ),
      data: (version) {
        final label = versionChipLabel(version, extended: extended);
        return Tooltip(
          message: versionChipTooltip(version),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => const ChangelogDialog(),
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: scheme.primary.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
