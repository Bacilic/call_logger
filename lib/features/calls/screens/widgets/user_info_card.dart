import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user_model.dart';

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
                ],
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _row(theme, Icons.business, 'Τμήμα', user.departmentName ?? '–'),
                  _row(theme, Icons.phone, 'Τηλ.', user.phone),
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
