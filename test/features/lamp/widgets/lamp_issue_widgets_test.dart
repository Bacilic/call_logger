import 'package:call_logger/features/lamp/widgets/lamp_issue_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LampIssueHelpers.resolveNetworkIssueIcon', () {
    const cases = <String, IconData>{
      'network_invalid_ip': Icons.wrong_location_outlined,
      'network_duplicate_ip': Icons.difference_outlined,
      'network_duplicate_name': Icons.content_copy_outlined,
      'network_duplicate_hostname': Icons.file_copy_outlined,
      'network_name_code_mismatch': Icons.sync_problem_outlined,
      'network_no_hostname': Icons.label_off_outlined,
      'network_hostname_unmatched': Icons.link_off_outlined,
      'network_code_not_found': Icons.search_off_outlined,
      'network_ip_in_comments': Icons.comment_outlined,
      'network_model_mismatch': Icons.devices_other_outlined,
      'network_sheet_invalid': Icons.grid_off_outlined,
    };

    for (final entry in cases.entries) {
      test('${entry.key} → ${entry.value}', () {
        expect(
          LampIssueHelpers.resolveNetworkIssueIcon(entry.key),
          entry.value,
        );
      });
    }

    test('άγνωστος τύπος επιστρέφει Icons.hub_outlined', () {
      expect(
        LampIssueHelpers.resolveNetworkIssueIcon('network_κατι_αλλο'),
        Icons.hub_outlined,
      );
    });
  });
}
