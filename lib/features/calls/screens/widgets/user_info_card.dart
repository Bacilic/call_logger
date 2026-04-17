import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/search_text_normalizer.dart';
import '../../../directory/models/department_model.dart';
import '../../../directory/providers/department_directory_provider.dart';
import '../../../directory/providers/directory_provider.dart';
import '../../../directory/screens/widgets/department_form_dialog.dart';
import '../../../directory/screens/widgets/user_form_dialog.dart';
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

Future<void> _openDepartmentCatalogForm(
  BuildContext context,
  WidgetRef ref,
  UserModel user,
) async {
  final notifier = ref.read(departmentDirectoryProvider.notifier);
  await notifier.loadDepartments();
  if (!context.mounted) return;
  final state = ref.read(departmentDirectoryProvider);
  DepartmentModel? department;
  final deptId = user.departmentId;
  if (deptId != null) {
    for (final d in state.allDepartments) {
      if (d.isDeleted) continue;
      if (d.id == deptId) {
        department = d;
        break;
      }
    }
  }
  if (department == null) {
    final name = (user.departmentName ?? '').trim();
    if (name.isNotEmpty) {
      final norm = SearchTextNormalizer.normalizeForSearch(name);
      for (final d in state.allDepartments) {
        if (d.isDeleted) continue;
        final dn = SearchTextNormalizer.normalizeForSearch(d.name);
        if (dn == norm) {
          department = d;
          break;
        }
      }
    }
  }
  if (department == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δεν βρέθηκε το τμήμα στον κατάλογο (ή δεν έχει οριστεί τμήμα για τον υπάλληλο).',
          ),
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) =>
        DepartmentFormDialog(initialDepartment: department, notifier: notifier),
  );
}

enum _UserInfoCardTitleMenu { copyAll, openUserEdit, openDepartmentEdit }

/// Κάρτα στοιχείων χρήστη (όνομα, τμήμα, τηλέφωνο).
class UserInfoCard extends ConsumerWidget {
  const UserInfoCard({super.key, required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

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
                        case _UserInfoCardTitleMenu.openUserEdit:
                          showDialog<void>(
                            context: context,
                            builder: (ctx) => UserFormDialog(
                              initialUser: user,
                              notifier: ref.read(directoryProvider.notifier),
                            ),
                          );
                        case _UserInfoCardTitleMenu.openDepartmentEdit:
                          _openDepartmentCatalogForm(context, ref, user);
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
                        value: _UserInfoCardTitleMenu.openUserEdit,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Άνοιγμα καρτέλας χρήστη'),
                          subtitle: Text(
                            'Φόρμα επεξεργασίας υπαλλήλου',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _UserInfoCardTitleMenu.openDepartmentEdit,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.apartment_outlined),
                          title: Text('Άνοιγμα καρτέλας τμήματος'),
                          subtitle: Text(
                            'Φόρμα επεξεργασίας τμήματος',
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
                  _row(
                    theme,
                    Icons.business,
                    'Τμήμα',
                    user.departmentName ?? '–',
                  ),
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
