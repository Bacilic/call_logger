import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../../core/widgets/section_card.dart';
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

  /// Ανώτατο πλάτος στήλης πλέγματος — ταιριάζει με εσωτερικό πλάτος [MiniMapCard].
  static const double kMapCardColumnMaxWidth = 336;

  /// Ανώτατο πλάτος στήλης για [UserInfoCard] (περιεχόμενο με [IntrinsicWidth]).
  static const double kUserInfoCardColumnMaxWidth = 400;

  /// Ανώτατο πλάτος στήλης — ταιριάζει με [RecentCallsList].
  static const double kRecentCallsCardColumnMaxWidth = 560;

  /// Ανώτατο πλάτος στήλης — ταιριάζει με [GlobalRecentCallsList].
  static const double kGlobalRecentCardColumnMaxWidth = _kGlobalRecentCardMaxWidth;

  /// Ανώτατο πλάτος στήλης για [EquipmentRecentCallsPanel].
  static const double kEquipmentRecentCardColumnMaxWidth = 560;

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
                if (isExpanded)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: _ExpandedBottomRightAnchors(
                      showGlobalRecentCard: cardsVis.showGlobalRecentCard,
                    ),
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

/// Κάτω δεξιά στην αναπτυγμένη όψη: «Εκκαθάριση» + (προαιρετικά) διακόπτης ΤΚ.
/// Στήλη για αποφυγή επικάλυψης όταν η κάρτα ΤΚ είναι κλειστή.
class _ExpandedBottomRightAnchors extends ConsumerWidget {
  const _ExpandedBottomRightAnchors({required this.showGlobalRecentCard});

  final bool showGlobalRecentCard;

  static const double _kAnchorSpacing = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showGlobal = ref.watch(showGlobalCallsToggleProvider);
    final showTkToggle = showGlobalRecentCard && !showGlobal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const _ClearFormButton(),
        if (showTkToggle) ...[
          const SizedBox(height: _kAnchorSpacing),
          const _GlobalRecentToggle(showExpanded: false),
        ],
      ],
    );
  }
}

/// Κουμπί καθαρισμού φόρμας — ανεξάρτητο από πυλώνα τηλεφώνου και slot submitActions.
class _ClearFormButton extends ConsumerWidget {
  const _ClearFormButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final isNarrowViewport = callsLayoutShouldStackColumns(
      contentWidth: width,
      plan: plan,
    );

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

    // Πυκνό πλέγμα: οι στήλες πακετάρονται κεντραρισμένες με σταθερό κενό 16px
    // αντί για ισόποσους Expanded διαδρόμους (που άφηναν μεγάλα νεκρά κενά).
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < row.columns.length; i++)
          if (!row.columns[i].isEmpty) ...[
            if (i > 0) const SizedBox(width: 16),
            Flexible(
              child: _LayoutColumnWidthCap(
                maxWidth: _layoutColumnMaxWidth(
                  row.columns[i],
                  sharedAxisCap,
                ),
                fillCappedWidth: _columnFillsCappedWidth(row.columns[i]),
                child: _LayoutColumnWidget(
                  column: row.columns[i],
                  sharedAxisWidth: sharedAxisWidth,
                  header: header,
                  tools: tools,
                  selectedEquipmentCode: selectedEquipmentCode,
                  showRemoteButtons: showRemoteButtons,
                ),
              ),
            ),
          ],
      ],
    );
  }
}

/// Περιορίζει το πλάτος στήλης σε ευρύ viewport· σε στενό χώρο το [Expanded] συνεχίζει να συρρικνώνει.
class _LayoutColumnWidthCap extends StatelessWidget {
  const _LayoutColumnWidthCap({
    required this.maxWidth,
    required this.fillCappedWidth,
    required this.child,
  });

  final double? maxWidth;
  final bool fillCappedWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (maxWidth == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cappedMax = math.min(constraints.maxWidth, maxWidth!);
        if (fillCappedWidth) {
          return SizedBox(
            width: cappedMax,
            child: child,
          );
        }
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cappedMax),
          child: child,
        );
      },
    );
  }
}

double? _layoutColumnMaxWidth(
  CallsLayoutColumn column,
  double sharedAxisCap,
) {
  double? cap;
  for (final slot in column.slots) {
    final slotCap = _layoutSlotMaxWidth(slot, sharedAxisCap);
    if (slotCap == null) continue;
    cap = cap == null ? slotCap : math.max(cap, slotCap);
  }
  return cap;
}

