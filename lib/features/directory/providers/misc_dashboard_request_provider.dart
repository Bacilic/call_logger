import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Όταν αυξάνεται, η καρτέλα «Διάφορα» επιστρέφει στις κάρτες της — από
/// όποια υπο-οθόνη κι αν βρίσκεται, περνώντας από τους φρουρούς εξόδου.
///
/// Το ζητά το νέο πάτημα της ήδη ενεργής καρτέλας «Διάφορα», όπως οι άλλες
/// τρεις καρτέλες του Καταλόγου που φέρνουν πάντα στη δική τους οθόνη.
class MiscDashboardRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() {
    state = state + 1;
  }
}

final miscDashboardRequestProvider =
    NotifierProvider<MiscDashboardRequestNotifier, int>(
      MiscDashboardRequestNotifier.new,
    );
