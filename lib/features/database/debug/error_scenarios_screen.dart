import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/database_integrity_panel.dart';
import 'integrity_debug_provider_refresh.dart';
import 'integrity_debug_seeder_service.dart';

/// Οθόνη δημιουργίας σενάριων σφαλμάτων για δοκιμή UX (μόνο debug desktop).
class ErrorScenariosScreen extends ConsumerStatefulWidget {
  const ErrorScenariosScreen({super.key});

  @override
  ConsumerState<ErrorScenariosScreen> createState() =>
      _ErrorScenariosScreenState();
}

class _ErrorScenariosScreenState extends ConsumerState<ErrorScenariosScreen> {
  bool _seeding = false;
  bool _seedSucceeded = false;
  String? _seedError;

  Future<void> _createProblematicDatabase() async {
    if (_seeding) return;
    setState(() {
      _seeding = true;
      _seedError = null;
      _seedSucceeded = false;
    });

    try {
      final service = ref.read(integrityDebugSeederServiceProvider);
      final result = await service.seedAndActivate();
      if (!mounted) return;

      if (!result.success) {
        setState(() {
          _seedError = result.errorMessage ?? 'Αποτυχία δημιουργίας debug βάσης.';
        });
        return;
      }

      await refreshProvidersAfterIntegrityDebugSwitch(ref);
      if (!mounted) return;
      setState(() => _seedSucceeded = true);
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  void _openIntegrityCheck() {
    DatabaseIntegrityDialog.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Σενάρια σφαλμάτων',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Δημιουργία τεχνητών προβλημάτων για δοκιμή της εμπειρίας χρήστη '
          '(dialogs επιβεβαίωσης, επιλογές, μαζική επιδιόρθωση κ.λπ.).',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (_seedSucceeded) ...[
          Material(
            color: scheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                        children: [
                          TextSpan(
                            text:
                                'Η βάση ${IntegrityDebugSeederService.databaseFileName} '
                                'δημιουργήθηκε και φορτώθηκε από την εφαρμογή. '
                                'Κάντε κλικ ',
                          ),
                          TextSpan(
                            text: 'εδώ',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = _openIntegrityCheck,
                          ),
                          const TextSpan(text: ' για έλεγχο.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_seedError != null) ...[
          Material(
            color: scheme.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: scheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _seedError!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: _seeding ? null : _createProblematicDatabase,
          icon: _seeding
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : const Icon(Icons.storage_outlined),
          label: Text(
            _seeding
                ? 'Δημιουργία προβληματικής βάσης…'
                : 'Δημιουργία προβληματικής βάσης',
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Πρόσθετα σενάρια',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Εδώ θα προστεθούν επιπλέον κουμπιά για άλλους τύπους δοκιμών.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
