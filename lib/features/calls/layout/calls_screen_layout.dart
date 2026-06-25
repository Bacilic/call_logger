import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/calls_layout_config.dart';
import '../../../core/models/calls_screen_cards_visibility.dart';
import '../../../core/models/remote_tool.dart';
import '../../../core/providers/settings_provider.dart';
import '../provider/call_entry_provider.dart';
import '../provider/call_header_provider.dart';
import '../provider/calls_dashboard_providers.dart';
import '../provider/notes_field_hint_provider.dart';
import '../provider/remote_paths_provider.dart';
import '../utils/call_remote_targets.dart';
import '../screens/widgets/call_header_form.dart';
import '../screens/widgets/call_status_bar.dart';
import '../screens/widgets/recent_calls_list.dart';
import '../screens/widgets/mini_map_card.dart';
import '../screens/widgets/equipment_recent_calls_panel.dart';
import '../screens/widgets/global_recent_calls_list.dart';
import '../screens/widgets/notes_sticky_field.dart';
import '../screens/widgets/category_autocomplete_field.dart';
import '../screens/widgets/remote_connection_buttons.dart';
import '../screens/widgets/user_info_card.dart';
import '../../../core/errors/call_save_exception.dart';
import '../../../core/errors/task_save_exception.dart';
import 'calls_field_groups.dart';
import 'calls_field_groups_provider.dart';
import 'calls_layout_engine.dart';
import 'calls_layout_plan.dart';

/// Expanded layout shell driven by [CallsLayoutEngine] plan.
class CallsScreenLayout extends ConsumerWidget {
  const CallsScreenLayout({super.key});

  static const double _kSharedAxisMaxWidth = 424;
  static const double _kSharedAxisMaxWidthWithRemote = 340;
  static const double _kGlobalRecentCardMaxWidth = 560;
  static const double _kScreenPadding = 16;
  static const Duration _kHeaderMoveDuration = Duration(milliseconds: 350);
  static const double _kCompactFormToRecentCardGap = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpanded = ref.watch(callsScreenIsExpandedProvider);
    final anyGroupActive = ref.watch(
      callsFieldGroupsProvider.select((g) => g.anyGroupActive),
    );
    final tkOpen = ref.watch(showGlobalCallsToggleProvider);
    final cardsVis = ref
        .watch(callsScreenCardsVisibilityProvider)
        .maybeWhen(
          data: (v) => v,
          orElse: () => CallsScreenCardsVisibility.defaults,
        );
    final showExpandedPlanBody = anyGroupActive ||
        (cardsVis.showGlobalRecentCard && tkOpen);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final innerHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - 2 * _kScreenPadding)
                .clamp(0.0, double.infinity)
            : double.infinity;

        return Padding(
          padding: const EdgeInsets.all(_kScreenPadding),
          child: SizedBox(
            width: width,
            height: innerHeight.isFinite ? innerHeight : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: _CallsMainContent(
                    isExpanded: isExpanded,
                    showExpandedPlanBody: showExpandedPlanBody,
                    showGlobalRecentCard: cardsVis.showGlobalRecentCard,
                  ),
                ),
                if (cardsVis.showGlobalRecentCard && isExpanded)
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: _TkBottomRightAnchor(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Κύριο περιεχόμενο: συμπτυγμένα κεντραρισμένα πεδία ή αναπτυγμένη κεφαλίδα + πλέγμα.
class _CallsMainContent extends StatelessWidget {
  const _CallsMainContent({
    required this.isExpanded,
    required this.showExpandedPlanBody,
    required this.showGlobalRecentCard,
  });

  final bool isExpanded;
  final bool showExpandedPlanBody;
  final bool showGlobalRecentCard;

  @override
  Widget build(BuildContext context) {
    final duration = Platform.isWindows
        ? CallsScreenLayout._kHeaderMoveDuration
        : Duration.zero;

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: isExpanded ? Alignment.topCenter : Alignment.center,
          fit: StackFit.expand,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      child: isExpanded
          ? Column(
              key: const ValueKey('expanded'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CallHeaderForm(),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: showExpandedPlanBody
                        ? const _ExpandedPlanBody()
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            )
          : SizedBox.expand(
              key: const ValueKey('compact'),
              child: _CompactCallsLayout(
                showGlobalRecentCard: showGlobalRecentCard,
              ),
            ),
    );
  }
}

/// Συμπτυγμένη όψη: η κάρτα ΤΚ στη ροή layout (όχι overlay) ώστε να σπρώχνει τα πεδία πάνω.
class _CompactCallsLayout extends ConsumerWidget {
  const _CompactCallsLayout({required this.showGlobalRecentCard});

  final bool showGlobalRecentCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showGlobal = ref.watch(showGlobalCallsToggleProvider);
    final cardOpen = showGlobalRecentCard && showGlobal;
    final duration = Platform.isWindows
        ? CallsScreenLayout._kHeaderMoveDuration
        : Duration.zero;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const CallHeaderForm(
              compactFieldCentering: true,
              compactExternalVerticalCentering: true,
            ),
            AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: cardOpen
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(
                          height: CallsScreenLayout._kCompactFormToRecentCardGap,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth:
                                  CallsScreenLayout._kGlobalRecentCardMaxWidth,
                            ),
                            child: const GlobalRecentCallsList(),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (!cardOpen) const Spacer(),
          ],
        ),
        if (showGlobalRecentCard && !showGlobal)
          const Positioned(
            right: 0,
            bottom: 0,
            child: _GlobalRecentToggle(showExpanded: false),
          ),
      ],
    );
  }
}

