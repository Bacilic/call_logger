import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/compact_tooltip.dart';

/// Το μήνυμα ορίων για μια τιμή — `null` όταν η τιμή είναι δεκτή.
///
/// Καθαρή λογική, χωρίς widgets: το ίδιο κείμενο κρίνεται και από τα τεστ.
/// Το κενό πεδίο **δεν** είναι σφάλμα — ο χρήστης απλώς σβήνει για να γράψει
/// από την αρχή, και ένα κόκκινο μήνυμα στη μέση της πληκτρολόγησης ενοχλεί.
String? backupIntFieldError({
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

/// Αριθμητική ρύθμιση αντιγράφων: κείμενο, πεδίο, μονάδα — σε μία γραμμή.
///
/// **Αποθηκεύει όταν φύγει η εστίαση**, όχι μόνο με Enter. Το `onEditingComplete`
/// από μόνο του δεν πιάνει το κλικ αλλού ούτε το κλείσιμο του διαλόγου: ο
/// χρήστης έγραφε «3», έφευγε, και η τιμή χανόταν σιωπηλά — ο διάλογος
/// ξανάνοιγε με την παλιά.
///
/// Όσο η τιμή είναι εκτός ορίων το πεδίο το λέει· μόλις φύγει η εστίαση, η
/// τιμή προσαρμόζεται στο όριο και φαίνεται στο πεδίο. Έτσι δεν αποθηκεύεται
/// ποτέ άκυρη τιμή, και ο χρήστης βλέπει τι ίσχυσε τελικά.
class BackupIntSettingField extends StatefulWidget {
  const BackupIntSettingField({
    required this.leadingText,
    required this.trailingText,
    required this.controller,
    required this.focusNode,
    required this.min,
    required this.max,
    required this.onPersist,
    this.limitHint,
    this.limitTooltip,
    super.key,
  });

  final String leadingText;
  final String trailingText;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Τα όρια που επιβάλλει η αποθήκευση — εδώ μόνο ανακοινώνονται.
  final int min;
  final int max;

  /// Αποθηκεύει και γράφει πίσω στο πεδίο την τιμή που τελικά ίσχυσε.
  final Future<void> Function() onPersist;

  /// Σύντομη υπενθύμιση δίπλα στο πεδίο (π.χ. «ελάχιστο 15 λεπτά»).
  final String? limitHint;

  /// Η αναλυτική εξήγηση, στο εικονίδιο πληροφοριών — για να μη φουσκώνει η
  /// γραμμή με ολόκληρη πρόταση.
  final String? limitTooltip;

  @override
  State<BackupIntSettingField> createState() => _BackupIntSettingFieldState();
}

class _BackupIntSettingFieldState extends State<BackupIntSettingField> {
  String? _error;

  @override
  void initState() {
    super.initState();
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
    final next = backupIntFieldError(
      raw: widget.controller.text,
      min: widget.min,
      max: widget.max,
    );
    if (next == _error || !mounted) return;
    setState(() => _error = next);
  }

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus) return;
    // Η αποθήκευση ψαλιδίζει και γράφει πίσω την τιμή που ίσχυσε· το σφάλμα
    // δεν έχει πια τι να δείξει.
    unawaited(widget.onPersist());
    if (mounted && _error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = widget.limitHint;
    final tooltip = widget.limitTooltip;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(widget.leadingText, style: theme.textTheme.bodyLarge),
          SizedBox(
            width: 64,
            child: TextField(
              focusNode: widget.focusNode,
              controller: widget.controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              // Το κόκκινο περίγραμμα μπαίνει με χρώμα και όχι με `errorText`:
              // το πεδίο είναι 64 pixel σε μια γραμμή που κυλά, και ένα
              // μήνυμα σφάλματος από κάτω θα το έσπαγε. Το κείμενο του
              // σφάλματος στέκεται δίπλα, στη θέση της υπενθύμισης ορίων.
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                enabledBorder: _error == null
                    ? null
                    : OutlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.error,
                          width: 2,
                        ),
                      ),
                focusedBorder: _error == null
                    ? null
                    : OutlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.error,
                          width: 2,
                        ),
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ),
              ),
              onEditingComplete: () => unawaited(widget.onPersist()),
              onSubmitted: (_) => unawaited(widget.onPersist()),
            ),
          ),
          Text(widget.trailingText, style: theme.textTheme.bodyLarge),
          if (_error != null)
            Text(
              _error!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (hint != null)
            Text(
              hint,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (tooltip != null)
            CompactTooltip(
              message: tooltip,
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
