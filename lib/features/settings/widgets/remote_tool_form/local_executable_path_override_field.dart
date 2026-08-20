import 'package:flutter/material.dart';

import '../../../../core/services/overridable_settings.dart';

/// «Διαδρομή σε αυτόν τον υπολογιστή» — η τοπική παράκαμψη ενός εργαλείου.
///
/// Ο ορισμός του εργαλείου (όνομα, παράμετροι, εικονίδιο, σειρά) είναι κοινός
/// για όλη την ομάδα· μόνο το πού βρίσκεται το πρόγραμμα αλλάζει από μηχάνημα
/// σε μηχάνημα. Ως τώρα, όποιος διόρθωνε τη διαδρομή για το δικό του μηχάνημα
/// τη χαλούσε για όλους (Φάση 3).
///
/// Δείχνει τρεις καταστάσεις, γιατί ο χρήστης πρέπει να ξεχωρίζει το «δεν
/// δήλωσα τίποτα» από το «δήλωσα ρητά κενή»:
/// 1. **Χωρίς παράκαμψη** — ισχύει η κοινή διαδρομή.
/// 2. **Με παράκαμψη** — ισχύει η δική του, με κουμπί επιστροφής στην κοινή.
/// 3. **Με κενή παράκαμψη** — «κανένα πρόγραμμα εδώ», ρητά δηλωμένο.
class LocalExecutablePathOverrideField extends StatefulWidget {
  const LocalExecutablePathOverrideField({
    super.key,
    required this.toolId,
    required this.sharedPath,
    this.enabled = true,
    this.onPick,
  });

  /// `null` για εργαλείο που δεν έχει αποθηκευτεί ακόμη — τότε το πεδίο δεν
  /// εμφανίζεται: δεν υπάρχει ταυτότητα για να δεθεί η παράκαμψη.
  final int? toolId;

  /// Η κοινή διαδρομή του ορισμού, για να φαίνεται τι ισχύει χωρίς παράκαμψη.
  final String sharedPath;

  final bool enabled;

  /// Επιλογή αρχείου· επιστρέφει τη διαδρομή ή `null` στην ακύρωση.
  final Future<String?> Function()? onPick;

  @override
  State<LocalExecutablePathOverrideField> createState() =>
      _LocalExecutablePathOverrideFieldState();
}

class _LocalExecutablePathOverrideFieldState
    extends State<LocalExecutablePathOverrideField> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _hasOverride = false;

  OverridableSettingKey? get _key => widget.toolId == null
      ? null
      : OverridableSettingKeys.remoteToolExecutablePath.forId(widget.toolId!);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = _key;
    if (key == null) {
      setState(() => _loading = false);
      return;
    }
    final value = await OverridableSettings.overrideOf(key);
    if (!mounted) return;
    setState(() {
      _hasOverride = value != null;
      _controller.text = value ?? '';
      _loading = false;
    });
  }

  Future<void> _saveOverride(String value) async {
    final key = _key;
    if (key == null) return;
    await OverridableSettings.setOverride(key, value.trim());
    if (!mounted) return;
    setState(() => _hasOverride = true);
  }

  Future<void> _useShared() async {
    final key = _key;
    if (key == null) return;
    await OverridableSettings.clearOverride(key);
    if (!mounted) return;
    setState(() {
      _hasOverride = false;
      _controller.text = '';
    });
  }

  Future<void> _pick() async {
    final picked = await widget.onPick?.call();
    if (picked == null || !mounted) return;
    _controller.text = picked;
    await _saveOverride(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.toolId == null || _loading) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final shared = widget.sharedPath.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.computer_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Διαδρομή σε αυτόν τον υπολογιστή',
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _hasOverride
              ? 'Ισχύει μόνο εδώ. Οι συνάδελφοι συνεχίζουν με την κοινή '
                    'διαδρομή.'
              : 'Αν το πρόγραμμα βρίσκεται αλλού σε αυτό το μηχάνημα, '
                    'δηλώστε το εδώ — η κοινή διαδρομή μένει ανέπαφη για τους '
                    'υπόλοιπους.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('remote_tool_local_path_override_field'),
                controller: _controller,
                enabled: widget.enabled,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: shared.isEmpty ? null : shared,
                  helperText: _hasOverride
                      ? null
                      : 'Κενό = χρησιμοποιείται η κοινή διαδρομή',
                ),
                onSubmitted: widget.enabled ? _saveOverride : null,
                onEditingComplete: widget.enabled
                    ? () => _saveOverride(_controller.text)
                    : null,
              ),
            ),
            if (widget.onPick != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.enabled ? _pick : null,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Αναζήτηση'),
              ),
            ],
          ],
        ),
        if (_hasOverride) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('remote_tool_use_shared_path_button'),
              onPressed: widget.enabled ? _useShared : null,
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              label: const Text('Χρήση της κοινής διαδρομής'),
            ),
          ),
        ],
      ],
    );
  }
}
