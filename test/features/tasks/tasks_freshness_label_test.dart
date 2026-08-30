// Η ένδειξη «πόσο παλιά είναι αυτά που βλέπω».
//
//   flutter test test/features/tasks/tasks_freshness_label_test.dart

import 'package:call_logger/features/tasks/services/tasks_freshness_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 22, 18, 5);

  test('χωρίς ανάγνωση: δεν εφευρίσκεται ώρα', () {
    expect(
      tasksFreshnessLabel(lastRead: null, now: now),
      'Δεν έχουν διαβαστεί ακόμη από τη βάση',
    );
  });

  test('μόλις τώρα', () {
    expect(
      tasksFreshnessLabel(
        lastRead: now.subtract(const Duration(seconds: 10)),
        now: now,
      ),
      'Ενημερώθηκαν μόλις τώρα',
    );
  });

  test('ένα λεπτό: ενικός', () {
    expect(
      tasksFreshnessLabel(
        lastRead: now.subtract(const Duration(minutes: 1, seconds: 5)),
        now: now,
      ),
      'Ενημερώθηκαν πριν από ένα λεπτό',
    );
  });

  test('λεπτά: πληθυντικός', () {
    expect(
      tasksFreshnessLabel(
        lastRead: now.subtract(const Duration(minutes: 7)),
        now: now,
      ),
      'Ενημερώθηκαν πριν από 7 λεπτά',
    );
  });

  test('πάνω από ώρα: γράφεται η ώρα', () {
    expect(
      tasksFreshnessLabel(lastRead: DateTime(2026, 8, 22, 16, 31), now: now),
      'Στοιχεία της 16:31',
    );
  });

  test('ρολόι που πήγε πίσω δεν δίνει αρνητικά λεπτά', () {
    expect(
      tasksFreshnessLabel(
        lastRead: now.add(const Duration(minutes: 3)),
        now: now,
      ),
      'Ενημερώθηκαν μόλις τώρα',
    );
  });
}
