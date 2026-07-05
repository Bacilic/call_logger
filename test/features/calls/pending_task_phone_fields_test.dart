import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _pendingTaskFieldsProbe = Provider((ref) => callsFormPendingTaskFields(ref));

void main() {
  group('callsFormPendingTaskFields — phoneId vs phoneText', () {
    test('phoneText διατηρεί τον αριθμό, phoneId παραμένει null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(callHeaderProvider.notifier).updatePhone('2262');

      final fields = container.read(_pendingTaskFieldsProbe);

      // phones.id δεν επιτρέπεται ποτέ να προκύπτει από τα ψηφία του αριθμού.
      expect(fields.phoneId, isNull);
      expect(fields.phoneText, '2262');
    });
  });
}
