// Τα κείμενα του παραθύρου «Αναφορές Εκκρεμοτήτων».
//
//   flutter test test/features/tasks/utils/task_analytics_texts_test.dart

import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/models/task_analytics_summary.dart';
import 'package:call_logger/features/tasks/utils/task_analytics_texts.dart';
import 'package:flutter_test/flutter_test.dart';

String _insight(int delta) =>
    buildTaskAnalyticsInsight(backlogLastDelta: delta, overdueRateActive: 12.5);

void main() {
  test('χωρίς μεταβολή: «έμεινε σταθερό», όχι «αυξήθηκε κατά 0»', () {
    expect(
      _insight(0),
      startsWith(
        'Το υπόλοιπο εκκρεμοτήτων έμεινε σταθερό στην τελευταία ημέρα του εύρους.',
      ),
    );
  });

  test('αύξηση και μείωση λέγονται με τον αριθμό τους', () {
    expect(_insight(3), contains('αυξήθηκε κατά 3'));
    expect(_insight(-2), contains('μειώθηκε κατά 2'));
  });

  test('η κυρίαρχη προέλευση με την ελληνική ετικέτα και το ποσοστό', () {
    final text = buildTaskAnalyticsInsight(
      backlogLastDelta: 1,
      overdueRateActive: 0,
      dominantOrigin: const TaskAnalyticsOriginSlice(
        origin: 'call_linked',
        count: 7,
        percent: 70,
      ),
    );
    expect(text, endsWith('κυρίαρχη προέλευση: Από κλήση (70.0%).'));
  });

  test('κάθε προέλευση έχει ελληνική ετικέτα — η μία πηγή τους', () {
    expect(taskAnalyticsOriginLabel(Task.originCallLinked), 'Από κλήση');
    expect(taskAnalyticsOriginLabel(Task.originManualFab), 'Χειροκίνητη');
    expect(taskAnalyticsOriginLabel(Task.originQuickAdd), 'Γρήγορη προσθήκη');
    expect(taskAnalyticsOriginLabel(Task.originLegacy), 'Παλαιές εγγραφές');
    expect(taskAnalyticsOriginLabel('κάτι άλλο'), 'Άγνωστη προέλευση');
  });

  test('διάρκεια: ώρες και λεπτά, ή μόνο λεπτά', () {
    expect(formatTaskAnalyticsDuration(8100), '2 ώρ. 15 λ.');
    expect(formatTaskAnalyticsDuration(2400), '40 λ.');
    expect(formatTaskAnalyticsDuration(double.nan), '0 λ.');
  });
}
