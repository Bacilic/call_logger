import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calls/models/user_model.dart';

/// Άνοιγμα [UserFormDialog] από άλλη οθόνη (π.χ. κάρτα χρήστη στις Κλήσεις).
/// Καταναλώνεται από [UsersTab].
class UserFormEditIntentNotifier extends Notifier<UserModel?> {
  @override
  UserModel? build() => null;

  void requestEdit(UserModel user) {
    state = user;
  }

  void clear() {
    state = null;
  }
}

final userFormEditIntentProvider =
    NotifierProvider<UserFormEditIntentNotifier, UserModel?>(
  UserFormEditIntentNotifier.new,
);
