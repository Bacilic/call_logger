import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calls/provider/remote_paths_provider.dart';
import '../../../core/models/remote_tool_arg.dart';

/// Επεξεργαστής ορισμάτων γραμμής εντολών για VNC ή AnyDesk.
/// Εμφανίζει λίστα ορισμάτων με checkbox (ενεργό/ανενεργό), επεξεργασία, διαγραφή, προσθήκη και δοκιμή.
class RemoteArgsEditor extends ConsumerStatefulWidget {
  const RemoteArgsEditor({super.key, required this.toolName});

  final String toolName;

  @override
  ConsumerState<RemoteArgsEditor> createState() => _RemoteArgsEditorState();
}

class _RemoteArgsEditorState extends ConsumerState<RemoteArgsEditor> {
  List<RemoteToolArg> _args = [];
  bool _loading = true;
  String? _error;

  Future<void> _loadArgs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(remoteArgsServiceProvider);
      final list = await service.getArgsForTool(widget.toolName);
      if (mounted) {
        setState(() {
          _args = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadArgs());
  }

  Future<void> _toggle(RemoteToolArg arg) async {
    try {
      final service = ref.read(remoteArgsServiceProvider);
      await service.toggleArg(arg);
      await _loadArgs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _delete(RemoteToolArg arg) async {
    if (arg.id == null) return;
    try {
      final service = ref.read(remoteArgsServiceProvider);
      await service.deleteArg(arg.id!);
      await _loadArgs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<({String argFlag, String description})>(
      context: context,
      builder: (ctx) => const _ArgEditDialog(argFlag: '', description: ''),
    );
    if (result == null || !mounted) return;
    try {
      final service = ref.read(remoteArgsServiceProvider);
      await service.addArg(RemoteToolArg(
        toolName: widget.toolName,
        argFlag: result.argFlag,
        description: result.description,
        isActive: true,
      ));
      await _loadArgs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _showEditDialog(RemoteToolArg arg) async {
    final result = await showDialog<({String argFlag, String description})>(
      context: context,
      builder: (ctx) => _ArgEditDialog(argFlag: arg.argFlag, description: arg.description),
    );
    if (result == null || !mounted) return;
    try {
      final service = ref.read(remoteArgsServiceProvider);
      await service.updateArg(arg.copyWith(argFlag: result.argFlag, description: result.description));
      await _loadArgs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _runTest() async {
    try {
      final launcher = ref.read(remoteLauncherServiceProvider);
      await launcher.testToolArguments(widget.toolName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Η δοκιμή ξεκίνησε με τη δοκιμαστική IP και τον κωδικό από τις ρυθμίσεις.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FilledButton.tonalIcon(
              onPressed: _showAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('Προσθήκη ορίσματος'),
            ),
            OutlinedButton.icon(
              onPressed: _runTest,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Δοκιμή'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_args.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Δεν υπάρχουν ορίσματα. Προσθέστε με το κουμπί παραπάνω.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _args.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final arg = _args[index];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Checkbox(
                    value: arg.isActive,
                    onChanged: (_) => _toggle(arg),
                  ),
                  title: Text(
                    arg.argFlag,
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: arg.description.isNotEmpty
                      ? Text(arg.description, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showEditDialog(arg),
                        tooltip: 'Επεξεργασία',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(arg),
                        tooltip: 'Διαγραφή',
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _ArgEditDialog extends StatefulWidget {
  const _ArgEditDialog({required this.argFlag, required this.description});

  final String argFlag;
  final String description;

  @override
  State<_ArgEditDialog> createState() => _ArgEditDialogState();
}

class _ArgEditDialogState extends State<_ArgEditDialog> {
  late final TextEditingController _argFlagController;
  late final TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _argFlagController = TextEditingController(text: widget.argFlag);
    _descController = TextEditingController(text: widget.description);
  }

  @override
  void dispose() {
    _argFlagController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.argFlag.isEmpty ? 'Προσθήκη ορίσματος' : 'Επεξεργασία ορίσματος'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _argFlagController,
            decoration: const InputDecoration(
              labelText: 'Όρισμα (π.χ. -fullscreen ή {TARGET})',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Περιγραφή',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop((
              argFlag: _argFlagController.text.trim(),
              description: _descController.text.trim(),
            ));
          },
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
