import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Εμφανίζει μία φορά ενημερωτικό διάλογο όταν η εφαρμογή επανεκκινήθηκε
/// αυτόματα από τα Windows μετά από κατάρρευση ή κόλλημα.
class CrashRestartNotice extends StatefulWidget {
  CrashRestartNotice({
    super.key,
    required this.child,
    bool? showNotice,
  }) : showNotice = showNotice ?? AppConfig.wasRestartedAfterCrash;

  final Widget child;
  final bool showNotice;

  @override
  State<CrashRestartNotice> createState() => _CrashRestartNoticeState();
}

class _CrashRestartNoticeState extends State<CrashRestartNotice> {
  @override
  void initState() {
    super.initState();
    if (widget.showNotice) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNoticeDialog());
    }
  }

  Future<void> _showNoticeDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Αυτόματη επανεκκίνηση'),
        content: const Text(
          'Η εφαρμογή επανεκκινήθηκε αυτόματα μετά από απροσδόκητο πρόβλημα '
          '(π.χ. γραφικών ή κατάρρευση). Τα δεδομένα σας είναι ασφαλή.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ΟΚ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
