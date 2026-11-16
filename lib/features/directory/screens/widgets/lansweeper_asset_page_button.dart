import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/lansweeper_asset_page.dart';
import '../../../../core/widgets/compact_tooltip.dart';
import '../../../history/providers/lansweeper_settings_provider.dart';

/// Κουμπί που ανοίγει τη σελίδα της συσκευής [assetId] στο Lansweeper.
///
/// Κοινό για τον Κατάλογο και τον χάρτη, ώστε ο σύνδεσμος να φτιάχνεται
/// παντού με τον ίδιο τρόπο: από τον διακομιστή του URL προβολής ticket.
class LansweeperAssetPageButton extends ConsumerWidget {
  const LansweeperAssetPageButton({
    super.key,
    required this.assetId,
    this.withLabel = false,
  });

  final int assetId;

  /// Με κείμενο «Άνοιγμα στο Lansweeper»· αλλιώς μόνο εικονίδιο.
  final bool withLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = lansweeperAssetPageUrl(
      ref.watch(lansweeperTicketViewUrlProvider),
      assetId,
    );
    final VoidCallback? onPressed = url == null
        ? null
        : () => unawaited(
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          );
    final tooltip = url == null
        ? 'Η διεύθυνση του διακομιστή Lansweeper δεν είναι σωστή '
              '(ρυθμίσεις Lansweeper → URL προβολής ticket).'
        : 'Άνοιγμα στο Lansweeper: $url';
    return CompactTooltip(
      message: tooltip,
      child: withLabel
          ? FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Άνοιγμα στο Lansweeper'),
            )
          : IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onPressed,
              icon: const Icon(Icons.open_in_new, size: 18),
            ),
    );
  }
}
