import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/calls_screen_cards_visibility.dart';
import '../../../core/models/remote_tool.dart';
import '../../../core/providers/settings_provider.dart';
import '../provider/call_entry_provider.dart';
import '../provider/call_header_provider.dart';
import '../provider/notes_field_hint_provider.dart';
import '../provider/remote_paths_provider.dart';
import '../utils/call_remote_targets.dart';
import 'widgets/call_header_form.dart';
import 'widgets/call_status_bar.dart';
import 'widgets/recent_calls_list.dart';
import 'widgets/equipment_info_card.dart';
import 'widgets/equipment_recent_calls_panel.dart';
import 'widgets/global_recent_calls_list.dart';
import 'widgets/notes_sticky_field.dart';
import 'widgets/category_autocomplete_field.dart';
import 'widgets/remote_connection_buttons.dart';
import 'widgets/user_info_card.dart';

/// Οθόνη εισαγωγής κλήσης: Εσωτερικό, lookup 3 ψηφία, κάρτα χρήστη, ιστορικό, sticky note, σημειώσεις, Enter = αποθήκευση + focus πίσω.
/// Το focus από shortcut (Quick Capture / Ctrl+Alt+L) γίνεται μέσω root Shortcuts/Actions σε microtask,
/// ώστε να μην συμπέσει με autofocus ή rebuild (βλ. docs/KEYBOARD_AND_FOCUS.md).
class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});
  static const double _kSharedAxisMaxWidth = 424;
  static const double _kSharedAxisMaxWidthWithRemote = 340;
  static const double _kGlobalRecentCardMaxWidth = 560;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = ref.watch(callHeaderProvider);
    final tools = ref.watch(remoteToolsCatalogProvider).value ?? <RemoteTool>[];
    final allToolsAsync = ref.watch(remoteToolsAllCatalogProvider);
    final hideRemoteButtons = allToolsAsync.maybeWhen(
      data: (all) => CallRemoteTargets.shouldHideRemoteConnectionButtons(
        header.selectedEquipment,
        all,
      ),
      orElse: () => false,
    );
    final cardsVis = ref
        .watch(callsScreenCardsVisibilityProvider)
        .maybeWhen(
          data: (v) => v,
          orElse: () => CallsScreenCardsVisibility.defaults,
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final selectedEquipmentCode =
              header.selectedEquipment?.code?.trim() ??
              header.equipmentText.trim();
          final showEquipmentHistoryPanel = selectedEquipmentCode.isNotEmpty;
          final showEquipmentRecentPanel =
              showEquipmentHistoryPanel && cardsVis.showEquipmentRecentPanel;
          final showRemoteButtons =
              !hideRemoteButtons &&
              (header.equipmentText.trim().isNotEmpty ||
                  header.selectedEquipment != null);
          final leftContentMaxWidth = showRemoteButtons ? 760.0 : 700.0;
          return SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CallHeaderForm(),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, middleConstraints) {
                    final compact = middleConstraints.maxWidth < 980;
                    final sharedAxisCap = showRemoteButtons
                        ? _kSharedAxisMaxWidthWithRemote
                        : _kSharedAxisMaxWidth;
                    final sharedAxisWidth = middleConstraints.maxWidth
                        .clamp(180.0, sharedAxisCap)
                        .toDouble();
                    final leftContent = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: sharedAxisWidth,
                                  child: const NotesStickyField(),
                                ),
                              ),
                            ),
                            if (showRemoteButtons) ...[
                              const SizedBox(width: 12),
                              Flexible(
                                fit: FlexFit.loose,
                                child: RemoteConnectionButtons(
                                  header: header,
                                  tools: tools,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildActionsRow(
                          context,
                          ref,
                          header,
                          sharedAxisWidth: sharedAxisWidth,
                        ),
                      ],
                    );

                    if (!showEquipmentRecentPanel) {
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [leftContent],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            fit: FlexFit.loose,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: leftContentMaxWidth,
                              ),
                              child: leftContent,
                            ),
                          ),
                        ],
                      );
                    }

                    if (compact || !showEquipmentHistoryPanel) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          leftContent,
                          if (showEquipmentHistoryPanel) ...[
                            const SizedBox(height: 12),
                            EquipmentRecentCallsPanel(
                              equipmentCode: selectedEquipmentCode,
                            ),
                          ],
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: leftContentMaxWidth,
                            ),
                            child: leftContent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 300,
                          child: EquipmentRecentCallsPanel(
                            equipmentCode: selectedEquipmentCode,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, bottomConstraints) {
                    final wrapMaxWidth = bottomConstraints.maxWidth.isFinite
                        ? bottomConstraints.maxWidth
                        : MediaQuery.sizeOf(context).width;
                    final compactBottom = wrapMaxWidth < 980;
                    final hasUserCard = header.selectedCaller != null;
                    final hasEquipmentCard =
                        header.selectedEquipment != null ||
                        header.equipmentText.trim().isNotEmpty;
                    final hasRecentCallsCard =
                        header.selectedCaller?.id != null;
                    if (compactBottom) {
                      return Wrap(
                        spacing: 16.0,
                        runSpacing: 16.0,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        children: [
                          if (hasUserCard && cardsVis.showUserCard)
                            UserInfoCard(user: header.selectedCaller!),
                          if (hasEquipmentCard && cardsVis.showEquipmentCard)
                            EquipmentInfoCard(
                              equipment: header.selectedEquipment,
                              equipmentCodeText: header.equipmentText,
                            ),
                          if (hasRecentCallsCard &&
                              cardsVis.showEmployeeRecentCard)
                            RecentCallsList(user: header.selectedCaller!),
                          if (cardsVis.showGlobalRecentCard)
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _kGlobalRecentCardMaxWidth,
                              ),
                              child: const GlobalRecentCallsList(),
                            ),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                spacing: 16.0,
                                runSpacing: 16.0,
                                crossAxisAlignment: WrapCrossAlignment.start,
                                children: [
                                  if (hasUserCard && cardsVis.showUserCard)
                                    UserInfoCard(user: header.selectedCaller!),
                                  if (hasEquipmentCard &&
                                      cardsVis.showEquipmentCard)
                                    EquipmentInfoCard(
                                      equipment: header.selectedEquipment,
                                      equipmentCodeText: header.equipmentText,
                                    ),
                                ],
                              ),
                              if (hasRecentCallsCard &&
                                  cardsVis.showEmployeeRecentCard)
                                RecentCallsList(user: header.selectedCaller!),
                            ],
                          ),
                        ),
                        if (cardsVis.showGlobalRecentCard) ...[
                          const SizedBox(width: 16),
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _kGlobalRecentCardMaxWidth,
                            ),
                            child: const GlobalRecentCallsList(),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Widget _buildActionsRow(
  BuildContext context,
  WidgetRef ref,
  CallHeaderState header, {
  required double sharedAxisWidth,
}) {
  final notifier = ref.read(callEntryProvider.notifier);
  final isPending = ref.watch(callEntryProvider.select((s) => s.isPending));
  final notesNonEmpty = ref.watch(
    callEntryProvider.select((s) => s.notes.trim().isNotEmpty),
  );
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final submitPadding = const EdgeInsets.symmetric(
    vertical: 14,
    horizontal: 14,
  );
  final primarySubmit = ElevatedButton.icon(
    onPressed: header.canSubmitCall
        ? () async {
            final ok = await notifier.submitCall();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok ? 'Κλήση αποθηκεύτηκε' : 'Αποτυχία αποθήκευσης',
                  ),
                ),
              );
            }
          }
        : null,
    style: header.canSubmitCall
        ? ElevatedButton.styleFrom(
            padding: submitPadding,
            backgroundColor: scheme.primary,
            foregroundColor: Colors.white,
            elevation: 1,
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          )
        : ElevatedButton.styleFrom(padding: submitPadding),
    icon: const Icon(Icons.save_alt),
    label: const Text('Καταγραφή'),
  );
  final mainSubmit = header.canSubmitCall
      ? primarySubmit
      : Tooltip(
          message:
              'Συμπληρώστε εσωτερικό αριθμό και πρέπει να βρεθεί ο καλώντας',
          child: primarySubmit,
        );

  final pendingToggle = SizedBox(
    height: 48,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: isPending,
          onChanged: notesNonEmpty ? (_) => notifier.togglePending() : null,
          tristate: false,
        ),
        const SizedBox(width: 4),
        MouseRegion(
          cursor: notesNonEmpty ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: notesNonEmpty
                ? notifier.togglePending
                : () => ref
                      .read(notesFieldHintTickProvider.notifier)
                      .requestHintFlash(),
            child: Text(
              'Εκκρεμότητα',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: notesNonEmpty
                    ? null
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  final newCallButton = OutlinedButton.icon(
    icon: const Icon(Icons.add_call),
    label: const Text('Νέα Κλήση'),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    ),
    onPressed: () {
      ref.read(callHeaderProvider.notifier).clearAll();
      ref.read(callEntryProvider.notifier).reset();
    },
  );

  return LayoutBuilder(
    builder: (context, constraints) {
      final axisWidth = constraints.maxWidth.isFinite
          ? sharedAxisWidth.clamp(180.0, constraints.maxWidth).toDouble()
          : sharedAxisWidth;
      const actionsMinWidth = 360.0;
      final keepSingleLineWidth = axisWidth + 16.0 + actionsMinWidth;
      final narrow = constraints.maxWidth < keepSingleLineWidth;

      final category = SizedBox(
        child: CategoryAutocompleteField(
          onCategoryChanged: (text, categoryId) {
            ref
                .read(callEntryProvider.notifier)
                .setCategory(text, categoryId: categoryId);
          },
        ),
      );
      final categoryAndStatus = SizedBox(
        width: axisWidth,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: category),
            const SizedBox(width: 6),
            SizedBox(
              width: 220,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: pendingToggle,
                ),
              ),
            ),
          ],
        ),
      );
      final actionsRow = Wrap(
        spacing: 4,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const CallStatusBar(showPendingToggle: false),
          mainSubmit,
          newCallButton,
        ],
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [categoryAndStatus, const SizedBox(height: 10), actionsRow],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          categoryAndStatus,
          const SizedBox(width: 16),
          Expanded(
            child: Align(alignment: Alignment.topLeft, child: actionsRow),
          ),
        ],
      );
    },
  );
}
