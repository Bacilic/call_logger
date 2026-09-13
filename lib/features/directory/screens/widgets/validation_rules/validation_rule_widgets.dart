/// Τα δομικά κομμάτια της οθόνης «Κανόνες επικύρωσης».
///
/// Καθαρή παρουσίαση: καμία γνώση των κανόνων, της σάρωσης ή των διαδρομών —
/// μόνο σχήματα που δέχονται περιεχόμενο και επιστρέφουν χειρονομίες. Ζουν
/// χωριστά ώστε η προσθήκη ενός κανόνα να μην ανοίγει το αρχείο που ορίζει
/// πώς δείχνει μια κάρτα.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/catalog_validation_rules.dart';

/// Ο τόνος ενός πλαισίου μηνύματος: προειδοποίηση ή καθαρό αποτέλεσμα.
enum StatusBannerTone { warning, success }

/// Χρωματιστό πλαίσιο μηνύματος με εικονίδιο.
///
/// Ένα σχήμα για όλα τα μηνύματα της οθόνης — η προειδοποίηση των κανόνων,
/// το καθαρό αποτέλεσμα της σάρωσης, οι διαδρομές που βρέθηκαν και οι ομάδες
/// που δεν ελέγχθηκαν. Ήταν τέσσερα σχεδόν πανομοιότυπα widgets· κάθε αλλαγή
/// στο περίγραμμα ή στη διαφάνεια έπρεπε να γίνει τέσσερις φορές.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.icon,
    required this.tone,
    required this.message,
    this.title,
  });

  final IconData icon;
  final StatusBannerTone tone;

  /// Έντονη πρώτη γραμμή. Όταν λείπει, το πλαίσιο έχει μόνο το [message].
  final String? title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = tone == StatusBannerTone.warning ? Colors.orange : Colors.green;
    final foreground = base.shade800;
    final headline = title;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: headline == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: headline == null
                ? Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foreground,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Έτοιμα πακέτα κανόνων — αφετηρία, όχι κλειδαριά.
///
/// Το επιλεγμένο επίπεδο δεν αποθηκεύεται: έρχεται υπολογισμένο από τους
/// ίδιους τους διακόπτες. Μόλις ο χρήστης αλλάξει έναν, κανένα κουμπί δεν
/// μένει πατημένο και εμφανίζεται το «Προσαρμοσμένο» — και αν κάποτε
/// ξαναφέρει τους διακόπτες ακριβώς σε ένα πακέτο, το κουμπί ανάβει μόνο του.
class StrictnessCard extends StatelessWidget {
  const StrictnessCard({super.key, required this.level, required this.onPick});

