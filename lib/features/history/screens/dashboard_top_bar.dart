/// Η πάνω μπάρα των Στατιστικών Κλήσεων.
///
/// Κρατά μόνο ό,τι αφορά ολόκληρη την οθόνη: επιστροφή, ταυτότητα, και τις
/// τρεις ενέργειες. Οι τέσσερις ισότιμες επιλογές που κουβαλούσε πριν
/// («Έξοδος», «Χρώματα», «Γρήγορη Εξαγωγή», «Ρυθμίσεις / Φίλτρα») έδιναν την
/// ίδια βαρύτητα σε μια αισθητική προτίμηση και σε μια έξοδο· τώρα η επιστροφή
/// είναι βέλος στην αριστερή άκρη όπως παντού στα Windows, και η παλέτα ζει στο
/// μενού «Περισσότερα».
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import 'dashboard_cards.dart';
import 'dashboard_palette_colors.dart';

/// Τι μπορεί να ζητήσει ο χρήστης από το μενού εξαγωγής.
enum DashboardExportFormat {
  excel,
  pdf;

  String get label => switch (this) {
    DashboardExportFormat.excel => 'Excel (.xlsx)',
    DashboardExportFormat.pdf => 'PDF (.pdf)',
  };

  IconData get icon => switch (this) {
    DashboardExportFormat.excel => Icons.table_chart_outlined,
    DashboardExportFormat.pdf => Icons.picture_as_pdf_outlined,
  };
}

/// Τα ονόματα των παλετών, όπως τα διαβάζει ο χρήστης.
String dashboardPaletteLabel(DashboardPalette palette) => switch (palette) {
  DashboardPalette.classic => 'Κλασικό',
  DashboardPalette.ocean => 'Ωκεανός',
  DashboardPalette.sunrise => 'Ανατολή',
  DashboardPalette.forest => 'Δάσος',
  DashboardPalette.indigoNight => 'Νυχτερινό ίντιγκο',
};

class DashboardTopBar extends StatelessWidget {
  const DashboardTopBar({
    super.key,
    required this.colors,
    required this.palette,
    required this.filtersExpanded,
    required this.onBack,
    required this.onToggleFilters,
    required this.onExport,
    required this.onPaletteChanged,
  });

  final DashboardPaletteColors colors;
  final DashboardPalette palette;
  final bool filtersExpanded;
  final VoidCallback onBack;
  final VoidCallback onToggleFilters;
  final ValueChanged<DashboardExportFormat> onExport;
  final ValueChanged<DashboardPalette> onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 12, 18, 12),
          decoration: BoxDecoration(
            color: colors.topBarFill.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.topBarBorder.withValues(alpha: 0.95),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                tooltip: 'Πίσω στο Ιστορικό Κλήσεων',
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              _identity(theme),
              const Spacer(),
              _filtersButton(theme),
              const SizedBox(width: 8),
              _exportMenu(theme),
              const SizedBox(width: 8),
              _moreMenu(),
            ],
          ),
        ),
      ),
    );
  }

  /// Το σήμα της οθόνης: ράβδοι διαγράμματος, όχι τηλέφωνο.
  ///
  /// Το τηλέφωνο ανήκει στην οθόνη των κλήσεων και στην κάρτα «Συνολικές
  /// κλήσεις». Όταν το φορούσε και ο τίτλος, δύο διαφορετικά πράγματα — «εδώ
  /// καταγράφεις κλήσεις» και «εδώ μετράς κλήσεις» — έδειχναν ίδια.
  Widget _identity(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [colors.topBarLogoBgStart, colors.topBarLogoBgEnd],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Icon(Icons.insights_rounded, color: colors.topBarLogoIcon),
        ),
        const SizedBox(width: 12),
        Text(
          'Στατιστικά Κλήσεων',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _filtersButton(ThemeData theme) {
    return OutlinedButton.icon(
      onPressed: onToggleFilters,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      icon: Icon(
        filtersExpanded ? Icons.expand_less_rounded : Icons.tune_rounded,
        size: 18,
      ),
      label: Text(filtersExpanded ? 'Απόκρυψη φίλτρων' : 'Φίλτρα'),
    );
  }

  Widget _exportMenu(ThemeData theme) {
    return PopupMenuButton<DashboardExportFormat>(
      tooltip: 'Εξαγωγή των στατιστικών που βλέπετε',
      onSelected: onExport,
      itemBuilder: (context) => [
        for (final format in DashboardExportFormat.values)
          PopupMenuItem<DashboardExportFormat>(
            value: format,
            child: Row(
              children: [
                Icon(format.icon, size: 18),
                const SizedBox(width: 10),
                Text(format.label),
              ],
            ),
          ),
      ],
      child: FilledButton.icon(
        // Το κουμπί είναι η λαβή του μενού· το πάτημα το χειρίζεται ο γονέας
        // του, γι' αυτό δεν έχει δικό του onPressed.
        onPressed: null,
        style: FilledButton.styleFrom(
          backgroundColor: colors.actionBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: colors.actionBlue,
          disabledForegroundColor: Colors.white,
        ),
        icon: const Icon(Icons.download_rounded, size: 18),
        label: const Text('Εξαγωγή'),
      ),
    );
  }

  Widget _moreMenu() {
    return MenuAnchor(
      builder: (context, controller, child) {
        return IconButton(
          tooltip: 'Περισσότερα',
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.more_horiz_rounded),
        );
      },
      menuChildren: [
        SubmenuButton(
          leadingIcon: GradientPaletteIcon(colors: colors),
          menuChildren: [
            for (final option in DashboardPalette.values)
              MenuItemButton(
                leadingIcon: Icon(
                  option == palette
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                onPressed: () => onPaletteChanged(option),
                child: Text(dashboardPaletteLabel(option)),
              ),
          ],
          child: const Text('Παλέτα χρωμάτων'),
        ),
      ],
    );
  }
}
