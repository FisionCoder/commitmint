import 'package:flutter/material.dart';

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