  final CatalogStrictnessLevel? level;
  final ValueChanged<CatalogStrictnessLevel> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Επίπεδο ελέγχων', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            // Χωρίς επιλογή όταν οι διακόπτες δεν ταιριάζουν σε κανένα πακέτο.
            SegmentedButton<CatalogStrictnessLevel>(
              segments: [
                for (final option in CatalogStrictnessLevel.values)
                  ButtonSegment<CatalogStrictnessLevel>(
                    value: option,
                    label: Text(option.label),
                  ),
              ],
              selected: level == null ? const {} : {level!},
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              onSelectionChanged: (picked) {
                if (picked.isEmpty) return;
                onPick(picked.first);
              },
            ),
            const SizedBox(height: 8),
            Text(
              level?.description ??
                  'Προσαρμοσμένο — έχετε αλλάξει κανόνες μόνοι σας. '
                      'Διαλέξτε επίπεδο για να ξεκινήσετε από πακέτο.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 4),
            Text(
              'Τα επίπεδα αλλάζουν μόνο ποιοι έλεγχοι είναι ενεργοί. '
              'Τα ψηφία, τα προθέματα και οι εξαιρέσεις μένουν όπως τα '
              'έχετε ρυθμίσει.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Κάρτα οντότητας (Τηλέφωνα/Εξοπλισμός/Τμήματα/Υπάλληλοι) με τους
/// κανόνες της σε γραμμές.
class RuleCard extends StatelessWidget {
  const RuleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            for (final child in children) ...[
              const Divider(height: 12),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// Μία γραμμή κανόνα: περιεχόμενο αριστερά, διακόπτης δεξιά,
/// προαιρετική σημείωση + παράδειγμα υπόδειξης από κάτω.
class RuleRow extends StatelessWidget {
  const RuleRow({
    super.key,
    required this.enabled,
    required this.onToggle,
    required this.child,
    required this.example,
    this.note,
  });

  final bool enabled;
  final ValueChanged<bool> onToggle;
  final Widget child;
  final String example;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                child,
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            note!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    example,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

/// Απλή γραμμή κειμένου κανόνα — ό,τι δεν έχει δικό του πεδίο.
class RuleLabel extends StatelessWidget {
  const RuleLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodyMedium);
  }
}

/// Το μήνυμα ορίων για μια αριθμητική ρύθμιση — `null` όταν η τιμή είναι δεκτή.
///
/// Το κενό πεδίο **δεν** είναι σφάλμα: ο χρήστης σβήνει για να γράψει από την
/// αρχή, και ένα κόκκινο μήνυμα στη μέση της πληκτρολόγησης ενοχλεί.
String? ruleNumberFieldError({
  required String raw,
  required int min,
  required int max,
}) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final value = int.tryParse(text);
  if (value == null) return null;
  if (value < min) return 'Ελάχιστο: $min';
  if (value > max) return 'Μέγιστο: $max';
  return null;
}

/// «Ετικέτα: [αριθμός]» σε μία γραμμή.
///
/// **Αποθηκεύει με Enter ή όταν φύγει η εστίαση**, ποτέ σε κάθε πλήκτρο:
/// γράφοντας «12» στα ψηφία, το ενδιάμεσο «1» είναι κι αυτό έγκυρη τιμή και
/// γινόταν στιγμιαία αληθινός κανόνας για όλες τις φόρμες.
///
/// Τιμή εκτός ορίων προσαρμόζεται στο όριο και **φαίνεται** στο πεδίο· άδειο
/// πεδίο επαναφέρει ό,τι ισχύει. Έτσι η οθόνη δεν δείχνει ποτέ κάτι που δεν
/// αποθηκεύτηκε.
class InlineNumberField extends StatelessWidget {
  const InlineNumberField({
    super.key,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.maxLength,
    required this.min,
    required this.max,
    required this.currentValue,
    required this.onCommitted,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxLength;
  final int min;
  final int max;

  /// Η τιμή που ισχύει τώρα — επιστρέφει στο πεδίο όταν ο χρήστης το αδειάσει.
  final int currentValue;
  final ValueChanged<int> onCommitted;

  void _commit() {
    final value = int.tryParse(controller.text.trim());
    if (value == null) {
      controller.text = '$currentValue';
      return;
    }
    final applied = value.clamp(min, max);
    if (controller.text != '$applied') controller.text = '$applied';
    // Το απλό πέρασμα από το πεδίο δεν είναι αλλαγή — καμία περιττή εγγραφή.
    if (applied != currentValue) onCommitted(applied);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(width: 8),
        _CommitNumberBox(
          controller: controller,
          focusNode: focusNode,
          maxLength: maxLength,
          min: min,
          max: max,
          onCommit: _commit,
        ),
      ],
    );
  }
}

/// «Ετικέτα: [από] έως [έως]» σε μία γραμμή.
///
/// Ίδιος χρονισμός με το [InlineNumberField]. Επιπλέον κρατά τη σχέση των δύο
/// άκρων: ένα «από» μεγαλύτερο από το «έως» δεν αποθηκεύεται, το λέει, και τα
/// πεδία επιστρέφουν σε ό,τι ισχύει.
class InlineRangeFields extends StatefulWidget {
  const InlineRangeFields({
    super.key,
    required this.label,
    required this.fromController,
    required this.toController,
    required this.fromFocusNode,
    required this.toFocusNode,
    required this.min,
    required this.max,
    required this.currentFrom,
    required this.currentTo,
    required this.onCommitted,
  });

  final String label;
  final TextEditingController fromController;
  final TextEditingController toController;
  final FocusNode fromFocusNode;
  final FocusNode toFocusNode;
  final int min;
  final int max;
  final int currentFrom;
  final int currentTo;
  final void Function(int from, int to) onCommitted;

  @override
  State<InlineRangeFields> createState() => _InlineRangeFieldsState();
}

class _InlineRangeFieldsState extends State<InlineRangeFields> {
  String? _orderError;

  void _commit() {
    final from = int.tryParse(widget.fromController.text.trim());
    final to = int.tryParse(widget.toController.text.trim());

    // Άδειο ή αδιάβαστο άκρο επιστρέφει σε ό,τι ισχύει — μόνο αυτό, όχι και
    // το διπλανό που ο χρήστης μόλις έγραψε.
    if (from == null) widget.fromController.text = '${widget.currentFrom}';
    if (to == null) widget.toController.text = '${widget.currentTo}';
    if (from == null || to == null) {
      _setOrderError(null);
      return;
    }

    final appliedFrom = from.clamp(widget.min, widget.max);
    final appliedTo = to.clamp(widget.min, widget.max);

    // Τα γραμμένα μένουν στη θέση τους: ο χρήστης που ανεβάζει και τα δύο
    // άκρα περνά αναγκαστικά από μια στιγμή όπου το «από» ξεπερνά το «έως»,
    // και μια επαναφορά εκεί θα του έσβηνε ό,τι μόλις πληκτρολόγησε. Το
    // κόκκινο μήνυμα λέει καθαρά ότι αυτό που φαίνεται δεν ισχύει ακόμη.
    if (appliedFrom > appliedTo) {
      _setOrderError('Το «από» δεν μπορεί να ξεπερνά το «έως»');
      return;
    }

    if (widget.fromController.text != '$appliedFrom') {
      widget.fromController.text = '$appliedFrom';
    }
    if (widget.toController.text != '$appliedTo') {
      widget.toController.text = '$appliedTo';
    }
    _setOrderError(null);
    if (appliedFrom != widget.currentFrom || appliedTo != widget.currentTo) {
      widget.onCommitted(appliedFrom, appliedTo);
    }
  }

  void _setOrderError(String? message) {
    if (!mounted || _orderError == message) return;
    setState(() => _orderError = message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(widget.label, style: theme.textTheme.bodyMedium),
        _CommitNumberBox(
          controller: widget.fromController,
          focusNode: widget.fromFocusNode,
          maxLength: 2,
          min: widget.min,
          max: widget.max,
          onCommit: _commit,
        ),
        Text('έως', style: theme.textTheme.bodyMedium),
        _CommitNumberBox(
          controller: widget.toController,
          focusNode: widget.toFocusNode,
          maxLength: 2,
          min: widget.min,
          max: widget.max,
          onCommit: _commit,
        ),
        if (_orderError != null)
          Text(
            _orderError!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// Πεδίο κειμένου ρύθμισης που αποθηκεύει με Enter ή στην έξοδο.
///
/// Ίδιος κανόνας με τα αριθμητικά: μια ρύθμιση γράφεται όταν ο χρήστης δηλώσει
/// ότι τελείωσε. Γράφοντας «(, -», κάθε ενδιάμεσο βήμα ήταν μια εγγραφή στη
/// βάση και μια ακύρωση της cache των κανόνων.
class CommitTextField extends StatefulWidget {
  const CommitTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.width,
    required this.onCommitted,
    this.hintText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double width;
  final String? hintText;
  final ValueChanged<String> onCommitted;

  @override
  State<CommitTextField> createState() => _CommitTextFieldState();
}

class _CommitTextFieldState extends State<CommitTextField> {
  late String _lastCommitted;

  @override
  void initState() {
    super.initState();
    _lastCommitted = widget.controller.text;
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) _commit();
  }

  void _commit() {
    final text = widget.controller.text;
    if (text == _lastCommitted) return;
    _lastCommitted = text;
    widget.onCommitted(text);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hintText,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          border: const OutlineInputBorder(),
        ),
        onEditingComplete: _commit,
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

/// Το κουτί του αριθμού: δείχνει τα όρια όσο γράφεται, και ειδοποιεί τον
/// γονέα μόνο όταν ο χρήστης δηλώσει ότι τελείωσε.
///
/// Το `onEditingComplete` από μόνο του δεν πιάνει το κλικ αλλού — γι' αυτό
/// ακούει και τον [focusNode].
class _CommitNumberBox extends StatefulWidget {
  const _CommitNumberBox({
    required this.controller,
    required this.focusNode,
    required this.maxLength,
    required this.min,
    required this.max,
    required this.onCommit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxLength;
  final int min;
  final int max;
  final VoidCallback onCommit;

  @override
  State<_CommitNumberBox> createState() => _CommitNumberBoxState();
}

class _CommitNumberBoxState extends State<_CommitNumberBox> {
  String? _error;

  /// Το κείμενο όπως έμεινε μετά την τελευταία αποθήκευση.
  ///
  /// Το Enter πυροδοτεί **και** `onEditingComplete` **και** `onSubmitted`, και
  /// αμέσως μετά χάνεται η εστίαση: χωρίς αυτόν τον φύλακα, μία αλλαγή θα
  /// γινόταν τρεις εγγραφές στη βάση. Κρατά επίσης ήσυχο το απλό πέρασμα με
  /// Tab, όπου τίποτα δεν άλλαξε.
  late String _lastCommitted;

  @override
  void initState() {
    super.initState();
    _lastCommitted = widget.controller.text;
    widget.focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final next = ruleNumberFieldError(
      raw: widget.controller.text,
      min: widget.min,
      max: widget.max,
    );
    if (next == _error || !mounted) return;
    setState(() => _error = next);
  }

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus) return;
    _commit();
  }

  /// Ο γονέας μπορεί να ψαλιδίσει την τιμή και να τη γράψει πίσω· ό,τι μείνει
  /// στο πεδίο είναι αυτό που θεωρείται πια αποθηκευμένο.
  void _commit() {
    if (widget.controller.text == _lastCommitted) return;
    widget.onCommit();
    _lastCommitted = widget.controller.text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorBorder = _error == null
        ? null
        : OutlineInputBorder(
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(widget.maxLength),
            ],
            // Το κόκκινο μπαίνει ως περίγραμμα και όχι ως `errorText`: το
            // πεδίο στέκεται μέσα σε γραμμή κειμένου, και μήνυμα από κάτω θα
            // την έσπαγε στα δύο.
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: const OutlineInputBorder(),
              enabledBorder: errorBorder,
              focusedBorder: errorBorder,
            ),
            onEditingComplete: _commit,
            onSubmitted: (_) => _commit(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(width: 6),
          Text(
            _error!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
