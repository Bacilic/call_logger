import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';
import 'update_check_result.dart';
import 'update_dialogs.dart';
import 'update_providers.dart';

/// Μία εμφάνιση popup ενημέρωσης ανά συνεδρία εφαρμογής.
bool _updateStartupPromptShownThisSession = false;

/// Το πρώτο αποτέλεσμα ελέγχου της συνεδρίας — αυτό της εκκίνησης. Ό,τι έρθει
/// μετά (ωριαίος έλεγχος, «Έλεγχος ξανά») βρίσκει τον χρήστη στη μέση της
/// δουλειάς, όπου η ερώτηση επανεκκίνησης μένει.
UpdateCheckResult? _startupCheckResult;

@visibleForTesting
void resetUpdateStartupPromptSessionForTests() {
  _updateStartupPromptShownThisSession = false;
  _startupCheckResult = null;
}

/// Ακούει τον [updateCheckProvider] και εμφανίζει το μήνυμα ενημέρωσης στην εκκίνηση.
class UpdateStartupPromptListener extends ConsumerStatefulWidget {
  const UpdateStartupPromptListener({super.key, this.getShowUpdateOnStartup});

  /// Έγχυση για τεστ· προεπιλογή: [SettingsService.getShowUpdateOnStartup].
  final Future<bool> Function()? getShowUpdateOnStartup;

  @override
  ConsumerState<UpdateStartupPromptListener> createState() =>
      _UpdateStartupPromptListenerState();
}

class _UpdateStartupPromptListenerState
    extends ConsumerState<UpdateStartupPromptListener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final result = ref.read(updateCheckProvider).asData?.value;
      if (result != null) {
        unawaited(_maybeShow(result));
      }
    });
  }

  Future<void> _maybeShow(UpdateCheckResult result) async {
    _startupCheckResult ??= result;
    final atStartup = identical(result, _startupCheckResult);
    if (_updateStartupPromptShownThisSession) return;
    if (!result.updateAvailable || result.manifest == null) return;

    final show =
        await (widget.getShowUpdateOnStartup ??
            () => SettingsService().catalogs.getShowUpdateOnStartup())();
    if (!show || !mounted) return;
    if (_updateStartupPromptShownThisSession) return;

    _updateStartupPromptShownThisSession = true;
    await showUpdateAvailableDialog(context, result, atStartup: atStartup);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<UpdateCheckResult>>(updateCheckProvider, (
      previous,
      next,
    ) {
      final result = next.asData?.value;
      if (result != null) {
        unawaited(_maybeShow(result));
      }
    });
    return const SizedBox.shrink();
  }
}
