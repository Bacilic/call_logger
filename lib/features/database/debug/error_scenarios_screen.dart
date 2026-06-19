import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/main_nav_request_provider.dart';
import '../../../core/widgets/main_nav_destination.dart';
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

  void _openNewCallWithDokimastikoDepartment() {
    ref.read(mainNavRequestProvider.notifier).request(
          MainNavRequest(
            destination: MainNavDestination.calls,
            callPrefillDepartmentName:
                IntegrityDebugSeederService.dokimastikoDepartmentName,
          ),
        );
  }

  String _formatGreekList(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} και ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')} και ${items.last}';
  }

  String get _dokimastikoPhonesLabel =>
      _formatGreekList(IntegrityDebugSeederService.dokimastikoSharedPhones);

  String get _dokimastikoEquipmentLabel => _formatGreekList(
        IntegrityDebugSeederService.dokimastikoSharedEquipmentCodes,
      );

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
                    child: Text(
                      'Η βάση ${IntegrityDebugSeederService.databaseFileName} '
                      'δημιουργήθηκε και φορτώθηκε από την εφαρμογή.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
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
          'Σενάρια',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (_seedSucceeded) ...[
          _ErrorScenarioCard(
            icon: Icons.fact_check_outlined,
            title: 'Έλεγχος ακεραιότητας βάσης',
            descriptionSpans: [
              const TextSpan(text: 'Κάντε κλικ '),
              _linkSpan(
                scheme: scheme,
                onTap: _openIntegrityCheck,
              ),
              const TextSpan(
                text: ' για να ελέγξετε την ορθή επίλυση των διαφορών.',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ErrorScenarioCard(
            icon: Icons.phone_in_talk_outlined,
            title: 'Μη εμφάνιση τηλεφώνων τμήματος',
            descriptionSpans: [
              TextSpan(
                text:
                    'Το τμήμα ${IntegrityDebugSeederService.dokimastikoDepartmentName} '
                    'με κοινόχρηστα τηλέφωνα: $_dokimastikoPhonesLabel '
                    'και κοινόχρηστο εξοπλισμό: $_dokimastikoEquipmentLabel '
                    'δημιουργήθηκε. Κάντε κλικ ',
              ),
              _linkSpan(
                scheme: scheme,
                onTap: _openNewCallWithDokimastikoDepartment,
              ),
              const TextSpan(text: ' για έλεγχο.'),
            ],
          ),
        ] else
          Text(
            'Δημιουργήστε πρώτα την προβληματική βάση για να ενεργοποιηθούν τα σενάρια.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

TextSpan _linkSpan({
  required ColorScheme scheme,
  required VoidCallback onTap,
}) {
  return TextSpan(
    text: 'εδώ',
    style: TextStyle(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    ),
    recognizer: TapGestureRecognizer()..onTap = onTap,
  );
}

/// Κάρτα ενός σεναρίου σφάλματος: εικονίδιο + τίτλος (έντονα:) + περιγραφή σε μία γραμμή.
class _ErrorScenarioCard extends StatelessWidget {
  const _ErrorScenarioCard({
    required this.icon,
    required this.title,
    required this.descriptionSpans,
  });

  final IconData icon;
  final String title;
  final List<InlineSpan> descriptionSpans;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurface,
    );

    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: bodyStyle,
                  children: [
                    TextSpan(
                      text: '$title: ',
                      style: bodyStyle?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    ...descriptionSpans,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
