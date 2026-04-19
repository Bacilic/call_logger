import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/settings_provider.dart';
import '../../../../core/providers/spell_check_provider.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';

/// Εμφανίζει διάλογο ρυθμίσεων εξοπλισμού (τύποι ως CSV στο `app_settings`).
/// Επιστρέφει `true` αν έγινε επιτυχής αποθήκευση.
Future<bool> showEquipmentSettingsDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _EquipmentSettingsDialog(),
  );
  return result ?? false;
}

class _EquipmentSettingsDialog extends ConsumerStatefulWidget {
  const _EquipmentSettingsDialog();

  @override
  ConsumerState<_EquipmentSettingsDialog> createState() =>
      _EquipmentSettingsDialogState();
}

class _EquipmentSettingsDialogState
    extends ConsumerState<_EquipmentSettingsDialog> {
  final SettingsService _settings = SettingsService();
  late final SpellCheckController _controller;

  bool _loading = true;
  String _initial = '';

  @override
  void initState() {
    super.initState();
    _controller = SpellCheckController();
    _load();
  }

  Future<void> _load() async {
    final raw = await _settings.getEquipmentTypesRaw();
    if (!mounted) return;
    setState(() {
      _controller.text = raw;
      _initial = raw;
      _loading = false;
    });
  }

  bool get _hasChanges => _controller.text.trim() != _initial.trim();

  Future<void> _save() async {
    try {
      await _settings.setEquipmentTypes(_controller.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Σφάλμα αποθήκευσης: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spellAsync = ref.watch(spellCheckServiceProvider);
    final spellEnabledAsync = ref.watch(enableSpellCheckProvider);
    spellAsync.whenData(_controller.attachSpellService);
    spellEnabledAsync.whenData(_controller.setSpellCheckEnabled);

    if (_loading) {
      return AlertDialog(
        content: const SizedBox(
          width: 360,
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Τύποι εξοπλισμού'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Χρησιμοποιούνται στα αναδυόμενα πεδία τύπου εξοπλισμού. '
                'Διαχωρίστε τις τιμές με κόμμα.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              LexiconSpellTextFormField(
                controller: _controller,
                maxLines: 6,
                minLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Τύποι εξοπλισμού',
                  hintText:
                      'Διαχωρίστε με κόμμα, π.χ. Υπολογιστής, Εκτυπωτής, Οθόνη',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _hasChanges ? _save : null,
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
