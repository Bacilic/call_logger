import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/models/remote_tool.dart';
import '../../../../core/widgets/remote_tool_icon.dart';

/// Πεδίο ονόματος με RawAutocomplete και επικύρωση διπλοτύπου.
class NameAutocompleteField extends StatelessWidget {
  const NameAutocompleteField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.nonDeleted,
    required this.excludeId,
    this.isCreate = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final List<RemoteTool> nonDeleted;
  final int? excludeId;

  /// Στη δημιουργία: ετικέτα με * (υποχρεωτικό πεδίο).
  final bool isCreate;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (s) => s,
      optionsBuilder: (TextEditingValue tev) {
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) {
          return suggestions.take(16);
        }
        return suggestions.where((n) => n.toLowerCase().contains(q)).take(24);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final opt = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(opt),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: isCreate ? 'Όνομα εργαλείου *' : 'Όνομα εργαλείου',
                border: const OutlineInputBorder(),
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                final name = v?.trim() ?? '';
                if (name.isEmpty) return 'Υποχρεωτικό όνομα εργαλείου.';
                final n = name.toLowerCase();
                for (final t in nonDeleted) {
                  if (excludeId != null && t.id == excludeId) continue;
                  if (t.name.trim().toLowerCase() == n) {
                    return 'Υπάρχει ήδη εργαλείο με αυτό το όνομα.';
                  }
                }
                return null;
              },
            );
          },
    );
  }
}

/// Υπάρχει το αρχείο; Πραγματικός έλεγχος δίσκου — **ασύγχρονος**.
Future<bool> _fileExistsOnDisk(String path) => File(path).exists();

class ExecutablePathField extends StatefulWidget {
  const ExecutablePathField({
    super.key,
    required this.controller,
    required this.onPick,
    required this.enabled,
    this.isCreate = false,
    this.checkExists,
  });

  final TextEditingController controller;
  final VoidCallback onPick;
  final bool enabled;

  /// Στη δημιουργία: ετικέτα με * (υποχρεωτικό πεδίο).
  final bool isCreate;

  /// Μόνο για τα τεστ: πλαστός έλεγχος ύπαρξης, ώστε να μη χρειάζεται δίσκος.
  final Future<bool> Function(String path)? checkExists;

  /// Καταλήξεις που εκτελεί απευθείας το `Process.start` (CreateProcess) στα
  /// Windows. Τα `.bat`/`.cmd` δεν τρέχουν χωρίς shell — θεωρούνται μη έγκυρα εδώ.
  static const _winExecutableExtensions = {'.exe', '.com'};

  /// Πόσο περιμένει να ησυχάσει η πληκτρολόγηση πριν ρωτήσει τον δίσκο.
  static const Duration probeDelay = Duration(milliseconds: 300);

  static bool _isWindowsExecutablePath(String path) {
    final lower = path.toLowerCase();
    final sep = lower.lastIndexOf(RegExp(r'[\\/]'));
    final dot = lower.lastIndexOf('.');
    if (dot <= sep) return false;
    return _winExecutableExtensions.contains(lower.substring(dot));
  }

  @override
  State<ExecutablePathField> createState() => _ExecutablePathFieldState();
}

class _ExecutablePathFieldState extends State<ExecutablePathField> {
  Timer? _debounce;

  /// Η διαδρομή που έχει ήδη απαντηθεί, και η απάντησή της.
  ///
  /// Όσο η τρέχουσα διαδρομή δεν είναι αυτή, η ένδειξη σιωπά: καλύτερα τίποτα
  /// για μισό δευτερόλεπτο παρά «δεν βρέθηκε» πάνω σε μισογραμμένη διαδρομή.
  String? _probedPath;
  bool _probedExists = false;
  int _probeSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPathChanged);
    _startProbe(widget.controller.text.trim());
  }

  @override
  void didUpdateWidget(ExecutablePathField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPathChanged);
      widget.controller.addListener(_onPathChanged);
      _startProbe(widget.controller.text.trim());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onPathChanged);
    super.dispose();
  }

  /// Η ένδειξη ακολουθεί το ΙΔΙΟ το πεδίο, όχι ό,τι άλλο αλλάζει στη φόρμα.
  void _onPathChanged() {
    if (mounted) setState(() {});
    _debounce?.cancel();
    final path = widget.controller.text.trim();
    if (path.isEmpty || path == _probedPath) return;
    _debounce = Timer(ExecutablePathField.probeDelay, () => _startProbe(path));
  }

  /// Ρωτά τον δίσκο **μία φορά ανά διαδρομή**, και ποτέ μέσα στο χτίσιμο.
  Future<void> _startProbe(String path) async {
    if (path.isEmpty || path == _probedPath) return;
    final seq = ++_probeSeq;
    final probe = widget.checkExists ?? _fileExistsOnDisk;
    final exists = await probe(path);
    if (!mounted || seq != _probeSeq) return;
    setState(() {
      _probedPath = path;
      _probedExists = exists;
    });
  }

  /// `null` όσο δεν ξέρουμε ακόμη τι λέει ο δίσκος για ΑΥΤΗ τη διαδρομή.
  String? _warningFor(String path) {
    if (path.isEmpty || path != _probedPath) return null;
    if (!_probedExists) return 'Το αρχείο δεν βρέθηκε στη διαδρομή.';
    if (!ExecutablePathField._isWindowsExecutablePath(path)) {
      return 'Το αρχείο δεν είναι εκτελέσιμο των Windows (αναμένεται .exe).';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = widget.controller.text.trim();
    final warningMsg = _warningFor(path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: widget.controller,
                enabled: widget.enabled,
                maxLines: 1,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: widget.isCreate
                      ? 'Κοινή διαδρομή εκτελέσιμου *'
                      : 'Κοινή διαδρομή εκτελέσιμου',
                  // Η κοινή διαδρομή αφορά ΟΛΟΥΣ όσοι ανοίγουν τη βάση: μια
                  // «διόρθωση» για το δικό μας μηχάνημα τη χαλάει για τους
                  // υπόλοιπους. Η ένδειξη δείχνει τον δρόμο στο σωστό πεδίο.
                  helperText:
                      'Ισχύει για όλους — για το δικό σας μηχάνημα '
                      'χρησιμοποιήστε το πεδίο παρακάτω',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Εντοπισμός αρχείου',
              onPressed: widget.enabled ? widget.onPick : null,
              icon: const Icon(Icons.folder_open),
            ),
          ],
        ),
        if (warningMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              warningMsg,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class IconFieldWithPreview extends StatelessWidget {
  const IconFieldWithPreview({
    super.key,
    required this.controller,
    required this.onPick,
    required this.enabled,
  });

  final TextEditingController controller;
  final VoidCallback onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = controller.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: controller,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Εικονίδιο εργαλείου (path ή asset)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Επιλογή εικονιδίου',
              onPressed: enabled ? onPick : null,
              icon: const Icon(Icons.image_outlined),
            ),
            const SizedBox(width: 8),
            _IconPreview(text: raw),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 12),
          child: Text(
            'Διαδρομή προς εικόνα (.png/.svg/.ico) ή asset key. Χρησιμοποιείται στα κουμπιά απομακρυσμένης σύνδεσης. '
            'Προτεραιότητα στο iconAssetKey, fallback στο προεπιλεγμένο εικονίδιο.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    if (text.isEmpty) {
      return const SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0xFFE0E0E0)),
          child: Icon(Icons.image, size: 22),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: RemoteToolIcon(
        iconAssetKey: text,
        size: 22,
        fallback: Icons.image_outlined,
      ),
    );
  }
}