/// Διακόπτης ΤΚ — κάτω δεξιά μόνο στην αναπτυγμένη όψη όταν η κάρτα είναι κλειστή.
/// Ανοιχτή αναπτυγμένη: κάρτα στο πλάνο. Συμπτυγμένη: [_CompactCallsLayout].
class _TkBottomRightAnchor extends ConsumerWidget {
  const _TkBottomRightAnchor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showGlobal = ref.watch(showGlobalCallsToggleProvider);
    if (showGlobal) return const SizedBox.shrink();
    return const _GlobalRecentToggle(showExpanded: false);
  }
}

class _ExpandedPlanBody extends ConsumerWidget {
  const _ExpandedPlanBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(callsFieldGroupsProvider);
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

    final selectedEquipmentCode =
        header.selectedEquipment?.code?.trim() ?? header.equipmentText.trim();
    final showRemoteButtons =
        !hideRemoteButtons &&
        groups.isEquipmentGroupActive &&
        (header.equipmentText.trim().isNotEmpty ||
            header.selectedEquipment != null);

    final callerId = header.selectedCaller?.id;
    final hasCallerHistory = callerId != null;
    final hasEquipmentHistory = selectedEquipmentCode.isNotEmpty &&
        groups.equipmentTier == EquipmentGroupTier.matchedRecord;

    final tkOpenInGrid = ref.watch(showGlobalCallsToggleProvider);

    final visibility = CallsLayoutVisibility.from(
      cards: cardsVis,
      groups: groups,
      showRemoteTools: showRemoteButtons,
      hasCallerHistoryData: hasCallerHistory,
      hasEquipmentHistoryData: hasEquipmentHistory,
      showGlobalRecentCard:
          cardsVis.showGlobalRecentCard && tkOpenInGrid,
    );

    final plan = CallsLayoutEngine.build(groups, visibility);
    final sharedAxisCap = showRemoteButtons
        ? CallsScreenLayout._kSharedAxisMaxWidthWithRemote
        : CallsScreenLayout._kSharedAxisMaxWidth;
    final width = MediaQuery.sizeOf(context).width - 32;
    final isNarrowViewport = width < callsLayoutNarrowViewportBreakpoint;

