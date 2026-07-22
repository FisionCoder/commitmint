import 'package:flutter/material.dart';

import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/notifier.dart';

/// Runs a repo action future, showing a notification on success/failure.
Future<void> runRepoAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (success != null && context.mounted) {
      notify(context, success,
          icon: Icons.check_circle,
          iconColor: AppColors.green,
          duration: const Duration(seconds: 2));
    }
  } catch (e) {
    if (context.mounted) {
      notify(context, e.toString(),
          icon: Icons.error,
          iconColor: AppColors.red,
          duration: const Duration(seconds: 4));
    }
  }
}

/// Simple text-input dialog (used for new branch name).
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String hint,
  String confirm = 'OK',
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(confirm),
        ),
      ],
    ),
  );
}

/// Stash dialog: optional message + include-untracked / keep-index options.
/// Falls back to a bare `stash push` (no options) if the user just confirms.
Future<void> stashWithOptions(BuildContext context, RepoState state) async {
  final controller = TextEditingController();
  var includeUntracked = false;
  var keepIndex = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Stash changes', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration:
                    const InputDecoration(hintText: 'Stash message (optional)'),
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: includeUntracked,
                onChanged: (v) => setState(() => includeUntracked = v ?? false),
                title: const Text('Include untracked files',
                    style: TextStyle(fontSize: 13)),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: keepIndex,
                onChanged: (v) => setState(() => keepIndex = v ?? false),
                title: const Text('Keep staged changes in the index',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stash'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await runRepoAction(
    context,
    () => state.stashPushWith(
        message: controller.text,
        includeUntracked: includeUntracked,
        keepIndex: keepIndex),
    success: 'Changes stashed',
  );
}

/// Previews (dry-run) then removes untracked files with `git clean -fd`.
Future<void> cleanUntrackedWithConfirm(
    BuildContext context, RepoState state) async {
  final preview = await state.cleanPreview();
  if (!context.mounted) return;
  if (preview.isEmpty) {
    notify(context, 'No untracked files to clean.');
    return;
  }
  final shown = preview.take(20).join('\n');
  final more = preview.length > 20 ? '\n…and ${preview.length - 20} more' : '';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Clean untracked files?', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${preview.length} untracked item(s) will be permanently '
                'deleted. This cannot be undone.'),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: SingleChildScrollView(
                child: SelectableText('$shown$more',
                    style: const TextStyle(fontSize: 12, fontFamily: 'Consolas')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete files'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await runRepoAction(context, state.cleanUntracked,
      success: 'Removed ${preview.length} untracked item(s)');
}
