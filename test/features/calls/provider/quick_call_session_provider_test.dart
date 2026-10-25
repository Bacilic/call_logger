// Η συνεδρία της γρήγορης καταγραφής: απομόνωση από την κύρια φόρμα και
// κύκλος ζωής των providers της.
//
//   flutter test test/features/calls/provider/quick_call_session_provider_test.dart

import 'package:call_logger/features/calls/layout/calls_field_groups_provider.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/quick_call_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer root;
  late QuickCallSessionNotifier session;

  setUp(() {
    root = ProviderContainer();
    session = root.read(quickCallSessionProvider.notifier);
  });

  tearDown(() => root.dispose());

  test('η γρήγορη καταγραφή δεν αγγίζει την κατάσταση της κύριας φόρμας', () {
    final quick = session.open();

    quick.read(callEntryProvider.notifier).setCategory('Δίκτυο');
    quick.read(callsScreenExpandedLatchProvider.notifier).engage();

    expect(root.read(callEntryProvider).category, isEmpty);
    expect(root.read(callsScreenExpandedLatchProvider), isFalse);
  });

  test(
    'η ελαχιστοποίηση κρατά ό,τι γράφτηκε και η επαναφορά το ξαναβρίσκει',
    () {
      session.open().read(callEntryProvider.notifier).setCategory('Δίκτυο');
      session.minimize();

      expect(root.read(quickCallSessionProvider), QuickCallPhase.minimized);
      expect(session.hasContent, isTrue);
      expect(session.open().read(callEntryProvider).category, 'Δίκτυο');
    },
  );

  test('νέα καταγραφή μετά το τέλος ξεκινά άδεια', () {
    session.open().read(callEntryProvider.notifier).setCategory('Δίκτυο');
    session.end();

    expect(root.read(quickCallSessionProvider), QuickCallPhase.closed);
    expect(session.open().read(callEntryProvider).category, isEmpty);
  });

  test(
    'τέλος ενώ ο διάλογος σβήνει ακόμη: τα providers ζουν ώσπου να φύγει',
    () {
      final quick = session.open();
      session.attachView();
      session.end();

      // Ο διάλογος διαβάζει ακόμη τα providers του όσο σβήνει.
      expect(() => quick.read(callEntryProvider), returnsNormally);

      session.detachView();
      expect(() => quick.read(callEntryProvider), throwsA(anything));
    },
  );

  test('ελαχιστοποίηση χωρίς καταγραφή δεν κάνει τίποτα', () {
    session.minimize();
    expect(root.read(quickCallSessionProvider), QuickCallPhase.closed);
  });
}