    return Column(
      children: [
        for (final row in plan.rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _LayoutRowWidget(
              row: row,
              isNarrowViewport: isNarrowViewport,
              sharedAxisCap: sharedAxisCap,
              sharedAxisWidth: width.clamp(180.0, sharedAxisCap).toDouble(),
              header: header,
              tools: tools,
              cardsVis: cardsVis,
              selectedEquipmentCode: selectedEquipmentCode,
              showRemoteButtons: showRemoteButtons,
            ),
          ),
      ],
    );
  }
}

class _GlobalRecentToggle extends ConsumerWidget {
  const _GlobalRecentToggle({required this.showExpanded});

  final bool showExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => ref.read(showGlobalCallsToggleProvider.notifier).toggle(),
      icon: Icon(showExpanded ? Icons.expand_less : Icons.history),
      label: const Text('Τελευταίες Κλήσεις'),
    );
  }
}

class _LayoutRowWidget extends ConsumerWidget {
  const _LayoutRowWidget({
    required this.row,
    required this.isNarrowViewport,
    required this.sharedAxisCap,
    required this.sharedAxisWidth,
    required this.header,
    required this.tools,
    required this.cardsVis,
    required this.selectedEquipmentCode,
    required this.showRemoteButtons,
  });

  final CallsLayoutRow row;
  final bool isNarrowViewport;
  final double sharedAxisCap;
  final double sharedAxisWidth;
  final CallHeaderState header;
  final List<RemoteTool> tools;
  final CallsScreenCardsVisibility cardsVis;
  final String selectedEquipmentCode;
  final bool showRemoteButtons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isNarrowViewport) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final col in row.columns)
            if (!col.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _LayoutColumnWidget(
                  column: col,
                  sharedAxisWidth: sharedAxisWidth,
                  header: header,
                  tools: tools,
                  selectedEquipmentCode: selectedEquipmentCode,
                  showRemoteButtons: showRemoteButtons,
                ),
              ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < row.columns.length; i++)
          if (!row.columns[i].isEmpty) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(
              child: _LayoutColumnWidget(
                column: row.columns[i],
                sharedAxisWidth: sharedAxisWidth,
                header: header,
                tools: tools,
                selectedEquipmentCode: selectedEquipmentCode,
                showRemoteButtons: showRemoteButtons,
              ),
            ),
          ],
      ],
    );
  }
}

class _LayoutColumnWidget extends ConsumerWidget {
  const _LayoutColumnWidget({
    required this.column,
    required this.sharedAxisWidth,
    required this.header,
    required this.tools,
    required this.selectedEquipmentCode,
    required this.showRemoteButtons,
  });

  final CallsLayoutColumn column;
  final double sharedAxisWidth;
  final CallHeaderState header;
  final List<RemoteTool> tools;
  final String selectedEquipmentCode;
  final bool showRemoteButtons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = column.slots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < slots.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _SlotWidget(
            slot: slots[i],
            sharedAxisWidth: sharedAxisWidth,
            header: header,
            tools: tools,
            selectedEquipmentCode: selectedEquipmentCode,
            showRemoteButtons: showRemoteButtons,
          ),
        ],
      ],
    );
  }
}

class _SlotWidget extends ConsumerWidget {
  const _SlotWidget({
    required this.slot,
    required this.sharedAxisWidth,
    required this.header,
    required this.tools,
    required this.selectedEquipmentCode,
    required this.showRemoteButtons,
  });

