import 'package:flutter/material.dart';
import 'desktop_services.dart';

class StickyOverlayWidget extends StatelessWidget {
  const StickyOverlayWidget({super.key, required this.taskId, required this.title, this.actionUrl});
  final String taskId;
  final String title;
  final String? actionUrl;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('TaskPulse reminder'),
    content: Text(title),
    actions: [
      TextButton(onPressed: () async { await DesktopServices.instance.markDone(taskId); if (context.mounted) Navigator.pop(context); }, child: const Text('Done')),
      TextButton(onPressed: () async { await DesktopServices.instance.snooze(taskId, const Duration(minutes: 10)); if (context.mounted) Navigator.pop(context); }, child: const Text('Snooze +10m')),
      TextButton(onPressed: () async { await DesktopServices.instance.skip(taskId); if (context.mounted) Navigator.pop(context); }, child: const Text('Skip')),
      if (actionUrl?.isNotEmpty == true) FilledButton(onPressed: () => DesktopServices.instance.openAction(actionUrl!), child: const Text('Open Action')),
    ],
  );
}
