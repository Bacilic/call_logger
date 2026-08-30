import 'package:flutter/material.dart';

import 'database_settings_backup_tab.dart';
import 'database_settings_file_tab.dart';
import 'database_settings_maintenance_tab.dart';
import 'database_settings_restore_tab.dart';

/// Πάνελ ρυθμίσεων βάσης δεδομένων σε 4 θεματικές καρτέλες
/// (Βάση, Αντίγραφα ασφαλείας, Επαναφορά, Συντήρηση) — όπως ο διάλογος
/// ρυθμίσεων Lansweeper.
///
/// Το περιεχόμενο κάθε καρτέλας ζει στο δικό της αρχείο· εδώ μένει μόνο το
/// κέλυφος: τίτλος, μπάρα καρτελών και κύλιση ανά καρτέλα. Οι καρτέλες
/// κρατούν την κατάστασή τους όσο ζει ο διάλογος (keep-alive), όπως όταν όλα
/// τα τμήματα κατοικούσαν σε ένα ενιαίο πάνελ.
class DatabaseSettingsPanel extends StatelessWidget {
  const DatabaseSettingsPanel({
    super.key,
    this.onDatabaseLifecycleChanged,
    this.initialTabIndex = 0,
  });

  /// Μετά από επιτυχή αλλαγή διαδρομής (επαλήθευση) ή δημιουργία νέου αρχείου βάσης.
  final Future<void> Function()? onDatabaseLifecycleChanged;

  /// Ποια καρτέλα είναι μπροστά όταν ανοίγει (0: Βάση, 1: Αντίγραφα,
  /// 2: Επαναφορά, 3: Συντήρηση). Όποιος έρχεται από αλλού για συγκεκριμένη
  /// ρύθμιση τη βρίσκει χωρίς δεύτερο κλικ.
  final int initialTabIndex;

  Widget _tab(IconData icon, String label) {
    return Tab(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: DefaultTabController(
          length: 4,
          initialIndex: initialTabIndex.clamp(0, 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.settings_suggest_outlined,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ρυθμίσεις βάσης δεδομένων',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TabBar(
                tabs: [
                  _tab(Icons.storage, 'Βάση'),
                  _tab(Icons.shield_outlined, 'Αντίγραφα ασφαλείας'),
                  _tab(Icons.unarchive_outlined, 'Επαναφορά'),
                  _tab(Icons.fact_check_outlined, 'Συντήρηση'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ScrollableTab(
                      child: DatabaseSettingsFileTab(
                        onDatabaseLifecycleChanged: onDatabaseLifecycleChanged,
                      ),
                    ),
                    const _ScrollableTab(child: DatabaseSettingsBackupTab()),
                    _ScrollableTab(
                      child: DatabaseSettingsRestoreTab(
                        onDatabaseLifecycleChanged: onDatabaseLifecycleChanged,
                      ),
                    ),
                    const _ScrollableTab(
                      child: DatabaseSettingsMaintenanceTab(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Κύλιση καρτέλας με ορατή μπάρα — ίδια εμφάνιση με το παλιό ενιαίο πάνελ.
class _ScrollableTab extends StatefulWidget {
  const _ScrollableTab({required this.child});

  final Widget child;

  @override
  State<_ScrollableTab> createState() => _ScrollableTabState();
}

class _ScrollableTabState extends State<_ScrollableTab> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      thickness: 6,
      radius: const Radius.circular(3),
      child: SingleChildScrollView(
        controller: _controller,
        // Κενό δεξιά ώστε η μπάρα να μην επικαλύπτει switches/dropdowns.
        padding: const EdgeInsetsDirectional.only(top: 12, end: 20, bottom: 4),
        child: widget.child,
      ),
    );
  }
}
