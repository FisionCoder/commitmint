// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';

import '../../services/git_service.dart';
import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import 'repo_actions.dart';

/// Browses `git reflog` and lets the user move HEAD back (or forward) to any
/// prior state — the safe, explicit "undo" mechanism: pick an entry and reset
/// (soft/mixed/hard) or checkout to it.
Future<void> showReflogDialog(BuildContext context, RepoState state) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReflogDialog(state: state),
  );
}

class _ReflogDialog extends StatelessWidget {
  final RepoState state;
  const _ReflogDialog({required this.state});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Row(
        children: [
          Icon(Icons.history, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          const Text('History (reflog)', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 440,
        child: FutureBuilder<List<ReflogEntry>>(
          future: state.loadReflog(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snap.data!;
            if (entries.isEmpty) {
              return Center(
                  child: Text('No reflog entries.',
                      style: TextStyle(color: AppColors.textMuted)));
            }
            return ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) =>
                  _ReflogRow(state: state, entry: entries[i]),
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ReflogRow extends StatelessWidget {
  final RepoState state;
  final ReflogEntry entry;
  const _ReflogRow({required this.state, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(entry.shortSha,
                style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11.5,
                    color: AppColors.accentTeal)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.selector,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        fontFamily: 'Consolas')),
                const SizedBox(height: 2),
                Text(entry.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Move HEAD here',
            color: AppColors.surfaceRaised,
            icon: Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'checkout', child: Text('Checkout')),
              const PopupMenuItem(
                  value: 'soft', child: Text('Reset (soft — keep changes)')),
              const PopupMenuItem(
                  value: 'mixed', child: Text('Reset (mixed)')),
              PopupMenuItem(
                  value: 'hard',
                  child: Text('Reset (hard — discard changes)',
                      style: TextStyle(color: AppColors.red))),
            ],
            onSelected: (v) async {
              if (v == 'checkout') {
                Navigator.of(context).pop();
                return runRepoAction(
                    context, () => state.checkoutCommit(entry.sha),
                    success: 'Checked out ${entry.shortSha}');
              }
              if (v == 'hard') {
                final ok = await _confirm(context);
                if (!ok || !context.mounted) return;
              }
              Navigator.of(context).pop();
              return runRepoAction(
                  context, () => state.resetTo(entry.sha, v),
                  success: 'Reset ($v) to ${entry.shortSha}');
            },
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Hard reset?', style: TextStyle(fontSize: 16)),
        content: Text(
            'Move ${state.currentBranch} to ${entry.shortSha} and discard all '
            'uncommitted changes? This cannot be undone (except via the reflog).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hard reset'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
