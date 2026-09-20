import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/settings_service.dart';
import '../../../core/database/database_staleness.dart';

/// Το όριο των ημερών πέρα από το οποίο μια βάση θεωρείται στάσιμη.
///
/// Ζει στην καρτέλα του **αρχείου** και όχι των αντιγράφων επίτηδες: η
/// ερώτηση που απαντά είναι «είμαι στη σωστή βάση;», όχι «πότε παίρνω
/// αντίγραφο».
///
/// Δικό του widget ώστε η καρτέλα να μην κουβαλά ούτε την ανάγνωση ούτε τη
/// γραφή της ρύθμισης.
class DatabaseStalenessSettingSection extends StatefulWidget {
  const DatabaseStalenessSettingSection({super.key});

  @override
  State<DatabaseStalenessSettingSection> createState() =>
      _DatabaseStalenessSettingSectionState();
}

class _DatabaseStalenessSettingSectionState
    extends State<DatabaseStalenessSettingSection> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final days = await SettingsService().catalogs.getDatabaseStalenessDays();
    if (!mounted) return;
    setState(() {
      _controller.text = '$days';
      _loading = false;
    });
  }

  /// Γράφει ό,τι στέκει, και επαναφέρει ό,τι δεν στέκει.
  ///
  /// Το πεδίο δεν μένει ποτέ με τιμή που δεν ισχύει: αν ο χρήστης γράψει 900,
  /// βλέπει αμέσως το 60 που πράγματι αποθηκεύτηκε.
  Future<void> _commit() async {
    final parsed = int.tryParse(_controller.text.trim());
    final normalized = normalizeDatabaseStalenessDays(parsed);
    await SettingsService().catalogs.setDatabaseStalenessDays(normalized);
    if (!mounted) return;
    if (_controller.text.trim() != '$normalized') {
      _controller.text = '$normalized';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Προειδοποίηση «ΠΑΛΙΑ ΒΑΣΗ»',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Αν σε αυτή τη βάση δεν έχει γραφτεί τίποτα εδώ και τόσες μέρες, '
          'εμφανίζεται κίτρινη λωρίδα «ΠΑΛΙΑ ΒΑΣΗ» με τη διαδρομή του αρχείου '
          '— για να μη δουλέψετε κατά λάθος πάνω σε παλαιότερο αντίγραφο. '
          'Μετράει η πιο πρόσφατη από τις δύο: τελευταία κλήση ή τελευταία '
          'εγγραφή στο Ιστορικό.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Μέρες',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onTapOutside: (_) => unawaited(_commit()),
                  onSubmitted: (_) => unawaited(_commit()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Από $kMinDatabaseStalenessDays έως '
                  '$kMaxDatabaseStalenessDays μέρες '
                  '(προεπιλογή $kDefaultDatabaseStalenessDays).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
