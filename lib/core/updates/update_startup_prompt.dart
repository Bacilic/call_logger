import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';
import 'update_check_result.dart';
import 'update_dialogs.dart';
import 'update_providers.dart';

/// Μία εμφάνιση popup ενημέρωσης ανά συνεδρία εφαρμογής.
bool _updateStartupPromptShownThisSession = false;

@visibleForTesting
void resetUpdateStartupPromptSessionForTests() {
  _updateStartupPromptShownThisSession = false;
}

/// Ακούει τον [updateCheckProvider] και εμφανίζει το μήνυμα ενημέρωσης στην εκκίνηση.
class UpdateStartupPromptListener extends ConsumerStatefulWidget {
  const UpdateStartupPromptListener({
    super.key,
    this.getShowUpdateOnStartup,
  });

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
    if (_updateStartupPromptShownThisSession) return;
    if (!result.updateAvailable || result.manifest == null) return;

    final show = await (widget.getShowUpdateOnStartup ??
        () => SettingsService().getShowUpdateOnStartup())();
    if (!show || !mounted) return;
    if (_updateStartupPromptShownThisSession) return;

    _updateStartupPromptShownThisSession = true;
    await showUpdateAvailableDialog(context, ref, result);
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
