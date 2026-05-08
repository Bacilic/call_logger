import 'package:flutter/material.dart';

class LansweeperSyncForm extends StatelessWidget {
  const LansweeperSyncForm({
    required this.titleController,
    required this.notesController,
    required this.agentController,
    super.key,
  });

  final TextEditingController titleController;
  final TextEditingController notesController;
  final TextEditingController agentController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Φόρμα καταχώρησης Lansweeper',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Τίτλος',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Σημειώσεις',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: agentController,
              decoration: const InputDecoration(
                labelText: 'Πράκτορας (username)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
