import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/settings_provider.dart';
import '../../../../core/providers/spell_check_provider.dart';
import '../../../../core/utils/run_after_next_frame.dart';
import '../../../../core/widgets/lexicon_spell_menu_helper.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../provider/call_entry_provider.dart';
import '../../provider/notes_field_hint_provider.dart';
import '../../utils/notes_solution_split.dart';

/// Πεδίο σημειώσεων σε στυλ post-it (εκτός state για αποφυγή διαρροής μνήμης).
///
/// ΚΑΝΟΝΑΣ: Το τικ «Εκκρεμότητα» ζει ΜΟΝΙΜΑ μέσα στο χαρτί σημειώσεων
/// (υποσέλιδο, κάτω-αριστερά, απέναντι από τον μετρητή χαρακτήρων), γιατί
/// εκκρεμότητα δημιουργείται ΜΟΝΟ από τις σημειώσεις — η αποθήκευση απαιτεί
/// μη κενές σημειώσεις για να επιτρέψει εκκρεμότητα. Καμία μελλοντική
/// αναδιάταξη της οθόνης δεν επιτρέπεται να βγάλει το τικ έξω από το χαρτί.
///
/// Το χαρτί ΔΕΝ ντύνεται ποτέ με κάρτα/τίτλο — είναι αυτόνομο widget που
/// μοιάζει μόνο με χαρτί σημειώσεων (ρητή απόφαση σχεδίασης).
class NotesStickyField extends ConsumerStatefulWidget {
  const NotesStickyField({super.key});

  @override
  ConsumerState<NotesStickyField> createState() => NotesStickyFieldState();
}

class NotesStickyFieldState extends ConsumerState<NotesStickyField> {
  late final SpellCheckController _controller;
  late final SpellCheckController _solutionController;
  final FocusNode _focusNode = FocusNode();
  final FocusNode _solutionFocusNode = FocusNode();

  /// Η ζώνη «Λύση» είναι ανοιχτή. Ανοίγει από το chip ή το Ctrl+Enter και
  /// κλείνει μόνη της όταν αδειάσει και χάσει την εστίαση — κλειστή δεν
  /// ξοδεύει χώρο στο χαρτί.
  bool _solutionZoneVisible = false;
  bool _flashHighlight = false;
  bool _flashPlaying = false;
  Offset? _lastSecondaryPointerGlobal;

  @override
  void initState() {
    super.initState();
    final entry = ref.read(callEntryProvider);
    _controller = SpellCheckController();
    _controller.text = entry.notes;
    _solutionController = SpellCheckController();
    _solutionController.text = entry.solution;
    _solutionZoneVisible = entry.solution.trim().isNotEmpty;
    _solutionFocusNode.addListener(_maybeCollapseSolutionZone);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _solutionFocusNode.removeListener(_maybeCollapseSolutionZone);
    _solutionFocusNode.dispose();
    _controller.dispose();
    _solutionController.dispose();
    super.dispose();
  }

  void _maybeCollapseSolutionZone() {
    if (_solutionFocusNode.hasFocus) return;
    if (_solutionController.text.trim().isNotEmpty) return;
    if (!_solutionZoneVisible || !mounted) return;
    setState(() => _solutionZoneVisible = false);
  }

