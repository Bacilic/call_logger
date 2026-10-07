import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_path_resolution.dart';
import '../init/network_database_return.dart';
import 'info_hint_icon.dart';

const String kLocalDatabaseBannerText =
    'ΤΟΠΙΚΗ ΒΑΣΗ ΔΕΔΟΜΕΝΩΝ - η δικτυακή δεν ήταν προσβάσιμη. '
    'Ό,τι καταγράφετε μένει σε αυτόν τον υπολογιστή.';

const String kNetworkDatabaseReturnedText =
    'Η ΔΙΚΤΥΑΚΗ ΒΑΣΗ ΕΠΑΝΗΛΘΕ - εξακολουθείτε να δουλεύετε στην τοπική.';

const String kLocalDatabaseSettingsLink = 'Ρυθμίσεις βάσης δεδομένων';

const String kReturnToNetworkDatabaseLink = 'Μετάβαση στη δικτυακή βάση';

const String kLocalDatabaseBannerHint =
    'Η εφαρμογή δουλεύει προσωρινά στην τοπική βάση αυτού του υπολογιστή, '
    'γιατί η δικτυακή δεν απάντησε στην εκκίνηση.\n'
    '• Επιστροφή στη δικτυακή: η εφαρμογή ελέγχει μόνη της το δίκτυο και θα '
    'σας ειδοποιήσει μόλις η δικτυακή βάση επανέλθει. Στο επόμενο άνοιγμα '
    'επιστρέφει έτσι κι αλλιώς μόνη της.\n'
    '• Μόνιμα στην τοπική: ορίστε την ως βάση σας από τις «Ρυθμίσεις βάσης '
    'δεδομένων». Η λωρίδα φεύγει αμέσως.\n'
    'Ό,τι καταγράφετε εδώ δεν μεταφέρεται στη δικτυακή βάση.';

const String kLocalDatabaseCollapseTooltip =
    'Σμίκρυνση σε σημάδι στην πλευρική μπάρα. Ο έλεγχος του δικτύου '
    'συνεχίζεται· μόλις επανέλθει η δικτυακή βάση, η λωρίδα ξαναφαίνεται.';

const String kLocalDatabaseMarkLabel = 'Τοπική βάση';

const String kLocalDatabaseMarkTooltip =
    'Τοπική βάση — η δικτυακή δεν ήταν προσβάσιμη. Ό,τι καταγράφετε μένει σε '
    'αυτόν τον υπολογιστή.\nΚλικ για λεπτομέρειες.';

/// Πώς φαίνεται η τοπική βάση: λωρίδα πάνω, ή σημάδι στην πλευρική μπάρα.
enum LocalDatabaseIndicator { banner, mark }

/// Ο χρήστης μίκρυνε τη λωρίδα με το «Χ».
///
/// autoDispose επίτηδες: ζει μόνο όσο κάποιος ρωτά τον
/// [localDatabaseIndicatorProvider], δηλαδή όσο η εφαρμογή δουλεύει σε τοπική
/// βάση. Μια επόμενη τοπική συνεδρία ξεκινά πάντα με ολόκληρη λωρίδα.
final localDatabaseBannerCollapsedProvider =
    NotifierProvider.autoDispose<LocalDatabaseBannerCollapsed, bool>(
      LocalDatabaseBannerCollapsed.new,
    );

class LocalDatabaseBannerCollapsed extends Notifier<bool> {
  @override
  bool build() => false;

  void collapse() => state = true;

  void expand() => state = false;
}

/// Απάντησε ξανά η δικτυακή βάση που αντικαταστάθηκε από την τοπική;
///
/// Ένα σημείο για τη λωρίδα και για την απόφαση λωρίδα/σημάδι, ώστε να μη
/// διαφωνήσουν ποτέ.
final localDatabaseNetworkReturnedProvider = Provider.autoDispose<bool>((ref) {
  final networkPath = LocalDatabaseSessionFallback.acceptedNetworkPath;
  if (networkPath == null) return false;
  return ref.watch(networkDatabaseReturnedProvider(networkPath)).value ?? false;
});