double? _layoutSlotMaxWidth(CallsLayoutSlot slot, double sharedAxisCap) {
  switch (slot) {
    case CallsLayoutSlot.map:
      return CallsScreenLayout.kMapCardColumnMaxWidth;
    case CallsLayoutSlot.callerCard:
      return CallsScreenLayout.kUserInfoCardColumnMaxWidth;
    case CallsLayoutSlot.callerHistory:
      return CallsScreenLayout.kRecentCallsCardColumnMaxWidth;
    case CallsLayoutSlot.globalRecent:
      return CallsScreenLayout.kGlobalRecentCardColumnMaxWidth;
    case CallsLayoutSlot.equipmentHistory:
      return CallsScreenLayout.kEquipmentRecentCardColumnMaxWidth;
    case CallsLayoutSlot.notes:
    case CallsLayoutSlot.categoryPending:
    case CallsLayoutSlot.submitActions:
    case CallsLayoutSlot.remoteTools:
      return sharedAxisCap;
  }
}

bool _columnFillsCappedWidth(CallsLayoutColumn column) {
  for (final slot in column.slots) {
    switch (slot) {
      case CallsLayoutSlot.notes:
      case CallsLayoutSlot.categoryPending:
      case CallsLayoutSlot.submitActions:
      case CallsLayoutSlot.remoteTools:
        return true;
      case CallsLayoutSlot.map:
      case CallsLayoutSlot.callerCard:
      case CallsLayoutSlot.callerHistory:
      case CallsLayoutSlot.globalRecent:
      case CallsLayoutSlot.equipmentHistory:
        continue;
    }
  }
  return false;
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

  /// Slots που ντύνονται μαζί σε κοινή [SectionCard] («Στοιχεία κλήσης»).
  static const Set<CallsLayoutSlot> _kFormClusterSlots = {
    CallsLayoutSlot.notes,
    CallsLayoutSlot.categoryPending,
  };

  Widget _slotWidget(CallsLayoutSlot slot) {
    return _SlotWidget(
      slot: slot,
      sharedAxisWidth: sharedAxisWidth,
      header: header,
      tools: tools,
      selectedEquipmentCode: selectedEquipmentCode,
      showRemoteButtons: showRemoteButtons,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = column.slots;

    // Συνεχόμενα slots φόρμας (σημειώσεις + κατηγορία/εκκρεμότητα)
    // ομαδοποιούνται σε μία SectionCard ώστε να μην αιωρούνται «γυμνά».
    final children = <Widget>[];
    var i = 0;
    while (i < slots.length) {
      if (_kFormClusterSlots.contains(slots[i])) {
        final run = <CallsLayoutSlot>[];
        while (i < slots.length && _kFormClusterSlots.contains(slots[i])) {
          run.add(slots[i]);
          i++;
        }
        children.add(
          SectionCard(
            icon: Icons.edit_note,
            title: 'Στοιχεία κλήσης',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < run.length; j++) ...[
                  if (j > 0) const SizedBox(height: 12),
                  _slotWidget(run[j]),
                ],
              ],
            ),
          ),
        );
      } else {
        children.add(_slotWidget(slots[i]));
        i++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var k = 0; k < children.length; k++) ...[
          if (k > 0) const SizedBox(height: 12),
          children[k],
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
        // Η κάρτα αγκαλιάζει το περιεχόμενό της — όχι νεκρό κενό στα δεξιά.
        return Align(
          alignment: Alignment.topLeft,
          child: SectionCard(
            icon: Icons.desktop_windows_outlined,
            title: 'Απομακρυσμένη σύνδεση',
            accent: const Color(0xFF1976D2),
            hugContent: true,
            contentPadding: EdgeInsets.zero,
            child: RemoteConnectionButtons(
              header: header,
              tools: tools,
              framed: false,
            ),
          ),
        );
      case CallsLayoutSlot.equipmentHistory:
        return EquipmentRecentCallsPanel(
          equipmentCode: selectedEquipmentCode,
        );
      case CallsLayoutSlot.callerCard:
        final user = header.selectedCaller;
        if (user == null || user.id == null) return const SizedBox.shrink();
        // Η κάρτα αγκαλιάζει το περιεχόμενό της — όχι νεκρό κενό στα δεξιά.
        return Align(
          alignment: Alignment.topLeft,
          child: UserInfoCard(user: user),
        );
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final trailing = Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              value: isPending,
              onChanged: notesNonEmpty
                  ? (_) => ref.read(callEntryProvider.notifier).togglePending()
                  : null,
            ),
            GestureDetector(
              onTap: notesNonEmpty
                  ? ref.read(callEntryProvider.notifier).togglePending
                  : () => ref
                        .read(notesFieldHintTickProvider.notifier)
                        .requestHintFlash(),
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
            const CallStatusBar(showPendingToggle: false),
          ],
        );

        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CategoryAutocompleteField(
                onCategoryChanged: (text, categoryId) {
                  ref
                      .read(callEntryProvider.notifier)
                      .setCategory(text, categoryId: categoryId);
                },
              ),
              const SizedBox(height: 8),
              trailing,
            ],
          );
        }

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
            trailing,
          ],
        );
      },
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

}
