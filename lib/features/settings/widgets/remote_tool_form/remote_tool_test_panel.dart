import 'package:flutter/material.dart';

import 'remote_tool_form_controller.dart';

class RemoteToolTestPanel extends StatelessWidget {
  const RemoteToolTestPanel({
    super.key,
    required this.controller,
    required this.onRunTest,
  });

  final RemoteToolFormController controller;
  final VoidCallback onRunTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller.testIpC,
          decoration: const InputDecoration(
            labelText: 'Δοκιμαστική IP / Hostname (για δοκιμή)',
            helperText:
                'Απαιτείται για δοκιμή· τροφοδοτεί {TARGET} και {EQUIPMENT_CODE}.',
            hintText: 'π.χ. 922 ή 192.168.1.100',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (controller.canRunTest) ...[
          Text(
            'Εντολή δοκιμής',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: SelectableText(
                controller.testCommandPreview,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: const [
                    'Courier New',
                    'monospace',
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Tooltip(
              message: controller.testButtonTooltip,
              showDuration: const Duration(seconds: 40),
              waitDuration: const Duration(milliseconds: 400),
              child: OutlinedButton.icon(
                onPressed: controller.saving || !controller.canRunTest
                    ? null
                    : onRunTest,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Δοκιμή εργαλείου'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
