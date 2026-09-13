/// Ενότητα «Διαδρομές» της οθόνης «Κανόνες επικύρωσης».
///
/// Δείχνει ποιες ρυθμισμένες διαδρομές δεν βρέθηκαν σε αυτό το μηχάνημα, με
/// σαφή ένδειξη αν ταξιδεύουν με τη βάση ή είναι τοπικές. Δεν έχει καμία
/// σχέση με τους κανόνες επικύρωσης — μοιράζεται μόνο το κουμπί που τη
/// σκανδαλίζει.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/providers/core_lexicon_provider.dart';
import '../../../services/configured_path_check.dart';
import '../../../services/configured_path_scan_result.dart';
import '../../../services/path_fix_navigator.dart';
import 'validation_rule_widgets.dart';

/// Το καθαρό μήνυμα των διαδρομών.
///
/// Λέει «όλες» **μόνο** όταν εξετάστηκε κάθε ομάδα· αλλιώς περιορίζεται στις
/// υπόλοιπες. Ζει έξω από το widget ώστε η υπόσχεση να ελέγχεται χωρίς να
/// χτιστεί οθόνη.
String configuredPathsCleanMessage({required bool partial}) {
  return partial
      ? 'Οι υπόλοιπες ρυθμισμένες διαδρομές βρέθηκαν σε αυτό το μηχάνημα.'
      : 'Όλες οι ρυθμισμένες διαδρομές βρέθηκαν σε αυτό το μηχάνημα.';
}

/// Τα αποτελέσματα του ελέγχου διαδρομών.
///
/// Το καθαρό μήνυμα μιλά για «όλες» τις διαδρομές **μόνο** όταν εξετάστηκαν
/// όλες. Όταν μια ομάδα δεν διαβάστηκε, το λέει πρώτα — και το πράσινο
/// περιορίζεται στις υπόλοιπες.
class ConfiguredPathsSection extends StatelessWidget {
  const ConfiguredPathsSection({super.key, required this.scan});

  final ConfiguredPathScanResult scan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invalidPaths = scan.invalidPaths;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!scan.isFullyChecked) ...[
          _UncheckedGroupsBanner(groups: scan.uncheckedGroups),
          const SizedBox(height: 8),
        ],
        if (invalidPaths.isEmpty)
          StatusBanner(
            icon: Icons.folder_outlined,
            tone: StatusBannerTone.success,
            message: configuredPathsCleanMessage(
              partial: !scan.isFullyChecked,
            ),
          )
        else ...[
          Text(
            invalidPaths.length == 1
                ? '1 διαδρομή εκτός λειτουργίας σε αυτό το μηχάνημα'
                : '${invalidPaths.length} διαδρομές εκτός λειτουργίας σε αυτό '
                      'το μηχάνημα',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Οι διαδρομές «της βάσης» ταξιδεύουν μαζί της (δουλειά ↔ σπίτι)· '
            'οι «τοπικές» αφορούν μόνο αυτόν τον υπολογιστή.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in invalidPaths) _InvalidPathTile(entry: entry),
        ],
      ],
    );
  }
}

/// «Δεν ελέγχθηκαν …» — τι έμεινε αόρατο και γιατί.
///
/// Τυπική αιτία: η κοινόχρηστη βάση ήταν κλειδωμένη από συνάδελφο τη στιγμή
/// του ελέγχου, οπότε οι ρυθμίσεις που ζουν μέσα της δεν διαβάστηκαν.
class _UncheckedGroupsBanner extends StatelessWidget {
  const _UncheckedGroupsBanner({required this.groups});

  final List<String> groups;

  @override
  Widget build(BuildContext context) {
    return StatusBanner(
      icon: Icons.help_outline,
      tone: StatusBannerTone.warning,
      title: 'Δεν ελέγχθηκαν: ${groups.join(', ')}',
      message:
          'Οι ρυθμίσεις αυτές δεν μπόρεσαν να διαβαστούν — συνήθως '
          'επειδή η βάση ήταν απασχολημένη από συνάδελφο. Ξανατρέξτε '
          'τον έλεγχο σε λίγο.',
    );
  }
}

/// Μία διαδρομή που δεν βρέθηκε, με τον δρόμο προς τη ρύθμισή της.
class _InvalidPathTile extends ConsumerWidget {
  const _InvalidPathTile({required this.entry});

  final ConfiguredPathEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final warning = Colors.orange.shade800;
    final blockedReason = pathFixBlockedReason(
      entry.fixDestination,
      dictionaryNavVisible: ref.watch(dictionaryNavVisibleProvider),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.folder_off_outlined, size: 22, color: warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.settingName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: entry.storedInDatabase
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          entry.storedInDatabase
                              ? 'ρύθμιση της βάσης'
                              : 'τοπική ρύθμιση',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: entry.storedInDatabase
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    entry.path,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['Consolas', 'monospace'],
                    ),
                  ),
                  Text(
                    'Δεν βρέθηκε σε αυτό το μηχάνημα · διορθώνεται: '
                    '${entry.fixLocation}',
                    style: theme.textTheme.bodySmall?.copyWith(color: warning),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message:
                          blockedReason ??
                          'Μετάβαση στη ρύθμιση: ${entry.fixLocation}',
                      child: OutlinedButton.icon(
                        onPressed: blockedReason != null
                            ? null
                            : () => requestPathFixNavigation(
                                ref,
                                entry.fixDestination,
                              ),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('Μετάβαση στη ρύθμιση'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
