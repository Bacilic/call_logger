import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_file_classifier.dart';
import '../services/backup_zip_inventory.dart';
import '../services/backup_zip_manifest.dart';
import '../services/database_file_replacement.dart';
import '../services/restore_database_eligibility.dart';
import '../services/restore_plan.dart';
import '../services/restore_selection.dart';

/// Διεπαφή επιβεβαίωσης επαναφοράς: σύγκριση, προέλευση, **τι** επαναφέρεται
/// και με ποιο όνομα.
///
/// Η επαναφορά γράφει πάντα στον φάκελο της τρέχουσας βάσης — ο χρήστης
/// επιλέγει το όνομα και τα στοιχεία. Δεν διαβάζει βάση και δεν γράφει
/// αρχεία: δέχεται έτοιμα δεδομένα και επιστρέφει την επιλογή, ή `null` σε
/// ακύρωση.
Future<RestoreSelection?> showRestoreFromBackupDialog({
  required BuildContext context,
  required DatabaseFileProfile? currentProfile,
  required DatabaseFileProfile backupProfile,
  required BackupZipManifest manifest,
  required String currentDatabasePath,
  required List<RestoreDestinationChoice> availableDestinations,
  required BackupZipPortablePresence portablePresence,
  RestoreDestinationChoice initialDestination =
      RestoreDestinationChoice.defaultChoice,
  String? preferredDatabaseFileName,
  bool backupNameTargetExists = false,
  bool allowSkippingDatabase = true,
  DateTime? localLampDatabaseModified,
  LocalPortableCounts localCounts = const LocalPortableCounts(),
}) {
  assert(availableDestinations.isNotEmpty);
  final initial = availableDestinations.contains(initialDestination)
      ? initialDestination
      : availableDestinations.first;

  return showDialog<RestoreSelection>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RestoreFromBackupDialog(
      currentProfile: currentProfile,
      backupProfile: backupProfile,
      manifest: manifest,
      currentDatabasePath: currentDatabasePath,
      availableDestinations: availableDestinations,
      initialDestination: initial,
      preferredDatabaseFileName: preferredDatabaseFileName,
      backupNameTargetExists: backupNameTargetExists,
      portablePresence: portablePresence,
      allowSkippingDatabase: allowSkippingDatabase,
      localLampDatabaseModified: localLampDatabaseModified,
      localCounts: localCounts,
    ),
  );
}

/// Πόσα φορητά αρχεία υπάρχουν ΤΩΡΑ στον υπολογιστή.
///
/// Χωρίς αυτά ο χρήστης δεν έχει τρόπο να δει ότι η επαναφορά «1 εικόνας»
/// αφήνει ορφανές τις 14 που έχει σήμερα — η απώλεια στις κατόψεις είναι
/// αθόρυβη, γιατί τα αρχεία μένουν στον δίσκο αλλά η νέα βάση δεν τα ξέρει.
class LocalPortableCounts {
  const LocalPortableCounts({
    this.maps = 0,
    this.toolImages = 0,
    this.lexicon = 0,
  });

  final int maps;
  final int toolImages;
  final int lexicon;

  int forPart(RestorePortablePart part) {
    switch (part) {
      case RestorePortablePart.maps:
        return maps;
      case RestorePortablePart.toolImages:
        return toolImages;
      case RestorePortablePart.lexicon:
        return lexicon;
      case RestorePortablePart.lampDatabase:
        return 0;
    }
  }
}

class _RestoreFromBackupDialog extends StatefulWidget {
  const _RestoreFromBackupDialog({
    required this.currentProfile,
    required this.backupProfile,
    required this.manifest,
    required this.currentDatabasePath,
    required this.availableDestinations,
    required this.initialDestination,
    required this.portablePresence,
    this.preferredDatabaseFileName,
    this.backupNameTargetExists = false,
    this.allowSkippingDatabase = true,
    this.localLampDatabaseModified,
    this.localCounts = const LocalPortableCounts(),
  });

