import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/main_nav_request_provider.dart';
import '../../../../core/widgets/main_nav_destination.dart';
import '../../../history/providers/history_provider.dart';
import '../../models/call_model.dart';
import '../../models/user_model.dart';
import '../../provider/calls_dashboard_providers.dart';
import 'text_layout_utils.dart';

/// Λέξη-κλειδί για αναζήτηση ιστορικού: όνομα, αλλιώς πρώτο μη κενό τηλέφωνο.
String _recentCallsHistorySearchKeyword(UserModel user) {
  final n = user.name?.trim() ?? '';
  if (n.isNotEmpty) return n;
  for (final p in user.phones) {
    final t = p.trim();
    if (t.isNotEmpty) return t;
  }
  return '';
}

String _recentCallsListClipboardText(UserModel user, List<CallModel> calls) {
  final name = (user.name ?? '').trim().isEmpty ? '—' : user.name!.trim();
  final buf = StringBuffer()..writeln('Πρόσφατο ιστορικό Υπαλλήλου: $name');
  for (final c in calls) {
    final line = (c.issue ?? '').trim();
    buf.writeln(
      '${c.date ?? ''} ${c.time ?? ''}\t${line.isEmpty ? '—' : line}',
    );
  }
  return buf.toString().trimRight();
}

enum _RecentCallsTitleMenu { copyAll, openHistory }

/// Σε φαρδύ παράθυρο η κάρτα σταματά εδώ· σε στενό «κόβεται» στο διαθέσιμο πλάτος.
const double _kRecentCallsCardMaxWidth = 560;

/// Εσωτερικό περιθώριο κάρτας (12px αριστερά + 12px δεξιά).
const double _kRecentCallsCardHorizontalPadding = 24;

/// Κενό ανάμεσα στη στήλη ημερομηνίας και στη στήλη σημειώσεων.
const double _kRecentCallsRowGap = 12;

/// Ελάχιστο ωφέλιμο πλάτος ώστε τίτλος + μενού ⋮ να μη συνθλίβονται.
const double _kRecentCallsMinContentWidth = 280;

/// ΚΑΝΟΝΑΣ: «έξυπνο» πλάτος κάρτας ιστορικού — καθορίζεται από την πιο
/// επιμήκη εγγραφή που εμφανίζεται, με οροφή [_kRecentCallsCardMaxWidth].
/// Οι κάρτες ιστορικού δεν απλώνονται ανεξέλεγκτα ούτε αφήνουν νεκρό κενό.
double _recentCallsSmartCardWidth(
  BuildContext context,
  ThemeData theme,
  List<CallModel> calls,
) {
  final textScaler = MediaQuery.textScalerOf(context);
  final dateStyle = theme.textTheme.bodySmall ?? const TextStyle();
  final issueStyle = theme.textTheme.bodyMedium ?? const TextStyle();

  var maxRow = 0.0;
  for (final c in calls) {
    final dateW = singleLineTextWidth(
      text: '${c.date ?? ''} ${c.time ?? ''}',
      style: dateStyle,
      textScaler: textScaler,
    );
    final issue = (c.issue ?? '').trim();
    final issueW = singleLineTextWidth(
      text: issue.isEmpty ? '—' : issue,
      style: issueStyle,
      textScaler: textScaler,
    );
    final rowW = dateW + _kRecentCallsRowGap + issueW;
    if (rowW > maxRow) maxRow = rowW;
  }

  final contentW = math.max(_kRecentCallsMinContentWidth, maxRow);
  return math.min(
    _kRecentCallsCardMaxWidth,
    contentW + _kRecentCallsCardHorizontalPadding,
  );
}

/// Λίστα τελευταίων κλήσεων για τον επιλεγμένο καλούντα (`calls.caller_id`).
class RecentCallsList extends ConsumerWidget {
  const RecentCallsList({super.key, required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = user.id;
    if (id == null) return const SizedBox.shrink();
    final asyncCalls = ref.watch(recentCallsProvider(id));
    return asyncCalls.when(
      data: (calls) {
        if (calls.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final searchKeyword = _recentCallsHistorySearchKeyword(user);
        return LayoutBuilder(
          builder: (context, constraints) {
            final parentMax = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final smartWidth = _recentCallsSmartCardWidth(
              context,
              theme,
              calls,
            );
            final cardWidth = math.min(smartWidth, parentMax);
            return Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: SizedBox(
                width: cardWidth,
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                'Πρόσφατο ιστορικό Υπαλλήλου',
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            PopupMenuButton<_RecentCallsTitleMenu>(
                              tooltip: 'Ενέργειες',
                              icon: const Icon(Icons.more_vert, size: 22),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 36,
                              ),
                              onSelected: (action) {
                                switch (action) {
                                  case _RecentCallsTitleMenu.copyAll:
                                    Clipboard.setData(
                                      ClipboardData(
                                        text: _recentCallsListClipboardText(
                                          user,
                                          calls,
                                        ),
                                      ),
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Το κείμενο αντιγράφηκε στο πρόχειρο.',
                                          ),
                                        ),
                                      );
                                    }
                                  case _RecentCallsTitleMenu.openHistory:
                                    ref
                                        .read(historyFilterProvider.notifier)
                                        .update(
                                          (s) => s.copyWith(
                                            keyword: searchKeyword,
                                          ),
                                        );
                                    ref
                                        .read(
                                          mainNavRequestProvider.notifier,
                                        )
                                        .request(
                                          const MainNavRequest(
                                            destination:
                                                MainNavDestination.history,
                                          ),
                                        );
                                }
                              },
                              itemBuilder: (ctx) => const [
                                PopupMenuItem(
                                  value: _RecentCallsTitleMenu.copyAll,
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.copy),
                                    title: Text('Αντιγραφή κειμένου'),
                                    subtitle: Text(
                                      'Αντιγράφει τις γραμμές της λίστας για επικόλληση',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: _RecentCallsTitleMenu.openHistory,
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.history),
                                    title: Text('Μετάβαση στο ιστορικό'),
                                    subtitle: Text(
                                      'Φίλτρο αναζήτησης με όνομα ή τηλέφωνο',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...calls.map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${c.date ?? ''} ${c.time ?? ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    c.issue ?? '—',
                                    style: theme.textTheme.bodyMedium,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
