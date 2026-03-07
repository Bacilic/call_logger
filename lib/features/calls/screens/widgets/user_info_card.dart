import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/equipment_model.dart';
import '../../models/user_model.dart';

/// Κάρτα στοιχείων χρήστη και εξοπλισμού με κουμπί VNC.
class UserInfoCard extends StatelessWidget {
  const UserInfoCard({
    super.key,
    required this.user,
    this.equipment,
  });

  final UserModel user;
  final EquipmentModel? equipment;

  Future<void> _openVnc() async {
    final host = equipment != null ? _vncPlaceholder(equipment!) : null;
    final uri = Uri.parse('vnc://${host ?? 'localhost'}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _vncPlaceholder(EquipmentModel e) {
    return 'localhost';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.name ?? '—',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _openVnc,
                  icon: const Icon(Icons.desktop_windows, size: 18),
                  label: const Text('VNC'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _row(theme, Icons.business, 'Τμήμα', user.department),
            _row(theme, Icons.phone, 'Τηλ.', user.phone),
            _row(theme, Icons.location_on, 'Τοποθεσία', user.location),
            if (equipment != null) ...[
              const Divider(height: 24),
              Text(
                'Εξοπλισμός',
                style: theme.textTheme.titleSmall,
              ),
              _row(theme, Icons.computer, 'Τύπος', equipment!.type),
              _row(theme, Icons.tag, 'Κωδικός εξοπλισμού', equipment!.code),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    IconData icon,
    String label,
    String? value,
  ) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$label: ', style: theme.textTheme.bodySmall),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
