import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/main_nav_request_provider.dart';
import '../../widgets/main_nav_destination.dart';
import '../../../features/database/debug/integrity_debug_seeder_service.dart';
import '../../../features/database/debug/publish_reminder.dart';
import '../../../features/database/debug/publish_reminder_provider.dart';
import '../../updates/update_providers.dart';
import '../providers/app_version_provider.dart';
import '../version_display.dart';
import 'changelog_dialog.dart';
import '../../widgets/compact_tooltip.dart';

/// Κλικ για άνοιγμα του ιστορικού αλλαγών με εμφάνιση έκδοσης.
class VersionChip extends ConsumerWidget {
  const VersionChip({super.key, required this.extended});

  /// Όταν false, συντομευμένη ετικέτα για στενό NavigationRail.
  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVer = ref.watch(appVersionProvider);
    final updateAsync = ref.watch(updateCheckProvider);
    final scheme = Theme.of(context).colorScheme;
    final updateResult = updateAsync.asData?.value;
    final updateAvailable = updateResult?.updateAvailable ?? false;
    final latestVersion = updateResult?.latestVersion;
    // Εκκρεμής (ήδη προετοιμασμένη) ενημέρωση σε αναμονή επανεκκίνησης.
    final pendingRestart =
        ref.watch(pendingUpdateProvider).asData?.value ?? false;
    // Πορτοκαλί = εκκρεμεί επανεκκίνηση· Κόκκινο = διαθέσιμη ενημέρωση.
    final showBadge =
        pendingRestart || (updateAvailable && updateResult?.manifest != null);
    final badgeColor = pendingRestart ? Colors.orange : Colors.red;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (IntegrityDebugSeederService.isEnabled)
          _DebugScenariosButton(
            reminder: ref.watch(publishReminderProvider).value,
            onTap: () {
              ref
                  .read(mainNavRequestProvider.notifier)
                  .request(
                    const MainNavRequest(
                      destination: MainNavDestination.debugScenarios,
                    ),
                  );
            },
          ),
        asyncVer.when(
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
              message: versionChipTooltip(
                version,
                availableUpdateVersion: updateAvailable ? latestVersion : null,
              ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: scheme.primary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                          textAlign: TextAlign.center,
                        ),
                        if (showBadge)
                          Positioned(
                            right: -6,
                            top: -4,
                            child: Container(
                              key: const Key('version_update_badge'),
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: badgeColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Κουμπί «Σενάρια σφαλμάτων» με σήμα υπενθύμισης δημοσίευσης.
///
/// Το σήμα είναι **κίτρινο** και όχι κόκκινο: το εικονίδιο έκδοσης από κάτω
/// χρησιμοποιεί ήδη κόκκινο (διαθέσιμη ενημέρωση) και πορτοκαλί (εκκρεμεί
/// επανεκκίνηση). Δύο σήματα σε απόσταση λίγων pixel πρέπει να ξεχωρίζουν —
/// και το κίτρινο σημαίνει ήδη «κοίτα εδώ όποτε προλάβεις» στην εφαρμογή.
class _DebugScenariosButton extends StatelessWidget {
  const _DebugScenariosButton({required this.reminder, required this.onTap});

  final PublishReminderStatus? reminder;
  final VoidCallback onTap;

  static const Color _reminderYellow = Color(0xFFFFC107);
  static const Color _reminderInk = Color(0xFF412402);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = reminder;
    final showReminder = status?.shouldRemind ?? false;

    final icon = Icon(
      Icons.bug_report_outlined,
      size: 20,
      color: scheme.error,
    );

    return CompactTooltip(
      waitDuration: const Duration(milliseconds: 600),
      showDuration: const Duration(seconds: 4),
      message: [
        'Σενάρια σφαλμάτων (Debug)',
        if (showReminder)
          status!.reasonLine!
        else
          'Δημιουργία προβληματικής βάσης για δοκιμή UX',
      ].join('\n'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: showReminder
                ? Stack(
                    clipBehavior: Clip.none,
                    children: [
                      icon,
                      Positioned(
                        right: -7,
                        top: -6,
                        child: _PublishReminderBadge(label: status!.badgeLabel),
                      ),
                    ],
                  )
                : icon,
          ),
        ),
      ),
    );
  }
}

/// Κίτρινο σήμα με το πλήθος των αδημοσίευτων αλλαγών.
class _PublishReminderBadge extends StatelessWidget {
  const _PublishReminderBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('publish_reminder_badge'),
      constraints: const BoxConstraints(minWidth: 16),
      height: 14,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _DebugScenariosButton._reminderYellow,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black87, width: 0.6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _DebugScenariosButton._reminderInk,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}