  final DatabaseFileProfile? currentProfile;
  final DatabaseFileProfile backupProfile;
  final BackupZipManifest manifest;
  final String currentDatabasePath;
  final List<RestoreDestinationChoice> availableDestinations;
  final RestoreDestinationChoice initialDestination;
  final BackupZipPortablePresence portablePresence;
  final String? preferredDatabaseFileName;
  final bool backupNameTargetExists;
  final bool allowSkippingDatabase;
  final DateTime? localLampDatabaseModified;
  final LocalPortableCounts localCounts;

  @override
  State<_RestoreFromBackupDialog> createState() =>
      _RestoreFromBackupDialogState();
}

class _RestoreFromBackupDialogState extends State<_RestoreFromBackupDialog> {
  late RestoreDestinationChoice _destination;
  late bool _restoreDatabase;
  late Set<RestorePortablePart> _parts;
  late RestoreDatabaseVerdict _verdict;

  @override
  void initState() {
    super.initState();
    _destination = widget.initialDestination;
    _verdict = judgeBackupDatabase(widget.backupProfile);
    // Ό,τι θέλει δεύτερη επιβεβαίωση δεν προεπιλέγεται. Η επικίνδυνη ενέργεια
    // απαιτεί κίνηση του χρήστη — δεν του συμβαίνει επειδή πάτησε «Επαναφορά».
    _restoreDatabase = _verdict.restorable && !_verdict.requiresConfirmation;
    // Προεπιλογή: έρχονται όσα υπάρχουν στο αντίγραφο — εκτός από τη βάση
    // Λάμπας όταν η τοπική είναι νεότερη, οπότε η επαναφορά θα έσβηνε δουλειά.
    _parts = {
      for (final part in RestorePortablePart.values)
        if (_countFor(part) > 0 && !_localIsNewer(part)) part,
    };
  }

  int _countFor(RestorePortablePart part) {
    final presence = widget.portablePresence;
    switch (part) {
      case RestorePortablePart.maps:
        return presence.mapsCount;
      case RestorePortablePart.toolImages:
        return presence.imagesCount;
      case RestorePortablePart.lexicon:
        return presence.dictionariesCount;
      case RestorePortablePart.lampDatabase:
        return presence.lampDatabaseCount;
    }
  }

  /// Μόνο η βάση Λάμπας κρίνεται χρονικά: είναι ολόκληρη βάση δεδομένων, και
  /// μια επαναφορά πάνω από νεότερη δουλειά είναι απώλεια, όχι σωτηρία.
  bool _localIsNewer(RestorePortablePart part) {
    if (part != RestorePortablePart.lampDatabase) return false;
    final local = widget.localLampDatabaseModified;
    final inBackup = widget.portablePresence.lampDatabaseModified;
    if (local == null || inBackup == null) return false;
    return local.isAfter(inBackup);
  }

