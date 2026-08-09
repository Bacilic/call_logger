import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';
import '../models/equipment_column.dart';
import '../providers/equipment_directory_provider.dart';
import '../screens/widgets/equipment_form_dialog.dart';

/// Άνοιγμα της φόρμας εξοπλισμού από οθόνη που δεν είναι ο κατάλογος
/// εξοπλισμού (ιστορικό κλήσης, εκκρεμότητες, κάρτα υπαλλήλου).
///
/// Γράφεται μία φορά ώστε η αναζήτηση της γραμμής, το μήνυμα όταν λείπει
/// και η φόρτωση του καταλόγου να συμπεριφέρονται παντού ίδια.
class EquipmentFormLauncher {
  const EquipmentFormLauncher._();

  /// Άνοιγμα με βάση το `id` του εξοπλισμού.
  static Future<bool> openById(
    BuildContext context,
    WidgetRef ref,
    int equipmentId,
  ) {
    return _open(
      context,
      ref,
      matches: (row) => row.$1.id == equipmentId,
      missingMessage: 'Ο εξοπλισμός δεν βρέθηκε στον κατάλογο.',
    );
  }

  /// Άνοιγμα με βάση τον κωδικό εξοπλισμού (όπως γράφεται στην κλήση).
  static Future<bool> openByCode(
    BuildContext context,
    WidgetRef ref,
    String equipmentCode,
  ) {
    final code = equipmentCode.trim();
    if (code.isEmpty) return Future.value(false);
    final codeNorm = code.toLowerCase();
    return _open(
      context,
      ref,
      matches: (row) => (row.$1.code ?? '').trim().toLowerCase() == codeNorm,
      missingMessage: 'Δεν βρέθηκε εξοπλισμός με κωδικό $code στον κατάλογο.',
    );
  }

  static Future<bool> _open(
    BuildContext context,
    WidgetRef ref, {
    required bool Function(EquipmentRow row) matches,
    required String missingMessage,
  }) async {
    final notifier = ref.read(equipmentDirectoryProvider.notifier);
    await notifier.load();
    if (!context.mounted) return false;

    EquipmentModel? equipment;
    UserModel? owner;
    for (final row in ref.read(equipmentDirectoryProvider).allItems) {
      if (matches(row)) {
        equipment = row.$1;
        owner = row.$2;
        break;
      }
    }
    if (equipment == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(missingMessage)));
      return false;
    }

    var saved = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => EquipmentFormDialog(
        initialEquipment: equipment,
        initialOwner: owner,
        notifier: notifier,
        onSaved: () => saved = true,
      ),
    );
    return saved;
  }
}
