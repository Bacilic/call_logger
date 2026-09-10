import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../layout/call_form_clear.dart';
import '../../provider/call_entry_provider.dart';
import 'smart_entity_selector_widget.dart';

/// Η σύνδεση των κοινών πεδίων (Τηλέφωνο, Καλών, Τμήμα, Εξοπλισμός) με τη
/// φόρμα **κλήσης** — χρονόμετρο και εκκαθάριση.
///
/// Γράφεται μία φορά επειδή τη χρειάζονται δύο οθόνες: η κύρια φόρμα και η
/// γρήγορη καταγραφή. Ήταν αντιγραμμένη αυτούσια και στις δύο· η επόμενη
/// αλλαγή θα έμενε στη μία και οι δύο οθόνες θα μετρούσαν διαφορετικά.
///
/// Ο διάλογος εκκρεμότητας δανείζεται τα ίδια πεδία αλλά **δεν** περνά από εδώ:
/// δεν έχει χρονόμετρο ούτε σημειώσεις, και η κατάσταση των Κλήσεων δεν είναι
/// δική του να την πειράξει.
SmartEntityCallEntryHooks callEntrySelectorHooks(WidgetRef ref) {
  return SmartEntityCallEntryHooks(
    syncTimerFromPhoneText: (raw) {
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      final notifier = ref.read(callEntryProvider.notifier);
      if (digits.isNotEmpty) {
        notifier.startTimerOnce();
      } else {
        notifier.resetTimerToStandby();
      }
    },
    startTimerOnceIfNotRunningWhenAutofill: () {
      final notifier = ref.read(callEntryProvider.notifier);
      if (!notifier.isTimerRunning) {
        notifier.startTimerOnce();
      }
    },
    resetTimerToStandby: () =>
        ref.read(callEntryProvider.notifier).resetTimerToStandby(),
    clearHostFormState: () => clearCallFormKeepingScreenExpanded(ref),
  );
}