  int get _selectedCount => _parts.length + (_restoreDatabase ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Επαναφορά από αντίγραφο'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Τι θα επαναφερθεί;', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _buildSelectionList(theme),
              const SizedBox(height: 8),
              Text(
                'Οι προσωπικές σας ρυθμίσεις ταξιδεύουν μέσα στη βάση — '
                'έρχονται πίσω μαζί της.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (_restoreDatabase) ...[
                Text('Σύγκριση', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                _ComparisonTable(
                  current: widget.currentProfile,
                  backup: widget.backupProfile,
                ),
                const SizedBox(height: 16),
              ],
              Text('Προέλευση αντιγράφου', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(_originText()),
              if (_restoreDatabase) ...[
                const SizedBox(height: 16),
                Text(
                  'Με ποιο όνομα να γίνει η επαναφορά;',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                RadioGroup<RestoreDestinationChoice>(
                  groupValue: _destination,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _destination = v);
                  },
                  child: Column(
                    children: [
                      for (final choice in widget.availableDestinations)
                        RadioListTile<RestoreDestinationChoice>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(_destinationLabel(choice)),
                          subtitle: Text(
                            _targetPathFor(choice),
                            style: theme.textTheme.bodySmall,
                          ),
                          value: choice,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(_preservationText(), style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: _selectedCount == 0 ? null : _confirm,
          child: Text(_confirmLabel()),
        ),
      ],
    );
  }

  String _confirmLabel() {
    if (_selectedCount == 0) return 'Επαναφορά';
    if (_selectedCount == 1) return 'Επαναφορά 1 στοιχείου';
    return 'Επαναφορά $_selectedCount στοιχείων';
  }

  Future<void> _confirm() async {
    // Φθαρμένη βάση που ΕΠΙΛΕΧΘΗΚΕ: η βαρύτερη απόφαση του διαλόγου, γιατί
    // αντικαθιστά μια βάση που πιθανότατα δουλεύει με μία που σίγουρα έχει
    // ζημιά. Ρωτιέται πρώτη, με το ωμό κείμενο του SQLite μπροστά.
    if (_restoreDatabase && _verdict.requiresConfirmation) {
      final proceed = await _askCorruptedConfirmation();
      if (proceed != true) return;
      if (!mounted) return;
    }

    // Η βάση είναι το βαρύ κομμάτι της επαναφοράς. Όταν ο χρήστης την
    // ξετσεκάρει, ζητάει κάτι ασυνήθιστο — μια δεύτερη ερώτηση κοστίζει ένα
    // κλικ και γλιτώνει την απορία «γιατί δεν άλλαξαν τα δεδομένα μου».
    if (!_restoreDatabase) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Χωρίς επαναφορά της βάσης;'),
          content: const Text(
            'Η βάση δεδομένων θα μείνει όπως είναι — κλήσεις, υπάλληλοι και '
            'εξοπλισμός δεν αλλάζουν.\n\n'
            'Θα επαναφερθούν μόνο τα αρχεία που επιλέξατε. Αν προέρχονται από '
            'άλλη εποχή, μπορεί να μην ταιριάζουν με ό,τι γράφει η σημερινή '
            'βάση.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Πίσω'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Συνέχεια'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!mounted) return;
    }
    Navigator.pop(
      context,
      RestoreSelection(
        destination: _restoreDatabase ? _destination : null,
        parts: {..._parts},
      ),
    );
  }

  /// Η ερώτηση για τη φθαρμένη βάση.
  ///
  /// Δείχνει το **ωμό** κείμενο του SQLite σε κυλιόμενο πλαίσιο: δεν το
  /// καταλαβαίνει ο χρήστης, αλλά είναι ό,τι θα ζητήσει όποιος κληθεί να
  /// βοηθήσει — και η απουσία του ήταν ακριβώς το παράπονο που γέννησε τον
  /// έλεγχο ακεραιότητας.
  Future<bool?> _askCorruptedConfirmation() {
    final detail = _verdict.technicalDetail?.trim() ?? '';
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Η βάση του αντιγράφου έχει φθορά'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Ο έλεγχος βρήκε ότι μέρος του αρχείου δεν διαβάζεται. Αν '
                  'συνεχίσετε, η τρέχουσα βάση σας θα αντικατασταθεί από αυτή '
                  'εδώ — μαζί με τη ζημιά της.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Συνεχίστε μόνο αν αυτό είναι το μοναδικό αντίγραφο που σας '
                  'έχει απομείνει. Αν υπάρχει παλαιότερο, προτιμήστε εκείνο: '
                  'ένα πιο παλιό αντίγραφο που διαβάζεται αξίζει περισσότερο '
                  'από ένα πρόσφατο που δεν διαβάζεται.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Η τρέχουσα βάση σας φυλάσσεται πριν την αντικατάσταση, και '
                  'η θέση της θα εμφανιστεί στην αναφορά.',
                  style: theme.textTheme.bodySmall,
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Τι ακριβώς βρέθηκε:',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 140),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Πίσω'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Επαναφορά παρά τη ζημιά'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSelectionList(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _SelectionRow(
            icon: Icons.storage_outlined,
            title: _databaseTitle(),
            detail: _databaseDetail(),
            detailIsWarning:
                !_verdict.restorable ||
                _verdict.requiresConfirmation ||
                _databaseLosesRecords(),
            value: _restoreDatabase,
            // Τρεις καταστάσεις, τρεις συμπεριφορές:
            // - Ασύμβατη: κλειδωμένο ΚΛΕΙΣΤΟ, δεν ξεκλειδώνει με τίποτα.
            // - Φθαρμένη: ΠΑΝΤΑ ξεκλείδωτο, ακόμη κι όταν το αντίγραφο δεν
            //   επιτρέπει παράλειψη — εδώ η παράλειψη είναι έγκυρη επιλογή,
            //   και το κλείδωμα ανοιχτό θα επέβαλλε το ρίσκο.
            // - Υγιής: όπως πάντα, εξαρτάται από το είδος του αντιγράφου.
            enabled:
                _verdict.restorable &&
                (widget.allowSkippingDatabase || _verdict.requiresConfirmation),
            onChanged: (v) => setState(() => _restoreDatabase = v),
          ),
          for (final part in RestorePortablePart.values)
            _SelectionRow(
              icon: _iconFor(part),
              title: restorePortablePartLabel(part),
              detail: _detailFor(part),
              detailIsWarning: _localIsNewer(part) || _losesFiles(part),
              value: _parts.contains(part),
              enabled: _countFor(part) > 0,
              onChanged: (v) => setState(() {
                if (v) {
                  _parts.add(part);
                } else {
                  _parts.remove(part);
                }
              }),
            ),
        ],
      ),
    );
  }

  String _databaseTitle() {
    if (!_verdict.restorable) return '$restoreDatabaseLabel — δεν επαναφέρεται';
    if (_verdict.requiresConfirmation) {
      return '$restoreDatabaseLabel — προσοχή';
    }
    return widget.allowSkippingDatabase
        ? restoreDatabaseLabel
        : '$restoreDatabaseLabel (πάντα)';
  }

  String _databaseDetail() {
    if (!_verdict.restorable) return _verdict.reason!;

    final profile = widget.backupProfile;
    // Η φθορά προηγείται των πληθών: τα «496 κλήσεις» ενός χαλασμένου
    // αρχείου είναι ακριβώς η πληροφορία που καθησυχάζει λανθασμένα.
    if (_verdict.requiresConfirmation) {
      final counted = profile.callCount == null
          ? ''
          : ' Δηλώνει ${profile.callCount} κλήσεις, αλλά ο αριθμός δεν είναι '
                'αξιόπιστος.';
      return '${_verdict.reason!}$counted';
    }
    final parts = <String>[
      if (profile.callCount != null) '${profile.callCount} κλήσεις',
      if (profile.userCount != null) '${profile.userCount} υπάλληλοι',
    ];
    final latest = profile.latestCallDate?.trim() ?? '';
    if (latest.isNotEmpty) parts.add('τελευταία $latest');

    final loss = _recordLossSentence();
    if (loss != null) parts.add(loss);
    return parts.isEmpty ? 'Από το αντίγραφο' : parts.join(' · ');
  }

  /// Τι θα χαθεί από τη ΒΑΣΗ, σε λέξεις του χρήστη.
  ///
  /// Συγκρίνονται μόνο μεγέθη που ξέρουμε και για τις δύο πλευρές· άγνωστο
  /// πλήθος δεν είναι απώλεια, είναι άγνοια, και δεν μπαίνει στο μήνυμα.
  String? _recordLossSentence() {
    final current = widget.currentProfile;
    if (current == null) return null;
    final backup = widget.backupProfile;
    final losses = <String>[];

    void compare(int? now, int? then, String singular, String plural) {
      if (now == null || then == null || then >= now) return;
      final diff = now - then;
      losses.add('$diff ${diff == 1 ? singular : plural}');
    }

    compare(current.callCount, backup.callCount, 'κλήση', 'κλήσεις');
    compare(current.userCount, backup.userCount, 'υπάλληλο', 'υπαλλήλους');
    compare(
      current.equipmentCount,
      backup.equipmentCount,
      'μηχάνημα',
      'μηχανήματα',
    );

    if (losses.isEmpty) return null;
    return 'θα χαθούν ${losses.join(', ')}';
  }

  bool _databaseLosesRecords() => _recordLossSentence() != null;

  IconData _iconFor(RestorePortablePart part) {
    switch (part) {
      case RestorePortablePart.maps:
        return Icons.map_outlined;
      case RestorePortablePart.toolImages:
        return Icons.image_outlined;
      case RestorePortablePart.lexicon:
        return Icons.menu_book_outlined;
      case RestorePortablePart.lampDatabase:
        return Icons.lightbulb_outline;
    }
  }

  /// Το αντίγραφο φέρνει λιγότερα αρχεία απ' όσα υπάρχουν σήμερα.
  ///
  /// Η απώλεια εδώ είναι πιο ύπουλη από εκείνη της βάσης: τα παλιά αρχεία
  /// μένουν στον δίσκο, αλλά η επαναφερμένη βάση δεν τα ξέρει — οι κατόψεις
  /// απλώς εξαφανίζονται από την εφαρμογή.
  bool _losesFiles(RestorePortablePart part) {
    final local = widget.localCounts.forPart(part);
    final inBackup = _countFor(part);
    return local > 0 && inBackup > 0 && inBackup < local;
  }

  String _detailFor(RestorePortablePart part) {
    final count = _countFor(part);
    if (count == 0) return 'Δεν υπάρχει σε αυτό το αντίγραφο';
    if (_localIsNewer(part)) {
      final local = _formatDate(widget.localLampDatabaseModified);
      final inBackup = _formatDate(
        widget.portablePresence.lampDatabaseModified,
      );
      return 'Η τοπική σας είναι νεότερη ($local) από του αντιγράφου '
          '($inBackup)';
    }
    switch (part) {
      case RestorePortablePart.maps:
      case RestorePortablePart.toolImages:
        return _countedDetail(part, count, 'εικόνα', 'εικόνες');
      case RestorePortablePart.lexicon:
        return _countedDetail(part, count, 'αρχείο', 'αρχεία');
      case RestorePortablePart.lampDatabase:
        final when = _formatDate(widget.portablePresence.lampDatabaseModified);
        return when.isEmpty ? 'Βρέθηκε στο αντίγραφο' : 'Από $when';
    }
  }

  String _countedDetail(
    RestorePortablePart part,
    int count,
    String singular,
    String plural,
  ) {
    final text = count == 1 ? '1 $singular' : '$count $plural';
    if (!_losesFiles(part)) return text;
    final local = widget.localCounts.forPart(part);
    return '$text — έχετε $local, θα μείνουν $count';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '';
    final d = value.day.toString().padLeft(2, '0');
    final m = value.month.toString().padLeft(2, '0');
    return '$d/$m/${value.year}';
  }

  String _originText() {
    if (!widget.manifest.isKnown) {
      return 'Άγνωστη προέλευση (παλαιότερο αντίγραφο χωρίς μεταδεδομένα).';
    }
    final original = widget.manifest.originalDatabasePath?.trim() ?? '';
    if (original.isEmpty) {
      return 'Άγνωστη προέλευση.';
    }
    final currentNorm = p.normalize(widget.currentDatabasePath);
    final originalNorm = p.normalize(original);
    final differs =
        currentNorm.replaceAll('/', '\\').toLowerCase() !=
        originalNorm.replaceAll('/', '\\').toLowerCase();
    final buffer = StringBuffer('Αρχική διαδρομή βάσης:\n$original');
    if (differs) {
      buffer.write(
        '\n\nΗ αρχική διαδρομή διαφέρει από την τρέχουσα βάση '
        '(${widget.currentDatabasePath}).',
      );
    }
    if (widget.manifest.createdAt != null) {
      buffer.write('\nΔημιουργία αντιγράφου: ${widget.manifest.createdAt}');
    }
    if (widget.manifest.appVersion != null) {
      buffer.write('\nΈκδοση εφαρμογής: ${widget.manifest.appVersion}');
    }
    return buffer.toString();
  }

  String _destinationLabel(RestoreDestinationChoice choice) {
    switch (choice) {
      case RestoreDestinationChoice.currentDatabase:
        return 'Με το τρέχον όνομα '
            '(${p.basename(widget.currentDatabasePath)})';
      case RestoreDestinationChoice.backupName:
        return 'Με το όνομα του αντιγράφου '
            '(${p.basename(_targetPathFor(choice))})';
    }
  }

  String _targetPathFor(RestoreDestinationChoice choice) {
    return resolveRestoreTargetPath(
      choice: choice,
      currentDatabasePath: widget.currentDatabasePath,
      backupDatabaseFileName: widget.preferredDatabaseFileName,
    );
  }

  String _preservationText() {
    switch (_destination) {
      case RestoreDestinationChoice.currentDatabase:
        final preRestoreName =
            DatabaseFileReplacement.previewPreRestoreFileName(
              widget.currentDatabasePath,
            );
        return 'Η τρέχουσα βάση θα φυλαχτεί ως:\n$preRestoreName';
      case RestoreDestinationChoice.backupName:
        final currentName = p.basename(widget.currentDatabasePath);
        final target = _targetPathFor(RestoreDestinationChoice.backupName);
        if (!widget.backupNameTargetExists) {
          return 'Η τρέχουσα βάση ($currentName) παραμένει στη θέση της.';
        }
        final preRestoreName =
            DatabaseFileReplacement.previewPreRestoreFileName(target);
        return 'Η τρέχουσα βάση ($currentName) παραμένει στη θέση της.\n'
            'Το υπάρχον αρχείο «${p.basename(target)}» θα φυλαχτεί ως:\n'
            '$preRestoreName';
    }
  }
}

