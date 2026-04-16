import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/main_nav_request_provider.dart';
import '../../../../core/providers/user_form_edit_intent_provider.dart';
import '../../../../core/widgets/main_nav_destination.dart';
import '../../../directory/models/user_catalog_mode.dart';
import '../../../directory/providers/directory_provider.dart';
import '../../../history/providers/history_provider.dart';
import '../../models/user_model.dart';

String _userInfoCardClipboardText(UserModel user) {
  final buf = StringBuffer();
  final name = (user.name ?? '').trim().isEmpty ? '—' : user.name!.trim();
  buf.writeln(name);
  final dept = (user.departmentName ?? '').trim();
  if (dept.isNotEmpty) buf.writeln('Τμήμα: $dept');
  final phones = user.phoneJoined.trim();
  if (phones.isNotEmpty) buf.writeln('Τηλ.: $phones');
  final notes = user.notes?.trim() ?? '';
  if (notes.isNotEmpty) buf.writeln('Σημείωση: $notes');
  return buf.toString().trimRight();
}

/// Λέξη-κλειδί για αναζήτηση ιστορικού: όνομα, αλλιώς πρώτο μη κενό τηλέφωνο.
String _userInfoHistorySearchKeyword(UserModel user) {
  final n = user.name?.trim() ?? '';
  if (n.isNotEmpty) return n;
  for (final p in user.phones) {
    final t = p.trim();
    if (t.isNotEmpty) return t;
  }
  return '';
}

enum _UserInfoCardTitleMenu { copyAll, openHistory, openUserEdit }

/// Κάρτα στοιχείων χρήστη (όνομα, τμήμα, τηλέφωνο).
class UserInfoCard extends ConsumerWidget {
  const UserInfoCard({
    super.key,
    required this.user,
  });

  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final searchKeyword = _userInfoHistorySearchKeyword(user);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Text(
                      user.name ?? '—',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  PopupMenuButton<_UserInfoCardTitleMenu>(
                    tooltip: 'Ενέργειες',
                    icon: const Icon(Icons.more_vert, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 36,
                    ),
                    onSelected: (action) {
                      switch (action) {
                        case _UserInfoCardTitleMenu.copyAll:
                          Clipboard.setData(
                            ClipboardData(
                              text: _userInfoCardClipboardText(user),
                            ),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Το κείμενο αντιγράφηκε στο πρόχειρο.',
                                ),
                              ),
                            );
                          }
                        case _UserInfoCardTitleMenu.openHistory:
                          ref
                              .read(historyFilterProvider.notifier)
                              .update(
                                (s) => s.copyWith(keyword: searchKeyword),
                              );
                          ref.read(mainNavRequestProvider.notifier).request(
                                const MainNavRequest(
                                  destination: MainNavDestination.history,
                                ),
                              );
                        case _UserInfoCardTitleMenu.openUserEdit:
                          ref
                              .read(directoryProvider.notifier)
                              .setCatalogMode(UserCatalogMode.personal);
                          ref.read(mainNavRequestProvider.notifier).request(
                                const MainNavRequest(
                                  destination: MainNavDestination.directory,
                                  directoryTabIndex: 0,
                                ),
                              );
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              ref
                                  .read(userFormEditIntentProvider.notifier)
                                  .requestEdit(user);
                            });
                          });
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: _UserInfoCardTitleMenu.copyAll,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.copy),
                          title: Text('Αντιγραφή κειμένου'),
                          subtitle: Text(
                            'Αντιγράφει τα στοιχεία της κάρτας για επικόλληση',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _UserInfoCardTitleMenu.openHistory,
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
                      const PopupMenuItem(
                        value: _UserInfoCardTitleMenu.openUserEdit,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Άνοιγμα καρτέλας χρήστη'),
                          subtitle: Text(
                            'Κατάλογος → Χρήστες και φόρμα επεξεργασίας',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _row(theme, Icons.business, 'Τμήμα', user.departmentName ?? '–'),
                  _row(theme, Icons.phone, 'Τηλ.', user.phoneJoined),
                  if (user.notes != null && user.notes!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Tooltip(
                        message: user.notes!.trim(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.note_alt_outlined,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Σημείωση: ',
                              style: theme.textTheme.bodySmall,
                            ),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Text(
                                user.notes!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _row(
    ThemeData theme,
    IconData icon,
    String label,
    String? value,
  ) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$label: ', style: theme.textTheme.bodySmall),
          Flexible(
            fit: FlexFit.loose,
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