  /// Άνοιγμα της ζώνης «Λύση» — από το chip ή το Ctrl+Enter.
  ///
  /// Όταν ο κέρσορας πατά σε γεμάτη γραμμή των σημειώσεων και η ζώνη είναι
  /// ακόμη άδεια, η γραμμή **κατεβαίνει**: είναι η παλιά συνήθεια «πρόβλημα
  /// στην πρώτη γραμμή, λύση στη δεύτερη», αυτοματοποιημένη. Σε κάθε άλλη
  /// περίπτωση απλώς ανοίγει η ζώνη και η εστίαση πάει εκεί.
  void _activateSolutionZone() {
    final notifier = ref.read(callEntryProvider.notifier);
    if (_focusNode.hasFocus && _solutionController.text.trim().isEmpty) {
      final selection = _controller.selection;
      final cursor = selection.isValid
          ? selection.extentOffset
          : _controller.text.length;
      final split = NotesSolutionSplit.extractCurrentLine(
        _controller.text,
        cursor,
      );
      if (split.movedLine.isNotEmpty) {
        _controller.value = TextEditingValue(
          text: split.notes,
          selection: TextSelection.collapsed(offset: split.notes.length),
        );
        notifier.setNotes(split.notes);
        _solutionController.text = split.movedLine;
        notifier.setSolution(split.movedLine);
      }
    }
    setState(() => _solutionZoneVisible = true);
    // Η εστίαση ζητείται αφού χτιστεί το πεδίο που μόλις έγινε ορατό.
    unawaited(
      runAfterNextFrame(() {
        if (!mounted) return;
        _solutionFocusNode.requestFocus();
        _solutionController.selection = TextSelection.collapsed(
          offset: _solutionController.text.length,
        );
      }),
    );
  }

  void _replaceWordAtCursor(
    TextEditingValue v,
    String replacement, {
    required SpellCheckController controller,
    required void Function(String) commit,
  }) {
    var offset = v.selection.extentOffset;
    if (offset < 0) offset = 0;
    if (offset > v.text.length) offset = v.text.length;
    final t = v.text;
    for (final m in SpellCheckController.wordPattern.allMatches(t)) {
      if (offset >= m.start && offset <= m.end) {
        final nt = t.replaceRange(m.start, m.end, replacement);
        controller.value = TextEditingValue(
          text: nt,
          selection: TextSelection.collapsed(
            offset: m.start + replacement.length,
          ),
        );
        commit(nt);
        controller.refreshSpellDecorations();
        return;
      }
    }
  }