/// Μία γραμμή της λίστας «τι θα επαναφερθεί»: κουτάκι, εικονίδιο, τι φέρνει.
class _SelectionRow extends StatelessWidget {
  const _SelectionRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.detailIsWarning = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool value;
  final bool enabled;
  final bool detailIsWarning;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      value: value,
      onChanged: enabled ? (v) => onChanged(v ?? false) : null,
      title: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 26),
        child: Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: detailIsWarning
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.current, required this.backup});

  final DatabaseFileProfile? current;
  final DatabaseFileProfile backup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String text, {bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: Text(
        text,
        style: header ? theme.textTheme.labelLarge : theme.textTheme.bodyMedium,
      ),
    );

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
      },
      children: [
        TableRow(
          children: [
            cell('', header: true),
            cell(_headerWithVersion('Τρέχουσα', current), header: true),
            cell(_headerWithVersion('Αντίγραφο', backup), header: true),
          ],
        ),
        _row('Κλήσεις', current?.callCount, backup.callCount, cell),
        _row('Υπάλληλοι', current?.userCount, backup.userCount, cell),
        _row(
          'Εξοπλισμός',
          current?.equipmentCount,
          backup.equipmentCount,
          cell,
        ),
        TableRow(
          children: [
            cell('Τελευταία κλήση'),
            cell(_dateOrDash(current?.latestCallDate)),
            cell(_dateOrDash(backup.latestCallDate)),
          ],
        ),
      ],
    );
  }

  TableRow _row(
    String label,
    int? currentValue,
    int? backupValue,
    Widget Function(String, {bool header}) cell,
  ) {
    return TableRow(
      children: [
        cell(label),
        cell(_countOrDash(currentValue)),
        cell(_countOrDash(backupValue)),
      ],
    );
  }

  /// «Τρέχουσα (έκδοση 59)» — η ασυμβατότητα σχήματος πρέπει να φαίνεται
  /// ΠΡΙΝ την επαναφορά, όχι να ανακαλύπτεται μετά.
  String _headerWithVersion(String label, DatabaseFileProfile? profile) {
    final version = profile?.userVersion;
    if (version == null || version <= 0) return label;
    return '$label (έκδ. $version)';
  }

  String _countOrDash(int? value) => value == null ? '—' : '$value';

  String _dateOrDash(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? '—' : trimmed;
  }
}
