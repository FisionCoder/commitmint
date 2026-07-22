// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/integration.dart';
import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/notifier.dart';

/// Opens the in-app "create pull request" dialog for [target] (a connected
/// GitHub/GitLab/Bitbucket integration), pre-filled with source/target branch.
Future<void> showCreatePullRequestDialog(
  BuildContext context,
  RepoState state, {
  required ({Integration inst, String secret, String owner, String repo}) target,
  required String sourceBranch,
  required String targetBranch,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CreatePrDialog(
      state: state,
      target: target,
      sourceBranch: sourceBranch,
      targetBranch: targetBranch,
    ),
  );
}

class _CreatePrDialog extends StatefulWidget {
  final RepoState state;
  final ({Integration inst, String secret, String owner, String repo}) target;
  final String sourceBranch;
  final String targetBranch;
  const _CreatePrDialog({
    required this.state,
    required this.target,
    required this.sourceBranch,
    required this.targetBranch,
  });

  @override
  State<_CreatePrDialog> createState() => _CreatePrDialogState();
}

class _CreatePrDialogState extends State<_CreatePrDialog> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _target;
  bool _draft = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.sourceBranch);
    _body = TextEditingController();
    _target = TextEditingController(
        text: widget.targetBranch.isEmpty ? 'main' : widget.targetBranch);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final url = await widget.state.createPullRequest(
        inst: widget.target.inst,
        secret: widget.target.secret,
        owner: widget.target.owner,
        repo: widget.target.repo,
        title: _title.text.trim(),
        body: _body.text.trim(),
        sourceBranch: widget.sourceBranch,
        targetBranch: _target.text.trim(),
        draft: _draft,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      notify(context, 'Pull request created',
          icon: Icons.check_circle, iconColor: AppColors.green);
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      notify(context, e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error, iconColor: AppColors.red,
          duration: const Duration(seconds: 5));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Row(
        children: [
          Icon(Icons.merge_type, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          const Text('Create Pull Request', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BranchLine(
                from: widget.sourceBranch,
                intoController: _target,
                repo: '${widget.target.owner}/${widget.target.repo}'),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)'),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _draft,
              onChanged: (v) => setState(() => _draft = v ?? false),
              title: const Text('Create as draft', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check, size: 16),
          label: const Text('Create'),
        ),
      ],
    );
  }
}

class _BranchLine extends StatelessWidget {
  final String from;
  final TextEditingController intoController;
  final String repo;
  const _BranchLine(
      {required this.from, required this.intoController, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.call_split, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(from,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, size: 14, color: AppColors.textMuted),
          ),
          Expanded(
            child: TextField(
              controller: intoController,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'into',
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
