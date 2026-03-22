// Unit tests: CallHeaderNotifier — επιλογή τηλεφώνου από υποψήφιους vs updatePhone (regression).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/calls/call_header_phone_candidates_test.dart
// Ομάδα:
//   flutter test test/features/calls/call_header_phone_candidates_test.dart --plain-name "CallHeader phone candidates"

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLookupService extends LookupService {
  _FakeLookupService() : super.forTest();

  @override
  List<String> searchPhonesByPrefix(String prefix) => const [];

  @override
  List<UserModel> searchUsersByQuery(String query) => const [];

  @override
  List<UserModel> findUsersByPhone(String phone) => const [];

  @override
  List<EquipmentModel> findEquipmentsForUser(int userId) => const [];

  @override
  List<EquipmentModel> findEquipmentsByCode(String query) => const [];
}

class _TestCallHeaderNotifier extends CallHeaderNotifier {
  _TestCallHeaderNotifier(this.initialState);

  final CallHeaderState initialState;
  bool selectPhoneFromCandidatesCalled = false;
  String? selectedFromCandidates;

  @override
  CallHeaderState build() => initialState;

  @override
  void selectPhoneFromCandidates(String value) {
    selectPhoneFromCandidatesCalled = true;
    selectedFromCandidates = value;
    super.selectPhoneFromCandidates(value);
  }
}

void main() {
  group('CallHeader phone candidates', () {
    // Επιλογή αριθμού από λίστα: διατηρείται ο καλών, selectedPhone, καθαρίζουν candidates.
    //   flutter test test/features/calls/call_header_phone_candidates_test.dart --plain-name "selectPhoneFromCandidates κρατά caller context και ορίζει selectedPhone"
    test(
      'selectPhoneFromCandidates κρατά caller context και ορίζει selectedPhone',
      () {
        final notifier = _TestCallHeaderNotifier(
          CallHeaderState(
            selectedCaller: UserModel(
              id: 10,
              firstName: 'Σταματίνα',
              lastName: 'Γεωργάκη',
              phones: PhoneListParser.splitPhones('2975 2997 2551 2564'),
            ),
            phoneCandidates: const ['2551', '2564', '2975', '2997'],
            callerDisplayText: 'Σταματίνα Γεωργάκη',
            equipmentIsManual: true,
            equipmentText: 'dummy',
          ),
        );
        final container = ProviderContainer(
          overrides: [
            callHeaderProvider.overrideWith(() => notifier),
            lookupServiceProvider.overrideWith(
              (ref) async =>
                  LookupLoadResult(service: _FakeLookupService()),
            ),
          ],
        );
        addTearDown(container.dispose);

        final n =
            container.read(callHeaderProvider.notifier)
                as _TestCallHeaderNotifier;
        n.selectPhoneFromCandidates('2551');
        final state = container.read(callHeaderProvider);
        expect(state.selectedPhone, '2551');
        expect(state.selectedCaller?.id, 10);
        expect(state.phoneCandidates, isEmpty);
        expect(state.phoneIsManual, isFalse);
        expect(n.selectPhoneFromCandidatesCalled, isTrue);
        expect(n.selectedFromCandidates, '2551');
      },
    );

    // Χειροκίνητη ενημέρωση τηλεφώνου: καθαρίζει selectedCaller (διαφορετικό path από selectPhoneFromCandidates).
    //   flutter test test/features/calls/call_header_phone_candidates_test.dart --plain-name "updatePhone καθαρίζει caller context (αιτία του regression όταν καλείται λάθος path)"
    test(
      'updatePhone καθαρίζει caller context (αιτία του regression όταν καλείται λάθος path)',
      () {
        final notifier = _TestCallHeaderNotifier(
          CallHeaderState(
            selectedCaller: UserModel(
              id: 10,
              firstName: 'Σταματίνα',
              lastName: 'Γεωργάκη',
            ),
            phoneCandidates: const ['2551'],
            callerDisplayText: 'Σταματίνα Γεωργάκη',
          ),
        );
        final container = ProviderContainer(
          overrides: [
            callHeaderProvider.overrideWith(() => notifier),
            lookupServiceProvider.overrideWith(
              (ref) async =>
                  LookupLoadResult(service: _FakeLookupService()),
            ),
          ],
        );
        addTearDown(container.dispose);

        final n = container.read(callHeaderProvider.notifier);
        n.updatePhone('2551');
        final state = container.read(callHeaderProvider);
        expect(state.selectedCaller, isNull);
      },
    );
  });
}
