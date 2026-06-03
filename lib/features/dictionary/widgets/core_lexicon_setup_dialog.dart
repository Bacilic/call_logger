import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers/core_lexicon_provider.dart';
import '../../../core/services/core_lexicon_service.dart';

/// Εμφανίζει διάλογο ρύθμισης πυρήνα· `true` αν φορτώθηκε επιτυχώς.
Future<bool> showCoreLexiconSetupDialog({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const CoreLexiconSetupDialog(),
  );
  return result == true;
}

class CoreLexiconSetupDialog extends ConsumerStatefulWidget {
  const CoreLexiconSetupDialog({super.key});

  @override
  ConsumerState<CoreLexiconSetupDialog> createState() =>
      _CoreLexiconSetupDialogState();
}

class _CoreLexiconSetupDialogState extends ConsumerState<CoreLexiconSetupDialog> {
  List<String> _bundledAssets = [];
  String? _selectedAsset;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBundled();
  }

  Future<void> _loadBundled() async {
    final list = await CoreLexiconService.instance.listBundledTxtAssets();
    if (!mounted) return;
    setState(() {
      _bundledAssets = list;
      _selectedAsset = list.isNotEmpty ? list.first : null;
      _loading = false;
    });
  }

  Future<void> _applyBundled() async {
    final asset = _selectedAsset;
    if (asset == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok =
        await ref.read(coreLexiconProvider.notifier).installFromBundledAsset(
              asset,
            );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = ref.read(coreLexiconProvider).lastError ??
          'Αποτυχία εγκατάστασης λεξικού-πυρήνα.';
    });
  }

  Future<void> _pickExternalFile() async {
    final r = await FilePicker.pickFiles(
      dialogTitle: 'Επιλογή αρχείου λεξικού-πυρήνα (.txt)',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (r == null || r.files.isEmpty) return;
    final path = r.files.single.path;
    if (path == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(coreLexiconProvider.notifier)
        .installFromExternalFile(path);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = ref.read(coreLexiconProvider).lastError ??
          'Αποτυχία εγκατάστασης λεξικού-πυρήνα.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Ρύθμιση λεξικού-πυρήνα'),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Για ορθογραφικό έλεγχο χρειάζεται λεξικό-πυρήνας. '
                      'Το αρχείο αποθηκεύεται στον φάκελο dictionaries δίπλα στην εφαρμογή '
                      '(portable, όπως η βάση δεδομένων).',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (_bundledAssets.isNotEmpty) ...[
                      Text(
                        'Διαθέσιμα bundled λεξικά:',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      IgnorePointer(
                        ignoring: _busy,
                        child: RadioGroup<String?>(
                          groupValue: _selectedAsset,
                          onChanged: (v) => setState(() => _selectedAsset = v),
                          child: Column(
                          children: [
                            for (final asset in _bundledAssets)
                              RadioListTile<String?>(
                                value: asset,
                                title: Text(
                                  p.basename(asset),
                                  style: theme.textTheme.bodyMedium,
                                ),
                                subtitle: Text(
                                  asset,
                                  style: theme.textTheme.bodySmall,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                          ],
                        ),
                        ),
                      ),
                    ] else
                      Text(
                        'Δεν βρέθηκαν bundled αρχεία .txt. Επιλέξτε αρχείο από τον δίσκο.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Άκυρο'),
        ),
        if (_bundledAssets.isNotEmpty)
          FilledButton(
            onPressed: _busy || _selectedAsset == null ? null : _applyBundled,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Εφαρμογή'),
          ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickExternalFile,
          icon: const Icon(Icons.folder_open_outlined),
          label: Text(
            _bundledAssets.isEmpty
                ? 'Επιλογή αρχείου…'
                : 'Άλλο αρχείο…',
          ),
        ),
      ],
    );
  }
}
