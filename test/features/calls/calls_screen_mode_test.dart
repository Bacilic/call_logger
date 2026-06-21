import 'package:call_logger/features/calls/layout/calls_field_groups_provider.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expanded latch keeps expanded after fields cleared', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(callsFieldConfirmationsProvider.notifier).confirmPhone();
    expect(container.read(callsScreenIsExpandedProvider), isTrue);

    container.read(callHeaderProvider.notifier).clearAll();
    expect(container.read(callsFieldGroupsProvider).anyGroupActive, isFalse);
    expect(container.read(callsScreenIsExpandedProvider), isTrue);

    container.read(callsScreenExpandedLatchProvider.notifier).release();
    expect(container.read(callsScreenIsExpandedProvider), isFalse);
  });

  test('Εκκαθάριση flow releases latch via resetAll + release', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(callsFieldConfirmationsProvider.notifier).confirmPhone();
    container.read(callsFieldConfirmationsProvider.notifier).resetAll();
    container.read(callsScreenExpandedLatchProvider.notifier).release();
    expect(container.read(callsScreenIsExpandedProvider), isFalse);
  });
}