  /// Κοινό μενού ορθογράφου για τα δύο πεδία του χαρτιού (σημειώσεις, λύση):
  /// ίδιος έλεγχος, ίδιες προτάσεις — αλλάζει μόνο πού γράφεται η διόρθωση.
  Widget _contextMenuBuilderFor(
    BuildContext context,
    EditableTextState state, {
    required SpellCheckController controller,
    required void Function(String) commit,
  }) {
    final v = state.textEditingValue;
    var offset = v.selection.extentOffset;
    if (offset < 0) offset = 0;
    if (offset > v.text.length) offset = v.text.length;
    final global = _lastSecondaryPointerGlobal;
    if (global != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !state.mounted) return;
        state.renderEditable.selectPositionAt(
          from: global,
          cause: SelectionChangedCause.tap,
        );
      });
    }
    _lastSecondaryPointerGlobal = null;

    final extras = <ContextMenuButtonItem>[];
    final spellOn = ref.read(enableSpellCheckProvider).value ?? true;
    final spell = switch (ref.read(spellCheckServiceProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    if (spellOn && spell != null && controller.isWordMisspelledAt(v, offset)) {
      final raw = controller.wordAtCursorOffset(v, offset);
      if (raw != null) {
        for (final sug in spell.getSuggestions(raw)) {
          extras.add(
            ContextMenuButtonItem(
              label: sug,
              onPressed: () {
                state.hideToolbar();
                _replaceWordAtCursor(
                  v,
                  sug,
                  controller: controller,
                  commit: commit,
                );
              },
            ),
          );
        }
        extras.add(
          LexiconSpellMenuHelper.googleSpellSearchButtonItem(
            word: raw,
            onBeforeLaunch: () => state.hideToolbar(),
          ),
        );
        extras.add(
          ContextMenuButtonItem(
            label: 'Προσθήκη στο λεξικό μου',
            onPressed: () {
              state.hideToolbar();
              unawaited(() async {
                await spell.insertUserWord(raw);
                if (mounted) controller.refreshSpellDecorations();
              }());
            },
          ),
        );
      }
    }

    final defaults = state.contextMenuButtonItems
        .where((e) => e.onPressed != null)
        .toList();
    final items = <ContextMenuButtonItem>[...extras, ...defaults];

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final platform = Theme.of(context).platform;
    final useDesktopLayout =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.fuchsia ||
        platform == TargetPlatform.macOS;
    final anchors = state.contextMenuAnchors;

    if (useDesktopLayout) {
      return _desktopNotesContextMenu(context, items, anchors);
    }
    return TextSelectionToolbar(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      toolbarBuilder: (ctx, child) {
        return Material(
          borderRadius: BorderRadius.circular(8),
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
          child: IntrinsicWidth(child: child),
        );
      },
      children: [
        for (final item in items)
          InkWell(
            onTap: item.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _desktopNotesContextMenu(
    BuildContext context,
    List<ContextMenuButtonItem> items,
    TextSelectionToolbarAnchors anchors,
  ) {
    const kToolbarScreenPadding = 8.0;
    final paddingAbove =
        MediaQuery.paddingOf(context).top + kToolbarScreenPadding;
    final localAdjustment = Offset(kToolbarScreenPadding, paddingAbove);
    final buttonWidgets = AdaptiveTextSelectionToolbar.getAdaptiveButtons(
      context,
      items,
    ).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        kToolbarScreenPadding,
        paddingAbove,
        kToolbarScreenPadding,
        kToolbarScreenPadding,
      ),
      child: CustomSingleChildLayout(
        delegate: DesktopTextSelectionToolbarLayoutDelegate(
          anchor: anchors.primaryAnchor - localAdjustment,
        ),
        child: Material(
          borderRadius: BorderRadius.circular(8),
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: buttonWidgets,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playDoubleFlash() async {
    if (_flashPlaying || !mounted) return;
    _flashPlaying = true;
    _focusNode.requestFocus();
    try {
      for (var i = 0; i < 2; i++) {
        if (!mounted) return;
        setState(() => _flashHighlight = true);
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (!mounted) return;
        setState(() => _flashHighlight = false);
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    } finally {
      _flashPlaying = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(spellCheckServiceProvider, (prev, next) {
      next.whenData((s) {
        if (mounted) {
          _controller.attachSpellService(s);
          _solutionController.attachSpellService(s);
        }
      });
    });
    ref.listen(enableSpellCheckProvider, (prev, next) {
      next.whenData((e) {
        if (mounted) {
          _controller.setSpellCheckEnabled(e);
          _solutionController.setSpellCheckEnabled(e);
        }
      });
    });

    final spellAsync = ref.watch(spellCheckServiceProvider);
    final spellEnabledAsync = ref.watch(enableSpellCheckProvider);
    spellAsync.whenData((s) {
      _controller.attachSpellService(s);
      _solutionController.attachSpellService(s);
    });
    spellEnabledAsync.whenData((e) {
      _controller.setSpellCheckEnabled(e);
      _solutionController.setSpellCheckEnabled(e);
    });

    final notes = ref.watch(callEntryProvider.select((s) => s.notes));
    final solution = ref.watch(callEntryProvider.select((s) => s.solution));
    ref.listen<int>(notesFieldHintTickProvider, (prev, next) {
      if (prev != null && next > prev) {
        _playDoubleFlash();
      }
    });
    if (notes.isEmpty && _controller.text.isNotEmpty) {
      _controller.text = '';
    }
    // Reset/Εκκαθάριση φόρμας: μαζί με τις σημειώσεις αδειάζει και η λύση,
    // και η ζώνη κλείνει ώστε το επόμενο χαρτί να ξεκινά καθαρό.
    if (solution.isEmpty && _solutionController.text.isNotEmpty) {
      _solutionController.text = '';
      _solutionZoneVisible = false;
    }
    final scheme = Theme.of(context).colorScheme;
    // Το πλάτος του χαρτιού το ορίζει το layout της οθόνης (οροφή ~700px,
    // βλ. CallsScreenLayout.kNotesColumnMaxWidth) — το κείμενο το γεμίζει.
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 400.0;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9C4),
            borderRadius: BorderRadius.circular(4),
            border: _flashHighlight
                ? Border.all(color: scheme.primary, width: 3)
                : null,
            boxShadow: [
              BoxShadow(
                color: _flashHighlight
                    ? scheme.primary.withValues(alpha: 0.35)
                    : Colors.black12,
                blurRadius: _flashHighlight ? 10 : 6,
                offset: const Offset(2, 4),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Listener(
              onPointerDown: (event) {
                if (event.kind == PointerDeviceKind.mouse &&
                    event.buttons == kSecondaryMouseButton) {
                  _lastSecondaryPointerGlobal = event.position;
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): _activateSolutionZone,
                    },
                    child: TextField(
                      focusNode: _focusNode,
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Περιγραφή κλήσης...',
                        hintStyle: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: true,
                        fillColor: Colors.transparent,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                      ),
                      minLines: 2,
                      maxLines: 5,
                      // Guardrail for future text-snippet expansion (e.g. .pwd):
                      // expansion logic must respect remaining characters.
                      maxLength: NotesLengthBudget.limitFor(
                        currentLength: notes.length,
                        otherLength: solution.length,
                      ),
                      buildCounter: _noCounter,
                      spellCheckConfiguration:
                          const SpellCheckConfiguration.disabled(),
                      contextMenuBuilder: (context, state) =>
                          _contextMenuBuilderFor(
                            context,
                            state,
                            controller: _controller,
                            commit: (nt) => ref
                                .read(callEntryProvider.notifier)
                                .setNotes(nt),
                          ),
                      onChanged: (value) =>
                          ref.read(callEntryProvider.notifier).setNotes(value),
                    ),
                  ),
                  if (_solutionZoneVisible) ...[
                    const SizedBox(height: 6),
                    const _SolutionZoneHeader(),
                    TextField(
                      focusNode: _solutionFocusNode,
                      controller: _solutionController,
                      decoration: const InputDecoration(
                        hintText: 'Λύση...',
                        hintStyle: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: true,
                        fillColor: Colors.transparent,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                      ),
                      minLines: 1,
                      maxLines: 4,
                      maxLength: NotesLengthBudget.limitFor(
                        currentLength: solution.length,
                        otherLength: notes.length,
                      ),
                      buildCounter: _noCounter,
                      spellCheckConfiguration:
                          const SpellCheckConfiguration.disabled(),
                      contextMenuBuilder: (context, state) =>
                          _contextMenuBuilderFor(
                            context,
                            state,
                            controller: _solutionController,
                            commit: (nt) => ref
                                .read(callEntryProvider.notifier)
                                .setSolution(nt),
                          ),
                      onChanged: (value) => ref
                          .read(callEntryProvider.notifier)
                          .setSolution(value),
                    ),
                  ],
                  const SizedBox(height: 2),
                  // Υποσέλιδο χαρτιού: Εκκρεμότητα αριστερά, chip Λύσης στη
                  // μέση, μετρητής δεξιά.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(child: _StickyPendingToggle()),
                      const SizedBox(width: 4),
                      _SolutionChip(
                        active:
                            _solutionZoneVisible ||
                            solution.trim().isNotEmpty,
                        onPressed: _activateSolutionZone,
                      ),
                      const SizedBox(width: 8),
                      // ΕΝΑΣ μετρητής για όλο το χαρτί: περιγραφή και λύση
                      // μοιράζονται το ίδιο όριο, οπότε ένας αριθμός λέει
                      // ακριβώς πόσο χώρο απομένει συνολικά.
                      IgnorePointer(
                        child: ListenableBuilder(
                          listenable: Listenable.merge([
                            _controller,
                            _solutionController,
                          ]),
                          builder: (context, _) {
                            final used =
                                _controller.text.length +
                                _solutionController.text.length;
                            return Text(
                              '$used / $kNotesTotalMaxLength',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Κρύβει τον ενσωματωμένο μετρητή του [TextField]: το χαρτί έχει δικό του,
/// κοινό για τα δύο πεδία, στο υποσέλιδο.
Widget? _noCounter(
  BuildContext context, {
  required int currentLength,
  required int? maxLength,
  required bool isFocused,
}) => null;

/// Κεφαλίδα της ζώνης «Λύση»: διαχωριστικό και ετικέτα.
///
/// Χωρίς δικό της μετρητή — το όριο είναι κοινό για όλο το χαρτί και μετριέται
/// μία φορά, στο υποσέλιδο. Δύο αριθμοί δίπλα-δίπλα δεν έλεγαν ποιος μετρά τι.
class _SolutionZoneHeader extends StatelessWidget {
  const _SolutionZoneHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.healing, size: 13, color: muted),
        const SizedBox(width: 4),
        Text(
          'Λύση',
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(color: muted.withValues(alpha: 0.4), height: 1),
        ),
      ],
    );
  }
}

/// Το chip «Λύση» στο υποσέλιδο του χαρτιού, δίπλα στην Εκκρεμότητα.
///
/// Ανοίγει τη ζώνη Λύσης (βλ. [NotesStickyFieldState._activateSolutionZone])·
/// γεμάτο όταν η κλήση έχει ήδη λύση, περίγραμμα όταν όχι.
class _SolutionChip extends StatelessWidget {
  const _SolutionChip({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      waitDuration: const Duration(milliseconds: 600),
      message:
          'Η γραμμή του κέρσορα γίνεται η Λύση της κλήσης (Ctrl+Enter)',
      child: Material(
        color: active ? muted : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: muted.withValues(alpha: 0.6)),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.healing,
                  size: 13,
                  color: active ? theme.colorScheme.surface : muted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Λύση',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: active ? theme.colorScheme.surface : muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Τικ «Εκκρεμότητα» μέσα στο χαρτί σημειώσεων (βλ. ΚΑΝΟΝΑ στην κλάση
/// [NotesStickyField]): ενεργό μόνο όταν υπάρχουν σημειώσεις· με άδειο χαρτί
/// το πάτημα αναβοσβήνει το πεδίο ως υπόδειξη.
class _StickyPendingToggle extends ConsumerWidget {
  const _StickyPendingToggle();

  /// Σκούρο πορτοκαλί «προσοχής» όταν η εκκρεμότητα είναι ενεργή —
  /// διακριτό πάνω στο κίτρινο χαρτί.
  static const Color _kActiveColor = Color(0xFFB25E00);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPending = ref.watch(callEntryProvider.select((s) => s.isPending));
    final notesNonEmpty = ref.watch(
      callEntryProvider.select((s) => s.notes.trim().isNotEmpty),
    );
    final theme = Theme.of(context);

    final labelColor = !notesNonEmpty
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : isPending
        ? _kActiveColor
        : theme.colorScheme.onSurfaceVariant;

    final label = Text(
      'Εκκρεμότητα',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: labelColor,
        fontWeight: isPending ? FontWeight.w600 : FontWeight.w500,
      ),
    );

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: isPending,
          onChanged: notesNonEmpty
              ? (_) => ref.read(callEntryProvider.notifier).togglePending()
              : null,
          activeColor: _kActiveColor,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(
            color: notesNonEmpty
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface.withValues(alpha: 0.38),
            width: 1.5,
          ),
        ),
        const SizedBox(width: 2),
        if (notesNonEmpty)
          Flexible(
            child: GestureDetector(
              onTap: () => ref.read(callEntryProvider.notifier).togglePending(),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: label,
              ),
            ),
          )
        else
          Flexible(child: label),
      ],
    );

    if (notesNonEmpty) return row;
    // Άδειο χαρτί: το πάτημα οπουδήποτε στη ζώνη του τικ αναβοσβήνει το πεδίο.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () =>
            ref.read(notesFieldHintTickProvider.notifier).requestHintFlash(),
        child: row,
      ),
    );
  }
}
