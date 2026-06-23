import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/git_repository.dart';
import '../../models/integration.dart';
import '../../services/git_service.dart';
import '../../services/integration_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../launchpad/launchpad_view.dart';

class RepoBrowserDialog extends StatefulWidget {
  final Integration instance;
  final String secret;
  const RepoBrowserDialog(
      {super.key, required this.instance, required this.secret});

  @override
  State<RepoBrowserDialog> createState() => _RepoBrowserDialogState();
}

class _RepoBrowserDialogState extends State<RepoBrowserDialog> {
  late Future<List<RemoteRepo>> _future;
  String _filter = '';
  String? _cloningId;

  @override
  void initState() {
    super.initState();
    _future =
        IntegrationService.listRepositories(widget.instance, widget.secret);
  }

  Future<void> _clone(RemoteRepo repo) async {
    final parent = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose where to clone ${repo.name}');
    if (parent == null) return;
    if (!mounted) return;

    setState(() => _cloningId = repo.id);
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final dest = '$parent/${repo.name}';
    try {
      await GitService.clone(repo.cloneUrl, dest,
          userInfo:
              IntegrationService.cloneUserInfo(widget.instance, widget.secret));
      await app.addRepository(GitRepository(
        id: LaunchpadView.genId(),
        name: repo.name,
        path: dest,
        remoteUrl: repo.cloneUrl,
        integrationId: widget.instance.id,
      ));
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text('Cloned ${repo.name}'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _cloningId = null);
      messenger.showSnackBar(SnackBar(
        content: Text('Clone failed: $e'),
        backgroundColor: AppColors.red.withValues(alpha: 0.95),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 560,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.cloud_done_outlined,
                      color: AppColors.accentTeal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.instance.title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const Text('Select a repository to clone',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _filter = v),
                decoration: const InputDecoration(
                  hintText: 'Filter repositories…',
                  prefixIcon: Icon(Icons.search, size: 16),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<RemoteRepo>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _error(snap.error.toString());
                  }
                  final repos = (snap.data ?? [])
                      .where((r) =>
                          _filter.isEmpty ||
                          r.name
                              .toLowerCase()
                              .contains(_filter.toLowerCase()) ||
                          r.group
                              .toLowerCase()
                              .contains(_filter.toLowerCase()))
                      .toList();
                  if (repos.isEmpty) {
                    return const Center(
                      child: Text('No repositories found',
                          style: TextStyle(color: AppColors.textMuted)),
                    );
                  }
                  return ListView.builder(
                    itemCount: repos.length,
                    itemBuilder: (context, i) => _RepoRow(
                        repo: repos[i],
                        onClone: _clone,
                        cloningId: _cloningId),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _error(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: AppColors.red, size: 32),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _RepoRow extends StatefulWidget {
  final RemoteRepo repo;
  final Future<void> Function(RemoteRepo) onClone;
  final String? cloningId;
  const _RepoRow(
      {required this.repo, required this.onClone, required this.cloningId});

  @override
  State<_RepoRow> createState() => _RepoRowState();
}

class _RepoRowState extends State<_RepoRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cloning = widget.cloningId == widget.repo.id;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        color: _hover ? AppColors.surfaceRaised : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 16, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.repo.name,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w500)),
                  Row(
                    children: [
                      if (widget.repo.group.isNotEmpty) ...[
                        const Icon(Icons.folder_outlined,
                            size: 11, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(widget.repo.group,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppColors.textMuted)),
                        ),
                      ],
                      if (widget.repo.defaultBranch != null) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.call_split,
                            size: 11, color: AppColors.textMuted),
                        const SizedBox(width: 3),
                        Text(widget.repo.defaultBranch!,
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.textMuted)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (cloning)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (_hover)
              OutlinedButton(
                onPressed: widget.cloningId != null
                    ? null
                    : () => widget.onClone(widget.repo),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('Clone', style: TextStyle(fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}
