import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/dialog_snackbar_scope.dart';
import '../../../../core/utils/user_facing_error_messages.dart';
import '../../../../core/services/ai_prompt_template_controller.dart';
import '../../../../core/services/ai_prompt_template_syntax.dart';
import '../../../../core/services/personal_ai_prompt.dart';
import '../../providers/gemini_settings_provider.dart';
import 'ai_prompt_template_field.dart';

enum _PromptEditorDismissChoice { continueEditing, discard }

/// Διάλογος επεξεργασίας προτύπου προτροπής Gemini (placeholders, blocks, JSON).
class AiPromptTemplateEditorDialog extends ConsumerStatefulWidget {
  const AiPromptTemplateEditorDialog({
    required this.savedTemplate,
    required this.onSave,
    this.profile = AiPromptProfile.lansweeper,
    this.title = 'Πρότυπο προτροπής Τεχνητής Νοημοσύνης',
    this.description =
        'Ορίζει πώς η ΤΝ προτείνει τίτλο, περιγραφή και λύση για μετατροπη της κλήσης σε ticket στο Lansweeper. ',
    this.personalDefault = true,
    super.key,
  });

  /// Ποια σήματα ισχύουν και ποια είναι η εργοστασιακή προτροπή.
  final AiPromptProfile profile;

  final String title;

  /// Τι ορίζει η προτροπή — η πρώτη πρόταση της περιγραφής του διαλόγου.
  final String description;

  /// «Ορισμός ως Προεπιλογή»: προσωπική προεπιλογή — υπάρχει μόνο για την
  /// προτροπή της Αναφοράς Lansweeper. Χωρίς αυτήν, η «Επαναφορά» φέρνει
  /// πάντα την εργοστασιακή.
  final bool personalDefault;

  /// Τελευταία αποθηκευμένη τιμή (στιγμιότυπο dirty-state).
  final String savedTemplate;

  /// Εγγραφή στον πραγματικό controller/ρυθμίσεις μετά επιτυχή «Αποθήκευση».
  final Future<void> Function(String text) onSave;

  @override
  ConsumerState<AiPromptTemplateEditorDialog> createState() =>
      _AiPromptTemplateEditorDialogState();
}

