import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/gemini_ticket_service.dart';
import '../../providers/gemini_settings_provider.dart';
import 'gemini_model_field.dart';
import 'lansweeper_settings_card.dart';

/// Καρτέλα «Τεχνητή Νοημοσύνη»: κλειδί/endpoint, συμπεριφορά και μοντέλα Gemini.
class LansweeperSettingsAiTab extends ConsumerStatefulWidget {
  const LansweeperSettingsAiTab({
    required this.geminiApiKeyController,
    required this.geminiEndpointController,
    required this.geminiPrimaryModelController,
    required this.geminiFallbackModelController,
    required this.onSettingsChanged,
    required this.onAiHelpLink,
    super.key,
  });

  final TextEditingController geminiApiKeyController;
  final TextEditingController geminiEndpointController;
  final TextEditingController geminiPrimaryModelController;
  final TextEditingController geminiFallbackModelController;
  final VoidCallback onSettingsChanged;
  final VoidCallback onAiHelpLink;

  @override
  ConsumerState<LansweeperSettingsAiTab> createState() =>
      _LansweeperSettingsAiTabState();
}

class _LansweeperSettingsAiTabState
    extends ConsumerState<LansweeperSettingsAiTab> {
  bool _obscureGeminiKey = true;

  /// Έχει ο συνδεδεμένος χρήστης δικό του κλειδί (Φάση 3), ή ισχύει το κοινό;
  bool _hasPersonalKey = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshPersonalKeyState());
  }

  Future<void> _refreshPersonalKeyState() async {
    final has = await ref
        .read(geminiApiKeyProvider.notifier)
        .hasPersonalApiKey();
    if (!mounted) return;
    setState(() => _hasPersonalKey = has);
  }

  Future<void> _useSharedKey() async {
    await ref.read(geminiApiKeyProvider.notifier).useSharedApiKey();
    if (!mounted) return;
    widget.geminiApiKeyController.text = ref.read(geminiApiKeyProvider);
    await _refreshPersonalKeyState();
  }

  /// Εξηγεί ΠΟΙΟ κλειδί ισχύει τώρα — χωρίς αυτό, ο χρήστης δεν μπορεί να
  /// ξεχωρίσει το κοινό της ομάδας από το δικό του.
  Widget _buildKeyScopeNotice(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            _hasPersonalKey ? Icons.person_outline : Icons.groups_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _hasPersonalKey
                  ? 'Χρησιμοποιείται το δικό σας κλειδί — σας ακολουθεί σε '
                        'όποιον υπολογιστή καθίσετε.'
                  : 'Χρησιμοποιείται το κοινό κλειδί της ομάδας. Ό,τι '
                        'πληκτρολογήσετε εδώ γίνεται δικό σας.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_hasPersonalKey)
            TextButton(
              key: const Key('gemini_use_shared_key_button'),
              onPressed: _useSharedKey,
              child: const Text('Χρήση του κοινού'),
            ),
        ],
      ),
    );
  }

  Widget _buildKeyAndEndpointCard(BuildContext context) {
    return LansweeperSettingsCard(
      icon: Icons.key_rounded,
      title: 'Κλειδί & διεύθυνση',
      children: [
        Text(
          'Απαιτείται για την αυτόματη πρόταση τίτλου/περιγραφής ticket.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onAiHelpLink,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Δωρεάν κλειδί από: aistudio.google.com'),
          ),
        ),
        TextFormField(
          controller: widget.geminiApiKeyController,
          onChanged: (_) => widget.onSettingsChanged(),
          obscureText: _obscureGeminiKey,
          decoration: InputDecoration(
            labelText: 'Gemini API key',
            hintText: 'AIza…',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              tooltip: _obscureGeminiKey
                  ? 'Εμφάνιση κλειδιού'
                  : 'Απόκρυψη κλειδιού',
              onPressed: () {
                setState(() => _obscureGeminiKey = !_obscureGeminiKey);
              },
              icon: Icon(
                _obscureGeminiKey
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
            ),
          ),
        ),
        _buildKeyScopeNotice(context),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.geminiEndpointController,
          onChanged: (_) => widget.onSettingsChanged(),
          decoration: const InputDecoration(
            labelText: 'Διεύθυνση κλήσης API του Gemini',
            hintText:
                '…/models/{προτεύων μοντέλο}:generateContent?key={κλειδί API}',
            helperText:
                'Χρησιμοποιήστε {προτεύων μοντέλο} και {κλειδί API} ως placeholders.',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildBehaviorCard() {
    final geminiFallbackEnabled = ref.watch(geminiFallbackEnabledProvider);

    return LansweeperSettingsCard(
      icon: Icons.settings_rounded,
      title: 'Συμπεριφορά',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Υποβάθμιση σε εφεδρικό μοντέλο'),
          subtitle: const Text(
            'Αν το κύριο μοντέλο είναι υπερφορτωμένο (503), δοκιμάζεται '
            'αυτόματα το εφεδρικό μοντέλο.',
          ),
          value: geminiFallbackEnabled,
          onChanged: (v) {
            unawaited(
              ref.read(geminiFallbackEnabledProvider.notifier).setEnabled(v),
            );
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Αυτόματη επανυποβολή μέχρι την επιτυχία'),
          subtitle: const Text(
            'Μετά από αναμονή ποσόστωσης, επαναλαμβάνεται αυτόματα '
            'η πρόταση ΤΝ όσο το παράθυρο παραμένει ανοιχτό.',
          ),
          value: ref.watch(geminiAutoResubmitEnabledProvider),
          onChanged: (v) {
            unawaited(
              ref
                  .read(geminiAutoResubmitEnabledProvider.notifier)
                  .setEnabled(v),
            );
          },
        ),
      ],
    );
  }

  Widget _buildModelsCard() {
    final geminiFallbackEnabled = ref.watch(geminiFallbackEnabledProvider);

    return LansweeperSettingsCard(
      icon: Icons.psychology_rounded,
      title: 'Μοντέλα',
      children: [
        GeminiModelsSection(
          primaryModelController: widget.geminiPrimaryModelController,
          fallbackModelController: widget.geminiFallbackModelController,
          apiKeyController: widget.geminiApiKeyController,
          fallbackEnabled: geminiFallbackEnabled,
          endpointTemplate: widget.geminiEndpointController.text.trim().isEmpty
              ? kDefaultGeminiEndpoint
              : widget.geminiEndpointController.text,
          onChanged: widget.onSettingsChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildKeyAndEndpointCard(context),
              const SizedBox(height: 14),
              _buildBehaviorCard(),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: _buildModelsCard()),
      ],
    );
  }
}
