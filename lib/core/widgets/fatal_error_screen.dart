import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors/app_error_result.dart';

/// Οθόνη πλήρους σφάλματος για runtime errors εκτός ροής βάσης δεδομένων.
class FatalErrorScreen extends StatefulWidget {
  const FatalErrorScreen({
    super.key,
    required this.result,
    required this.onRetry,
  });

  final AppErrorResult result;
  final Future<void> Function() onRetry;

  @override
  State<FatalErrorScreen> createState() => _FatalErrorScreenState();
}

class _FatalErrorScreenState extends State<FatalErrorScreen> {
  late final ScrollController _detailsScrollController;

  @override
  void initState() {
    super.initState();
    _detailsScrollController = ScrollController();
  }

  @override
  void dispose() {
    _detailsScrollController.dispose();
    super.dispose();
  }

  bool get _isLayoutError =>
      widget.result.kind == AppErrorKind.uiLayoutError;

  Future<void> _copyFullReport(BuildContext context) async {
    final text = widget.result.buildClipboardReport();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Αντιγράφηκε πλήρης αναφορά σφάλματος στο πρόχειρο.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = widget.result.technicalSummary.trim();
    final original = widget.result.originalExceptionText?.trim();
    final stack = widget.result.stackTraceText?.trim();

    final iconColor = _isLayoutError
        ? Colors.amber.shade700
        : theme.colorScheme.error;
    final titleColor = _isLayoutError
        ? Colors.amber.shade800
        : theme.colorScheme.error;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                _isLayoutError
                    ? Icons.warning_amber_rounded
                    : Icons.error_outline,
                size: 56,
                color: iconColor,
              ),
              const SizedBox(height: 16),
              Text(
                widget.result.friendlyTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Scrollbar(
                  controller: _detailsScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _detailsScrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (summary.isNotEmpty) ...[
                          SelectableText(
                            summary,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (original != null &&
                            original.isNotEmpty &&
                            original != summary) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Αρχικό μήνυμα σφάλματος (runtime)',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            original,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (stack != null && stack.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Stack trace',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            stack,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _copyFullReport(context),
                icon: const Icon(Icons.copy),
                label: const Text('Αντιγραφή πλήρους σφάλματος'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await widget.onRetry();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Επαναδοκιμή'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
