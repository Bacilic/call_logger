import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/greek_dictionary_provider.dart';
import '../../../core/providers/lexicon_categories_provider.dart';
import '../../../core/providers/lexicon_language_recalc_provider.dart';
import '../../../core/providers/spell_check_provider.dart';
import '../../../core/services/settings_service.dart';

/// Διάλογος ρυθμίσεων λεξικού: διαδρομές πηγής/εξαγωγής, εισαγωγές και compile.
class DictionarySettingsDialog extends ConsumerStatefulWidget {
  const DictionarySettingsDialog({
    super.key,
    required this.onImportTxt,
    required this.onCompile,
  });

  final Future<void> Function() onImportTxt;
  final Future<void> Function() onCompile;

  @override
  ConsumerState<DictionarySettingsDialog> createState() =>
      _DictionarySettingsDialogState();
}

class _DictionarySettingsDialogState
    extends ConsumerState<DictionarySettingsDialog> {
  final _settings = SettingsService();
  late final TextEditingController _sourcePathCtrl;
  late final TextEditingController _exportPathCtrl;
  late final TextEditingController _lexiconCategoriesCtrl;
  bool _compileBusy = false;

  @override
  void initState() {
    super.initState();
    _sourcePathCtrl = TextEditingController();
    _exportPathCtrl = TextEditingController();
    _lexiconCategoriesCtrl = TextEditingController();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    final s = await _settings.getDictionarySourcePath();
    final e = await _settings.getDictionaryExportPath();
    final c = await _settings.getLexiconCategoriesRaw();
    if (!mounted) return;
    _sourcePathCtrl.text = s ?? '';
    _exportPathCtrl.text = e ?? '';
    _lexiconCategoriesCtrl.text = c;
    setState(() {});
  }

  @override
  void dispose() {
    _sourcePathCtrl.dispose();
    _exportPathCtrl.dispose();
    _lexiconCategoriesCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSourcePath() async {
    final t = _sourcePathCtrl.text.trim();
    await _settings.setDictionarySourcePath(t.isEmpty ? null : t);
    ref.invalidate(greekDictionaryServiceProvider);
    ref.invalidate(spellCheckServiceProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποθηκεύτηκε διαδρομή πηγής λεξικού')),
      );
    }
  }

  Future<void> _saveExportPath() async {
    final t = _exportPathCtrl.text.trim();
    await _settings.setDictionaryExportPath(t.isEmpty ? null : t);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποθηκεύτηκε διαδρομή εξαγωγής')),
      );
    }
  }

  Future<void> _saveLexiconCategories() async {
    final t = _lexiconCategoriesCtrl.text.trim();
    if (t.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ορίστε τουλάχιστον μία κατηγορία (χωρισμένες με κόμμα)'),
          ),
        );
      }
      return;
    }
    await _settings.setLexiconCategories(t);
    ref.invalidate(lexiconCategoriesProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποθηκεύτηκαν κατηγορίες λεξικού')),
      );
    }
  }

  Future<void> _pickSaveSourcePath() async {
    final r = await FilePicker.pickFiles(
      dialogTitle: 'Αρχείο πηγής λεξικού (TXT)',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (r == null || r.files.isEmpty) return;
    final p = r.files.single.path;
    if (p != null) {
      _sourcePathCtrl.text = p;
      await _saveSourcePath();
      setState(() {});
    }
  }

  Future<void> _pickSaveExportPath() async {
    final p = await FilePicker.saveFile(
      dialogTitle: 'Αρχείο εξαγωγής Compile (TXT)',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (p == null) return;
    _exportPathCtrl.text = p;
    await _saveExportPath();
    setState(() {});
  }

  Future<void> _runCompile() async {
    setState(() => _compileBusy = true);
    try {
      await widget.onCompile();
    } finally {
      if (mounted) setState(() => _compileBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recalc = ref.watch(lexiconLanguageRecalcProvider);
    final recalcLoading = recalc is LexiconLanguageRecalcLoading;
    final recalcProgress = switch (recalc) {
      LexiconLanguageRecalcLoading(:final progress) => progress,
      _ => 0.0,
    };

    ref.listen<LexiconLanguageRecalcState>(lexiconLanguageRecalcProvider,
        (prev, next) {
      if (next is LexiconLanguageRecalcSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ολοκληρώθηκε ο επανέλεγχος γλωσσών'),
          ),
        );
        ref.read(lexiconLanguageRecalcProvider.notifier).acknowledge();
      } else if (next is LexiconLanguageRecalcError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message)),
        );
        ref.read(lexiconLanguageRecalcProvider.notifier).acknowledge();
      }
    });

    return AlertDialog(
      title: const Text('Ρυθμίσεις λεξικού'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (recalcLoading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: recalcProgress.clamp(0.0, 1.0),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: recalcLoading
                      ? null
                      : () => ref
                          .read(lexiconLanguageRecalcProvider.notifier)
                          .recalculate(),
                  icon: const Icon(Icons.translate_outlined),
                  label: const Text('Επανέλεγχος Γλωσσών'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _sourcePathCtrl,
                decoration: InputDecoration(
                  labelText: 'Διαδρομή πηγής TXT (ορθογραφία)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: _pickSaveSourcePath,
                  ),
                ),
                onSubmitted: (_) => _saveSourcePath(),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saveSourcePath,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Αποθήκευση πηγής'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _exportPathCtrl,
                decoration: InputDecoration(
                  labelText: 'Διαδρομή εξαγωγής Compile (TXT)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.save_alt),
                    onPressed: _pickSaveExportPath,
                  ),
                ),
                onSubmitted: (_) => _saveExportPath(),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saveExportPath,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Αποθήκευση εξαγωγής'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _lexiconCategoriesCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Κατηγορίες λεξικού (dropdown)',
                  hintText:
                      'Διαχωρίστε με κόμμα, π.χ. Γενική, Τεχνικός Όρος, Όνομα',
                  border: OutlineInputBorder(),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saveLexiconCategories,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Αποθήκευση κατηγοριών'),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () async {
                      await widget.onImportTxt();
                    },
                    child: const Text('Εισαγωγή από αρχείο'),
                  ),
                  FilledButton(
                    onPressed: _compileBusy ? null : _runCompile,
                    child: _compileBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Εξαγωγή\\Δημιουργία'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Κλείσιμο'),
        ),
      ],
    );
  }
}