  final CallsLayoutSlot slot;
  final double sharedAxisWidth;
  final CallHeaderState header;
  final List<RemoteTool> tools;
  final String selectedEquipmentCode;
  final bool showRemoteButtons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (slot) {
      case CallsLayoutSlot.notes:
        return const SizedBox(
          width: double.infinity,
          child: NotesStickyField(),
        );
      case CallsLayoutSlot.categoryPending:
        return const _CategoryPendingRow();
      case CallsLayoutSlot.submitActions:
        return Align(
          alignment: Alignment.centerRight,
          child: _SubmitActionsRow(
            header: header,
            sharedAxisWidth: sharedAxisWidth,
          ),
        );
      case CallsLayoutSlot.remoteTools:
        if (!showRemoteButtons) return const SizedBox.shrink();
        return RemoteConnectionButtons(header: header, tools: tools);
      case CallsLayoutSlot.equipmentHistory:
        return EquipmentRecentCallsPanel(
          equipmentCode: selectedEquipmentCode,
        );
      case CallsLayoutSlot.callerCard:
        final user = header.selectedCaller;
        if (user == null || user.id == null) return const SizedBox.shrink();
        return UserInfoCard(user: user);
      case CallsLayoutSlot.callerHistory:
        final user = header.selectedCaller;
        if (user == null || user.id == null) return const SizedBox.shrink();
        return RecentCallsList(user: user);
      case CallsLayoutSlot.map:
        return MiniMapCard(
          equipment: header.selectedEquipment,
          equipmentCodeText: header.equipmentText,
          phoneText: header.selectedPhone ?? '',
          user: header.selectedCaller,
          callerDisplayText: header.callerDisplayText,
          departmentId: header.selectedDepartmentId,
        );
      case CallsLayoutSlot.globalRecent:
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: CallsScreenLayout._kGlobalRecentCardMaxWidth,
          ),
          child: const GlobalRecentCallsList(),
        );
    }
  }
}

class _CategoryPendingRow extends ConsumerWidget {
  const _CategoryPendingRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPending = ref.watch(callEntryProvider.select((s) => s.isPending));
    final notesNonEmpty = ref.watch(
      callEntryProvider.select((s) => s.notes.trim().isNotEmpty),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: CategoryAutocompleteField(
              onCategoryChanged: (text, categoryId) {
                ref
                    .read(callEntryProvider.notifier)
                    .setCategory(text, categoryId: categoryId);
              },
            ),
          ),
          const SizedBox(width: 6),
          Checkbox(
            value: isPending,
            onChanged: notesNonEmpty
                ? (_) => ref.read(callEntryProvider.notifier).togglePending()
                : null,
          ),
          GestureDetector(
            onTap: notesNonEmpty
                ? ref.read(callEntryProvider.notifier).togglePending
                : () =>
                      ref.read(notesFieldHintTickProvider.notifier).requestHintFlash(),
            child: Text(
              'Εκκρεμότητα',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: notesNonEmpty
                    ? null
                    : Theme.of(context).colorScheme.onSurface.withValues(
                        alpha: 0.38,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const CallStatusBar(showPendingToggle: false),
        ],
    );
  }
}

class _SubmitActionsRow extends ConsumerWidget {
  const _SubmitActionsRow({
    required this.header,
    required this.sharedAxisWidth,
  });

  final CallHeaderState header;
  final double sharedAxisWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 4,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildSubmitButton(context, ref),
        _buildClearButton(context, ref),
      ],
    );
  }

  Widget _buildSubmitButton(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(callEntryProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final submitPadding =
        const EdgeInsets.symmetric(vertical: 14, horizontal: 14);
    final primarySubmit = ElevatedButton.icon(
      onPressed: header.canSubmitCall
          ? () async {
              try {
                final ok = await notifier.submitCall();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Κλήση αποθηκεύτηκε' : 'Αποτυχία αποθήκευσης',
                    ),
                  ),
                );
              } on CallSaveException catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
              } on TaskSaveException catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
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
            )
          : ElevatedButton.styleFrom(padding: submitPadding),
      icon: const Icon(Icons.save_alt),
      label: const Text('Καταγραφή'),
    );
    return header.canSubmitCall
        ? primarySubmit
        : Tooltip(
            message:
                'Συμπληρώστε ένα αριθμό τηλεφώνου ώστε να είναι δυνατή η καταγραφή της κλήσης',
            child: primarySubmit,
          );
  }

  Widget _buildClearButton(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.cleaning_services_outlined),
      label: const Text('Εκκαθάριση'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),
      onPressed: () {
        ref.read(callHeaderProvider.notifier).clearAll();
        ref.read(callEntryProvider.notifier).reset();
        ref.read(callsFieldConfirmationsProvider.notifier).resetAll();
        ref.read(callsScreenExpandedLatchProvider.notifier).release();
      },
    );
  }
}
