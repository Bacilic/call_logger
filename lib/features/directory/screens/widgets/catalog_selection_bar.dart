import 'package:flutter/material.dart';

/// Η κάτω μπάρα που εμφανίζεται όταν υπάρχει επιλογή σε καρτέλα του Καταλόγου.
///
/// Ήταν γραμμένη τέσσερις φορές, μία σε κάθε καρτέλα, με διαφορά μόνο στο
/// ουσιαστικό και στα κουμπιά ενεργειών. Τώρα ζει σε ένα σημείο, ώστε ό,τι
/// προστίθεται εδώ να το αποκτούν και οι τέσσερις μαζί.
class CatalogSelectionBar extends StatelessWidget {
  const CatalogSelectionBar({
    super.key,
    required this.selectedCount,
    required this.countLabel,
    required this.showOnlySelected,
    required this.searchController,
    required this.onToggleShowOnlySelected,
    required this.onClearSelection,
    required this.actions,
  });

  final int selectedCount;

  /// Το ουσιαστικό στο σωστό γένος: «επιλεγμένοι» ή «επιλεγμένα».
  final String countLabel;

  final bool showOnlySelected;

  /// Το πεδίο αναζήτησης της καρτέλας.
  ///
  /// **Υποχρεωτικό επίτηδες:** ανάβοντας το φίλτρο η αναζήτηση καθαρίζει, ώστε
  /// να φανεί ολόκληρη η συλλογή και όχι η τομή της με ένα ξεχασμένο ερώτημα.
  /// Αν το καθάριζε ο καλών, η τέταρτη καρτέλα θα το ξέχναγε.
  final TextEditingController searchController;

  final VoidCallback onToggleShowOnlySelected;
  final VoidCallback onClearSelection;

  /// Τα κουμπιά ενεργειών της καρτέλας (Επεξεργασία, Αντίγραφο, Διαγραφή…).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          // **Wrap και όχι Row:** σε στενό παράθυρο τα κουμπιά ενεργειών μαζί
          // με τα δύο νέα δεν χωρούν σε μία σειρά, και μια σειρά που ξεχειλίζει
          // κρύβει τη «Διαγραφή» αντί να την κατεβάσει από κάτω.
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$selectedCount $countLabel',
                key: const Key('catalog_selection_count'),
                style: theme.textTheme.bodyMedium,
              ),
              // Το κουμπί λέει τι ΘΑ κάνει, όχι σε ποια κατάσταση βρίσκεται:
              // «δείξε» δεν διαβάζεται ποτέ ως «αφαίρεσε», και έτσι δεν
              // συγχέεται με την αποεπιλογή.
              TextButton.icon(
                key: const Key('catalog_selection_filter_toggle'),
                onPressed: () {
                  if (!showOnlySelected) searchController.clear();
                  onToggleShowOnlySelected();
                },
                icon: Icon(
                  showOnlySelected
                      ? Icons.filter_alt_off_outlined
                      : Icons.filter_alt_outlined,
                  size: 18,
                ),
                label: Text(
                  showOnlySelected ? 'Δείξε όλα' : 'Δείξε μόνο τα επιλεγμένα',
                ),
              ),
              TextButton(
                key: const Key('catalog_selection_clear'),
                onPressed: onClearSelection,
                child: const Text('Καθαρισμός επιλογής'),
              ),
              ...actions,
            ],
          ),
        ),
      ],
    );
  }
}

/// Η γραμμή που λέει ότι η λίστα είναι περιορισμένη στα επιλεγμένα.
///
/// Χωρίς αυτήν, μια λίστα με πέντε γραμμές σε κατάλογο εκατοντάδων μοιάζει με
/// άδειο κατάλογο — και ο διακόπτης της κάτω μπάρας είναι μακριά από το σημείο
/// που κοιτά ο χρήστης.
class CatalogSelectionFilterNotice extends StatelessWidget {
  const CatalogSelectionFilterNotice({
    super.key,
    required this.active,
    required this.shownCount,
    required this.onShowAll,
  });

  final bool active;

  /// Πόσες γραμμές δείχνει η λίστα τώρα (επιλεγμένα ∩ αναζήτηση).
  final int shownCount;

  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      child: Row(
        children: [
          Icon(
            Icons.filter_alt_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Δείχνονται μόνο τα επιλεγμένα ($shownCount) — η αναζήτηση '
              'καθάρισε και τα υπόλοιπα είναι κρυμμένα.',
              key: const Key('catalog_selection_filter_notice'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onShowAll, child: const Text('Δείξε όλα')),
        ],
      ),
    );
  }
}
