import 'smart_entity_selector_provider.dart';

export 'smart_entity_selector_provider.dart'
    show
        SmartEntitySelectorNotifier,
        SmartEntitySelectorState,
        callSmartEntityProvider,
        taskSmartEntityProvider;

/// Σταθερό εξωτερικό API: οι καταναλωτές συνεχίζουν να χρησιμοποιούν αυτούς τους τύπους.
typedef CallHeaderState = SmartEntitySelectorState;
typedef CallHeaderNotifier = SmartEntitySelectorNotifier;

/// Ίδιο instance με [callSmartEntityProvider] — μηδενικό breakage για υπάρχοντα `ref.watch/read`.
final callHeaderProvider = callSmartEntityProvider;
