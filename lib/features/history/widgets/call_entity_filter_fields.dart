/// Τα χειριστήρια των φίλτρων «ποιανού είναι η κλήση»: τμήμα, υπάλληλος,
/// εξοπλισμός.
///
/// Γράφονται χωριστά από τις οθόνες γιατί τα ίδια τρία φίλτρα ζουν και στα
/// Στατιστικά Κλήσεων και στο Ιστορικό. Όταν έρθει ο ανασχεδιασμός τους
/// (αυτόματη συμπλήρωση αντί για ελεύθερο κείμενο), αλλάζουν **εδώ** μία φορά
/// και οι δύο οθόνες τον παίρνουν μαζί.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/user_facing_error_messages.dart';

/// Επιλογή τμήματος από κλειστή λίστα — «Όλα τα Τμήματα» σημαίνει χωρίς φίλτρο.
class CallDepartmentFilterField extends StatelessWidget {
  const CallDepartmentFilterField({
    super.key,
    required this.departments,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final AsyncValue<List<String>> departments;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return departments.when(
      data: (names) {
        final options = <String?>[null, ...names];
        return DropdownButtonFormField<String?>(
          initialValue: options.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Τμήμα',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: options
              .map(
                (name) => DropdownMenuItem<String?>(
                  value: name,
                  child: Text(name ?? '— Όλα τα Τμήματα —'),
                ),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(10),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Text(
        'Σφάλμα φόρτωσης τμημάτων: ${humanizeUserFacingError(e)}',
        style: TextStyle(color: theme.colorScheme.error),
      ),
    );
  }
}

/// Πεδίο ελεύθερου κειμένου για φίλτρο υπαλλήλου ή εξοπλισμού.
///
/// Κρατά μόνο του το κείμενο και τη μικρή αναμονή πληκτρολόγησης, ώστε η οθόνη
/// να δηλώνει απλώς «αυτή είναι η τιμή, ειδοποίησέ με όταν αλλάξει».
///
/// **Ακολουθεί τις αλλαγές που έρχονται απ' έξω** — π.χ. όταν το «Προβολή όλων»
/// φέρνει το φίλτρο του Πίνακα Ελέγχου — αλλά **ποτέ όσο ο χρήστης γράφει μέσα
/// του**: αλλιώς μια καθυστερημένη ενημέρωση θα του έσβηνε τα γράμματα.
class CallEntityTextFilterField extends StatefulWidget {
  const CallEntityTextFilterField({
    super.key,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.label,
    this.hintText,
    this.clearTooltip = 'Καθαρισμός',
    this.enabled = true,
    this.debounce = const Duration(milliseconds: 350),
  });

  /// Ετικέτα πάνω από το πεδίο· τα φίλτρα οντότητας τη χρησιμοποιούν.
  final String? label;

  /// Υπόδειξη μέσα στο άδειο πεδίο· η αναζήτηση τη χρησιμοποιεί αντί ετικέτας,
  /// γιατί εξηγεί σε ολόκληρη πρόταση πού ψάχνει.
  final String? hintText;
  final String clearTooltip;
  final IconData icon;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final Duration debounce;

  @override
  State<CallEntityTextFilterField> createState() =>
      _CallEntityTextFilterFieldState();
}

class _CallEntityTextFilterFieldState extends State<CallEntityTextFilterField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value ?? '',
  );
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;

  @override
  void didUpdateWidget(covariant CallEntityTextFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus) return;
    final incoming = widget.value ?? '';
    if (incoming == _controller.text) return;
    _debounceTimer?.cancel();
    _controller.text = incoming;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounce, () {
      final text = raw.trim();
      widget.onChanged(text.isEmpty ? null : text);
    });
  }

  void _clear() {
    _debounceTimer?.cancel();
    _controller.clear();
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      onChanged: _onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        hintMaxLines: 1,
        prefixIcon: Icon(widget.icon, size: 18),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.close),
              tooltip: widget.clearTooltip,
              onPressed: widget.enabled ? _clear : null,
            );
          },
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}
