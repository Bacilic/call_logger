import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/catalog_counts.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/background_task.dart';
import '../../directory/services/mass_deletion_guard.dart';

/// Το ποσοστό από το οποίο μια διαγραφή καταλόγου προειδοποιεί — κοινό για
/// όλους τους σταθμούς.
///
/// Κάτω από το πεδίο λέει ποιοι κατάλογοι καλύπτονται, από τα **πραγματικά**
/// πλήθη της βάσης: ο κανόνας ισχύει από 50 στοιχεία και πάνω, και κανείς δεν
/// θυμάται απ' έξω πόσα τμήματα έχει ο κατάλογος.
class MassDeletionSettingSection extends StatefulWidget {
  const MassDeletionSettingSection({super.key});

  @override
  State<MassDeletionSettingSection> createState() =>
      _MassDeletionSettingSectionState();
}

class _MassDeletionSettingSectionState
    extends State<MassDeletionSettingSection> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  String? _coverage;

  @override
  void initState() {
    super.initState();
    runBackgroundTask(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final percent = await SettingsService().catalogs
        .getMassDeletionWarningPercent();
    final db = await DatabaseHelper.instance.database;
    final counts = await activeCatalogCounts(db);
    if (!mounted) return;
    setState(() {
      _controller.text = '$percent';
      _coverage = massDeletionCoverageText({
        MassDeletionCatalog.users: counts.users,
        MassDeletionCatalog.departments: counts.departments,
        MassDeletionCatalog.equipment: counts.equipment,
      });
      _loading = false;
    });
  }

  /// Γράφει ό,τι στέκει, και επαναφέρει ό,τι δεν στέκει: αν γραφτεί 100,
  /// φαίνεται αμέσως το 90 που πράγματι αποθηκεύτηκε.
  Future<void> _commit() async {
    final normalized = normalizeMassDeletionPercent(
      int.tryParse(_controller.text.trim()),
    );
    await SettingsService().catalogs.setMassDeletionWarningPercent(normalized);
    if (!mounted) return;
    if (_controller.text.trim() != '$normalized') {
      _controller.text = '$normalized';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Προειδοποίηση μαζικής διαγραφής',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Όταν μια διαγραφή υπαλλήλων, τμημάτων ή εξοπλισμού σβήνει τουλάχιστον '
          'αυτό το ποσοστό του καταλόγου, ο διάλογος διαγραφής το λέει με '
          'πλαίσιο προειδοποίησης. Η ρύθμιση είναι κοινή για όλους τους '
          'σταθμούς.',
          style: muted,
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Ποσοστό %',
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
                  'Από $kMinMassDeletionPercent% έως '
                  '$kMaxMassDeletionPercent% (προεπιλογή '
                  '$kDefaultMassDeletionPercent%).',
                  style: muted,
                ),
              ),
            ],
          ),
          if (_coverage != null) ...[
            const SizedBox(height: 8),
            Text(_coverage!, style: muted),
          ],
        ],
      ],
    );
  }
}