/// **Μία απόφαση** για το τι φαίνεται — τη διαβάζουν και η στήλη περιεχομένου
/// (λωρίδα) και η πλευρική μπάρα (σημάδι). Το «επανήλθε» ξαναφέρνει πάντα τη
/// λωρίδα: είναι νέα κατάσταση, και ζητά απόφαση.
///
/// Ο φρουρός επανόδου ζει μέσα από αυτόν τον provider, οπότε το «Χ» δεν τον
/// σταματά: ο έλεγχος συνεχίζει όσο η λωρίδα είναι σημάδι.
final localDatabaseIndicatorProvider =
    Provider.autoDispose<LocalDatabaseIndicator>((ref) {
      final returned = ref.watch(localDatabaseNetworkReturnedProvider);
      final collapsed = ref.watch(localDatabaseBannerCollapsedProvider);
      return collapsed && !returned
          ? LocalDatabaseIndicator.mark
          : LocalDatabaseIndicator.banner;
    });

/// Η λωρίδα της τοπικής βάσης «γι' αυτή τη φορά».
///
/// Δύο καταστάσεις: όσο η δικτυακή δεν απαντά (κίτρινη), εξηγεί πώς φεύγει η
/// λωρίδα και δίνει σύνδεσμο στις Ρυθμίσεις βάσης· μόλις ξαναπαντήσει
/// (πράσινη), το λέει και προσφέρει τη μετάβαση. Η απόφαση μένει πάντα στον
/// χρήστη.
class LocalDatabaseBanner extends ConsumerStatefulWidget {
  const LocalDatabaseBanner({
    super.key,
    required this.onOpenDatabaseSettings,
    required this.onReturnToNetwork,
    this.canCollapse = true,
  });

  final VoidCallback onOpenDatabaseSettings;
  final Future<void> Function() onReturnToNetwork;

  /// Αν υπάρχει το «Χ» που τη μικραίνει σε σημάδι της πλευρικής μπάρας.
  /// `false` όπου η μπάρα δεν φαίνεται (π.χ. πλήρης οθόνη Λεξικού) — εκεί
  /// το σημάδι δεν θα το έβλεπε κανείς.
  final bool canCollapse;

  @override
  ConsumerState<LocalDatabaseBanner> createState() =>
      _LocalDatabaseBannerState();
}

class _LocalDatabaseBannerState extends ConsumerState<LocalDatabaseBanner> {
  bool _switching = false;

  Future<void> _returnToNetwork() async {
    setState(() => _switching = true);
    try {
      await widget.onReturnToNetwork();
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final returned = ref.watch(localDatabaseNetworkReturnedProvider);
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Colors.black87,
      fontWeight: FontWeight.w600,
    );

    return Container(
      key: const ValueKey('local_database_banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
      // Άλλο χρώμα = άλλη κατάσταση: το πράσινο είναι το ίδιο με της
      // ανακοίνωσης επιτυχημένης αλλαγής βάσης.
      color: returned ? Colors.green.shade200 : Colors.amber,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  returned
                      ? kNetworkDatabaseReturnedText
                      : kLocalDatabaseBannerText,
                  textAlign: TextAlign.center,
                  style: textStyle,
                ),
                if (!returned) ...[
                  const InfoHintIcon(message: kLocalDatabaseBannerHint),
                  _BannerLink(
                    label: kLocalDatabaseSettingsLink,
                    onPressed: widget.onOpenDatabaseSettings,
                  ),
                ] else
                  _BannerLink(
                    label: kReturnToNetworkDatabaseLink,
                    onPressed: _switching ? null : _returnToNetwork,
                  ),
              ],
            ),
          ),
          // Η πράσινη δεν μικραίνει: είναι είδηση που ζητά απόφαση.
          if (widget.canCollapse && !returned)
            IconButton(
              key: const ValueKey('local_database_banner_collapse'),
              icon: const Icon(Icons.close),
              color: Colors.black87,
              visualDensity: VisualDensity.compact,
              tooltip: kLocalDatabaseCollapseTooltip,
              onPressed: () => ref
                  .read(localDatabaseBannerCollapsedProvider.notifier)
                  .collapse(),
            ),
        ],
      ),
    );
  }
}

class _BannerLink extends StatelessWidget {
  const _BannerLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.black87,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        label,
        style: const TextStyle(
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
