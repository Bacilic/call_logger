import 'dart:async';

import 'package:flutter/material.dart';

/// Περιεχόμενο SnackBar διαγραφής εξοπλισμού: μήνυμα + κουμπιά στην ίδια γραμμή
/// με ορατή αντίστροφη μέτρηση στο «Επιβεβαίωση (N)».
class EquipmentDeleteCountdownSnackBarContent extends StatefulWidget {
  const EquipmentDeleteCountdownSnackBarContent({
    super.key,
    required this.message,
    required this.onConfirm,
    required this.onUndo,
    this.seconds = 5,
  });

  final String message;
  final VoidCallback onConfirm;
  final VoidCallback onUndo;
  final int seconds;

  @override
  State<EquipmentDeleteCountdownSnackBarContent> createState() =>
      _EquipmentDeleteCountdownSnackBarContentState();
}

class _EquipmentDeleteCountdownSnackBarContentState
    extends State<EquipmentDeleteCountdownSnackBarContent> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _timer?.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(widget.message),
            ),
          ),
        ),
        TextButton(
          onPressed: widget.onConfirm,
          child: Text('Επιβεβαίωση ($_secondsLeft)'),
        ),
        TextButton(
          onPressed: widget.onUndo,
          child: const Text('Αναίρεση'),
        ),
      ],
    );
  }
}