class _AiPromptTemplateEditorDialogState
    extends ConsumerState<AiPromptTemplateEditorDialog>
    with DialogSnackbarHost {
  final ScrollController _scrollController = ScrollController();
  late final AiPromptTemplateTextEditingController _draftController;
  late String _savedSnapshot;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _savedSnapshot = widget.savedTemplate;
    _draftController = AiPromptTemplateTextEditingController(
      text: _savedSnapshot,
      profile: widget.profile,
    );
    _draftController.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    _draftController.removeListener(_onDraftChanged);
    _draftController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  bool get _isDirty => _draftController.text != _savedSnapshot;

  void _cancelEdits() {
    _draftController.text = _savedSnapshot;
  }

  Future<bool> _confirmInvalidSave() async {
    final validation = AiPromptTemplateSyntax.validate(
      _draftController.text,
      profile: widget.profile,
    );
    if (validation.isValid) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Μη έγκυρο πρότυπο'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Το πρότυπο έχει σφάλματα συντακτικού. Διορθώστε τα πριν την αποθήκευση:',
              ),
              const SizedBox(height: 8),
              for (final error in validation.errors) Text('• $error'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Εντάξει'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _save() async {
    if (!_isDirty || _saving) return;
    if (!await _confirmInvalidSave()) return;

    setState(() => _saving = true);
    try {
      final next = _draftController.text;
      await widget.onSave(next);
      if (!mounted) return;
      setState(() {
        _savedSnapshot = next;
        _saving = false;
      });
      showDialogSnackBar(
        const SnackBar(content: Text('Το πρότυπο αποθηκεύτηκε.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDialogSnackBar(
        SnackBar(
          content: Text('Αποτυχία αποθήκευσης: ${humanizeUserFacingError(e)}'),
        ),
      );
    }
  }

  Future<_PromptEditorDismissChoice?> _showUnsavedChangesDialog() {
    return showDialog<_PromptEditorDismissChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Μη αποθηκευμένες αλλαγές'),
        content: const Text(
          'Υπάρχουν μη αποθηκευμένες αλλαγές στο πρότυπο προτροπής. '
          'Να απορριφθούν;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              ctx,
            ).pop(_PromptEditorDismissChoice.continueEditing),
            child: const Text('Συνέχεια επεξεργασίας'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_PromptEditorDismissChoice.discard),
            child: const Text('Απόρριψη αλλαγών'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestClose() async {
    if (!_isDirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await _showUnsavedChangesDialog();
    if (!mounted ||
        choice == null ||
        choice == _PromptEditorDismissChoice.continueEditing) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _setUserDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ορισμός προσωπικής προεπιλογής'),
        content: const Text(
          'Η τρέχουσα τιμή του πεδίου θα αποθηκευτεί ως προσωπική προεπιλογή '
          'και θα αντικαταστήσει την προηγούμενη (αν υπήρχε). Συνέχεια;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ορισμός'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref
        .read(geminiPromptTemplateUserDefaultProvider.notifier)
        .setUserDefault(_draftController.text);
    if (!mounted) return;
    showDialogSnackBar(
      const SnackBar(content: Text('Ορίστηκε προσωπική προεπιλογή προτροπής.')),
    );
  }

  Future<void> _restoreDefault() async {
    final userDefault = widget.personalDefault
        ? ref.read(geminiPromptTemplateUserDefaultProvider)
        : null;
    final hasUserDefault = userDefault != null && userDefault.trim().isNotEmpty;

    if (!hasUserDefault) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Επαναφορά προεπιλογής'),
          content: const Text(
            'Δεν υπάρχει αποθηκευμένη προσωπική προεπιλογή. '
            'Το πεδίο θα αντικατασταθεί με το εργοστασιακό πρότυπο. Συνέχεια;',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Επαναφορά'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      _draftController.text = widget.profile.defaultTemplate;
      return;
    }

    final choice = await showDialog<_RestoreDefaultChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Επαναφορά προεπιλογής'),
        content: const Text(
          'Ποια προεπιλογή θέλετε να φορτωθεί στο πεδίο επεξεργασίας;',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_RestoreDefaultChoice.cancel),
            child: const Text('Άκυρο'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_RestoreDefaultChoice.factory),
            child: const Text('Εργοστασιακή'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_RestoreDefaultChoice.personal),
            child: const Text('Προσωπική'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == _RestoreDefaultChoice.cancel) {
      return;
    }
    _draftController.text = switch (choice) {
      _RestoreDefaultChoice.factory => widget.profile.defaultTemplate,
      _RestoreDefaultChoice.personal => userDefault,
      _RestoreDefaultChoice.cancel => _draftController.text,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtleStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          unawaited(_requestClose());
        },
        child: AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
            width: 520,
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${widget.description}'
                      'Ο επεξεργαστής προτροπής υποστηρίζει αυτόματες προτάσεις όταν πληκτρολογήσετε \'{\'',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AiPromptTemplateField(controller: _draftController),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (widget.personalDefault)
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              textStyle: subtleStyle,
                            ),
                            onPressed: _setUserDefault,
                            child: const Text('Ορισμός ως Προεπιλογή'),
                          ),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            textStyle: subtleStyle,
                          ),
                          onPressed: _restoreDefault,
                          child: const Text('Επαναφορά Προεπιλογής'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isDirty ? _cancelEdits : null,
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: _isDirty && !_saving ? () => unawaited(_save()) : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Αποθήκευση'),
            ),
            TextButton(
              onPressed: () => unawaited(_requestClose()),
              child: const Text('Κλείσιμο'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _RestoreDefaultChoice { cancel, factory, personal }

/// Ανοίγει τον επεξεργαστή μιας προσωπικής προτροπής — τον ίδιο με της
/// Αναφοράς Lansweeper, με τα σήματα και την εργοστασιακή της προτροπής.
Future<void> openPersonalPromptEditor(
  BuildContext context,
  PersonalAiPrompt prompt,
) async {
  final saved = await prompt.read();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AiPromptTemplateEditorDialog(
      savedTemplate: saved,
      onSave: prompt.write,
      profile: prompt.profile,
      title: prompt.title,
      description: prompt.description,
      personalDefault: false,
    ),
  );
}
