import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/settings_service.dart';
import '../../models/catalog_validation_finding.dart';
import '../../models/catalog_validation_rules.dart';
import '../../providers/catalog_validation_provider.dart';
import '../../services/catalog_scan_runner.dart';
import '../../services/configured_path_check.dart';
import '../../services/configured_path_scan_result.dart';
import 'validation_rules/catalog_scan_section.dart';
import 'validation_rules/validation_rule_cards.dart';
import 'validation_rules/validation_rule_field_controllers.dart';
import 'validation_rules/validation_rule_widgets.dart';

/// Υπο-οθόνη «Κανόνες επικύρωσης» του hub «Διάφορα».
///
/// Όλοι οι κανόνες είναι προειδοποιήσεις — δεν εμποδίζουν ποτέ την
/// αποθήκευση. Κάθε αλλαγή αποθηκεύεται αμέσως στο app_settings της
/// ενεργής βάσης και ακυρώνει την cache των κανόνων.
///
/// Η οθόνη κρατά **μόνο την κατάσταση και τη ροή**: ποιοι κανόνες ισχύουν,
/// τι βρήκε η τελευταία σάρωση, και πώς γράφεται μια αλλαγή. Η δήλωση των
/// κανόνων, τα ευρήματα και οι διαδρομές ζουν σε δικά τους αρχεία κάτω από
/// το `validation_rules/`.
class ValidationRulesView extends ConsumerStatefulWidget {
  const ValidationRulesView({super.key});

  @override
  ConsumerState<ValidationRulesView> createState() =>
      _ValidationRulesViewState();
}

class _ValidationRulesViewState extends ConsumerState<ValidationRulesView> {
  CatalogValidationRules? _rules;

  /// Αποτελέσματα του τελευταίου ελέγχου· `null` = δεν έχει τρέξει ακόμη.
  List<CatalogValidationFinding>? _findings;

  /// Το τελευταίο αποτέλεσμα του ελέγχου διαδρομών — μαζί με τις ομάδες που
  /// δεν κατάφερε να διαβάσει. `null` = δεν έχει τρέξει ακόμη.
  ConfiguredPathScanResult? _pathScan;
  bool _scanning = false;

  final ValidationRuleFieldControllers _fields =
      ValidationRuleFieldControllers();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await ref.read(catalogValidationRulesProvider.future);
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _fields.fillFrom(rules);
    });
  }

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  /// Άμεση αποθήκευση + ακύρωση cache, ώστε οι φόρμες να δουν τους νέους
  /// κανόνες χωρίς επανεκκίνηση.
  ///
  /// Η [change] περιγράφει **τι άγγιξε ο χρήστης** και εφαρμόζεται πάνω στους
  /// κανόνες όπως είναι εκείνη τη στιγμή στη βάση — όχι πάνω στην εικόνα που
  /// φόρτωσε η οθόνη. Και οι είκοσι δύο κανόνες ζουν σε ένα κλειδί: γράφοντάς
  /// τους ολόκληρους από παλιά εικόνα, ένα τσεκάρισμα εδώ επανέφερε τον
  /// διακόπτη που μόλις άλλαξε ο άλλος διαχειριστής.
  ///
  /// Η οθόνη δείχνει μετά ό,τι όντως αποθηκεύτηκε, άρα βλέπει και τις ξένες
  /// αλλαγές χωρίς να χρειάζεται να ξανανοίξει.
  Future<void> _apply(ValidationRuleChange change) async {
    setState(() {
      // Τα ευρήματα προήλθαν από τους ΠΑΛΙΟΥΣ κανόνες — παύουν να ισχύουν.
      _findings = null;
      _pathScan = null;
      // Άμεση απόκριση του διακόπτη· η αυθεντική τιμή έρχεται πιο κάτω.
      final shown = _rules;
      if (shown != null) _rules = change(shown);
    });
    final storedRaw = await SettingsService().catalogs
        .updateCatalogValidationRulesRaw(
          (raw) => change(CatalogValidationRules.fromRawJson(raw)).toRawJson(),
        );
    if (!mounted) return;
    if (storedRaw != null) {
      setState(() => _rules = CatalogValidationRules.fromRawJson(storedRaw));
    }
    ref.invalidate(catalogValidationRulesProvider);
    // Ο service παρακολουθεί τους κανόνες με watch: χωρίς άμεσο ξέπλυμα η
    // αλυσίδα μένει «dirty» (καμία φόρμα ανοιχτή εδώ) και ξεπλένεται σύγχρονα
    // μέσα στο build της επόμενης φόρμας καταλόγου → «setState during build».
    flushCatalogValidationProviderChain(ref);
  }

  /// Με [recheckPaths]: false κρατούνται τα προηγούμενα ευρήματα διαδρομών.
  /// Οι έλεγχοι διαδρομών περιμένουν απαντήσεις δικτύου (έως 3" η καθεμιά) —
  /// τρέχουν μόνο όταν πατιέται το κουμπί, όχι σε κάθε φρεσκάρισμα.
  Future<void> _runScan({bool recheckPaths = true}) async {
    setState(() => _scanning = true);
    try {
      final findings = await CatalogScanRunner.scan(ref);
      final pathScan = recheckPaths
          ? await findInvalidConfiguredPaths()
          : _pathScan;
      if (!mounted) return;
      setState(() {
        _findings = findings;
        _pathScan = pathScan;
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Άνοιγμα της καρτέλας μιας εγγραφής ευρήματος· μετά το κλείσιμο ο
  /// έλεγχος ξανατρέχει, ώστε η λίστα να δείχνει την πραγματικότητα και
  /// όχι ευρήματα που μόλις διορθώθηκαν.
  ///
  /// ΧΩΡΙΣ επανέλεγχο διαδρομών: η επεξεργασία μιας εγγραφής δεν μπορεί να
  /// αλλάξει ρυθμισμένες διαδρομές, και οι έλεγχοί τους περιμένουν δίκτυο —
  /// αυτό έκανε το κλείσιμο της καρτέλας να «κολλάει» αισθητά.
  Future<void> _openRecord(CatalogFindingRecord record) async {
    await CatalogScanRunner.openRecord(context, ref, record);
    if (!mounted) return;
    await _runScan(recheckPaths: false);
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    if (rules == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const StatusBanner(
                icon: Icons.info_outline,
                tone: StatusBannerTone.warning,
                message:
                    'Όλοι οι κανόνες είναι προειδοποιήσεις — δεν εμποδίζουν '
                    'ποτέ την αποθήκευση.',
              ),
              const SizedBox(height: 12),
              StrictnessCard(
                level: rules.strictnessLevel,
                // Το πακέτο γράφει ΟΛΟΥΣ τους διακόπτες — και αυτό είναι το
                // ζητούμενο: «θέλω αυτό το επίπεδο» σημαίνει ότι υπερισχύει
                // όποιου μεμονωμένου τσεκαρίσματος. Εφαρμόζεται πάντως πάνω
                // στην αποθηκευμένη εικόνα, οπότε οι αριθμητικές ρυθμίσεις
                // (και του συναδέλφου) μένουν άθικτες.
                onPick: (level) =>
                    _apply((current) => current.withStrictness(level)),
              ),
              const SizedBox(height: 12),
              ValidationRuleCards(
                rules: rules,
                fields: _fields,
                onApply: _apply,
              ),
              const SizedBox(height: 20),
              CatalogScanSection(
                scanning: _scanning,
                findings: _findings,
                pathScan: _pathScan,
                onScan: _runScan,
                onOpenRecord: _openRecord,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
