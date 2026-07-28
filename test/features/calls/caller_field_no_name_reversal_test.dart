import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/*
 * Αρχή «ελεύθερης καταγραφής κλήσης»: το πεδίο «Καλούντας» δεν ξαναγράφει ποτέ
 * ό,τι πληκτρολόγησε ο χρήστης χωρίς ρητή επιλογή του από τη λίστα προτάσεων.
 *
 * Πραγματικό σενάριο: ο χρήστης γράφει «Δρόσος Βασίλης» ενώ στη βάση υπάρχει
 * «Βασίλης Δρόσος (Πληροφορική)» — το κείμενο μετατρεπόταν μόνο του.
 *
 *   flutter test test/features/calls/caller_field_no_name_reversal_test.dart
 */

UserModel _u({
  required int id,
  required String first,
  required String last,
  int? departmentId,
}) {
  return UserModel(
    id: id,
    firstName: first,
    lastName: last,
    departmentId: departmentId,
  );
}

Future<ProviderContainer> _containerWith(List<UserModel> users) async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: users,
    equipment: const [],
    departmentRows: [DepartmentModel(id: 4, name: 'Πληροφορική')],
  );
  final container = ProviderContainer(
    overrides: [
      lookupServiceProvider.overrideWith(
        (ref) async => LookupLoadResult(service: svc),
      ),
    ],
  );
  await container.read(lookupServiceProvider.future);
  return container;
}

void main() {
  final drosos = _u(id: 7, first: 'Βασίλης', last: 'Δρόσος', departmentId: 4);

  group('πεδίο καλούντα — καμία σιωπηλή αναστροφή', () {
    test('«Δρόσος Βασίλης» δεν κουμπώνει τον «Βασίλης Δρόσος»', () async {
      final container = await _containerWith([drosos]);
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      notifier.updateCallerDisplayText('Δρόσος Βασίλης');
      notifier.performCallerLookup('Δρόσος Βασίλης');

      final state = container.read(callSmartEntityProvider);
      expect(
        state.selectedCaller,
        isNull,
        reason: 'Η ανάστροφη γραφή δεν είναι ρητή επιλογή του χρήστη',
      );
      expect(
        state.callerDisplayText,
        'Δρόσος Βασίλης',
        reason: 'Το κείμενο του χρήστη μένει άθικτο',
      );
      expect(
        state.callerCandidates.map((u) => u.id),
        contains(7),
        reason: 'Ο υπάρχων παραμένει ορατός ως πρόταση στη λίστα',
      );
    });

    test('«Βασίλης Δρόσος» στη σωστή σειρά κουμπώνει κανονικά', () async {
      final container = await _containerWith([drosos]);
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      notifier.updateCallerDisplayText('Βασίλης Δρόσος');
      notifier.performCallerLookup('Βασίλης Δρόσος');

      final state = container.read(callSmartEntityProvider);
      expect(state.selectedCaller?.id, 7);
      expect(state.callerDisplayText, 'Βασίλης Δρόσος');
    });

    test('σκέτο μικρό όνομα «Βασίλης» μένει ως έχει', () async {
      final container = await _containerWith([drosos]);
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      notifier.updateCallerDisplayText('Βασίλης');
      notifier.performCallerLookup('Βασίλης');

      final state = container.read(callSmartEntityProvider);
      expect(
        state.selectedCaller,
        isNull,
        reason: 'Οι νέοι συνάδελφοι καταχωρούν μόνο μικρά ονόματα',
      );
      expect(state.callerDisplayText, 'Βασίλης');
    });

    test('χωρίς τόνους η σωστή σειρά εξακολουθεί να κουμπώνει', () async {
      final container = await _containerWith([drosos]);
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      notifier.updateCallerDisplayText('Βασιλης Δροσος');
      notifier.performCallerLookup('Βασιλης Δροσος');

      expect(container.read(callSmartEntityProvider).selectedCaller?.id, 7);
    });
  });
}
