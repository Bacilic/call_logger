import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/main_nav_request_provider.dart';
import '../../../../core/widgets/main_nav_destination.dart';
import '../../../directory/providers/equipment_directory_provider.dart';
import '../../../directory/screens/widgets/equipment_form_dialog.dart';
import '../../../history/providers/history_provider.dart';
import '../../models/call_model.dart';
import '../../models/equipment_model.dart';
import '../../models/user_model.dart';
import '../../provider/calls_dashboard_providers.dart';

DateTime? _equipmentRecentParseSqlDateOnly(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

/// Πρώτη στήλη: `ηη-μμ-εε ώρα` (αν υπάρχει `date`), αλλιώς μόνο ώρα / `--:--`.
String _equipmentRecentDateTimeLabel(CallModel c) {
  final t = (c.time ?? '').trim();
  final timePart = t.isEmpty ? '--:--' : t;
  final d = _equipmentRecentParseSqlDateOnly(c.date);
  if (d == null) return timePart;
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yy = (d.year % 100).toString().padLeft(2, '0');
  return '$dd-$mm-$yy $timePart';
}

/// Κατηγορία· αν κενή → σημειώσεις (`issue`)· αν και αυτό κενό → παύλα.
String _equipmentRecentCategoryOrNotesLine(CallModel c) {
  final category = (c.category ?? '').trim();
  if (category.isNotEmpty) return category;
  final notes = (c.issue ?? '').trim();
  if (notes.isNotEmpty) return notes;
  return '—';
}

String _equipmentRecentCardClipboardText(
  String equipmentCode,
  List<CallModel> calls,
) {
  final buf = StringBuffer()
    ..writeln('Ιστορικό Εξοπλισμού: $equipmentCode');
  for (final c in calls) {
    buf.writeln(
      '${_equipmentRecentDateTimeLabel(c)}\t${_equipmentRecentCategoryOrNotesLine(c)}',
    );
  }
  return buf.toString().trimRight();
}

enum _EquipmentRecentTitleMenu { copyAll, openHistory, openEquipmentEdit }

Future<void> _openEquipmentCatalogForm(
  BuildContext context,
  WidgetRef ref,
  String equipmentCode,
) async {
  final code = equipmentCode.trim();
  if (code.isEmpty) return;
  final notifier = ref.read(equipmentDirectoryProvider.notifier);
  await notifier.load();
  if (!context.mounted) return;
  final rows = ref.read(equipmentDirectoryProvider).allItems;
  final codeNorm = code.toLowerCase();
  EquipmentModel? equipment;
  UserModel? owner;
  for (final row in rows) {
    final c = (row.$1.code ?? '').trim().toLowerCase();
    if (c == codeNorm) {
      equipment = row.$1;
      owner = row.$2;
      break;
    }
  }
  if (equipment == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Δεν βρέθηκε εξοπλισμός με κωδικό $code στον κατάλογο.'),
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => EquipmentFormDialog(
      initialEquipment: equipment,
      initialOwner: owner,
      notifier: notifier,
      ref: ref,
    ),
  );
}

class EquipmentRecentCallsPanel extends ConsumerWidget {
  const EquipmentRecentCallsPanel({super.key, required this.equipmentCode});

  final String equipmentCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = equipmentCode.trim();
    if (code.isEmpty) return const SizedBox.shrink();
    final asyncCalls = ref.watch(recentCallsByEquipmentProvider(code));
    return asyncCalls.when(
      data: (calls) {
        if (calls.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Ιστορικό Εξοπλισμού',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    PopupMenuButton<_EquipmentRecentTitleMenu>(
                      tooltip: 'Ενέργειες',
                      icon: const Icon(Icons.more_vert, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 36,
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case _EquipmentRecentTitleMenu.copyAll:
                            final text = _equipmentRecentCardClipboardText(
                              code,
                              calls,
                            );
                            Clipboard.setData(ClipboardData(text: text));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Το κείμενο αντιγράφηκε στο πρόχειρο.',
                                  ),
                                ),
                              );
                            }
                          case _EquipmentRecentTitleMenu.openHistory:
                            ref
                                .read(historyFilterProvider.notifier)
                                .update(
                                  (s) => s.copyWith(keyword: code),
                                );
                            ref
                                .read(mainNavRequestProvider.notifier)
                                .request(
                                  const MainNavRequest(
                                    destination: MainNavDestination.history,
                                  ),
                                );
                          case _EquipmentRecentTitleMenu.openEquipmentEdit:
                            _openEquipmentCatalogForm(context, ref, code);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: _EquipmentRecentTitleMenu.copyAll,
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.copy),
                            title: Text('Αντιγραφή κειμένου'),
                            subtitle: Text(
                              'Αντιγράφει όλες τις γραμμές για επικόλληση',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const PopupMenuItem(
                          value: _EquipmentRecentTitleMenu.openHistory,
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.history),
                            title: Text('Μετάβαση στο ιστορικό'),
                            subtitle: Text(
                              'Φίλτρο αναζήτησης με τον κωδικό εξοπλισμού',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const PopupMenuItem(
                          value: _EquipmentRecentTitleMenu.openEquipmentEdit,
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Άνοιγμα καρτέλας εξοπλισμού'),
                            subtitle: Text(
                              'Άμεσο άνοιγμα φόρμας επεξεργασίας εξοπλισμού',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final c in calls)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 132,
                          child: Text(
                            _equipmentRecentDateTimeLabel(c),
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _equipmentRecentCategoryOrNotesLine(c),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
