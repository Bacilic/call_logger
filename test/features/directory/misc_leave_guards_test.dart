import 'package:call_logger/features/directory/screens/widgets/misc_leave_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('φρουροί εξόδου των «Διαφόρων»', () {
    test('χωρίς φρουρούς η έξοδος επιτρέπεται', () async {
      expect(await MiscLeaveGuards().canLeave(), isTrue);
    });

    test('η έξοδος περιμένει να τελειώσει κάθε φρουρός', () async {
      final guards = MiscLeaveGuards();
      var settled = false;
      guards.add(() async {
        await Future<void>.delayed(Duration.zero);
        settled = true;
        return true;
      });
      expect(await guards.canLeave(), isTrue);
      expect(settled, isTrue);
    });

    test('ένας φρουρός που αρνείται σταματά την έξοδο', () async {
      final guards = MiscLeaveGuards()
        ..add(() async => true)
        ..add(() async => false);
      expect(await guards.canLeave(), isFalse);
    });

    test('φρουρός που αφαιρέθηκε δεν ρωτιέται', () async {
      final guards = MiscLeaveGuards();
      Future<bool> refuse() async => false;
      guards
        ..add(refuse)
        ..remove(refuse);
      expect(await guards.canLeave(), isTrue);
    });
  });
}
