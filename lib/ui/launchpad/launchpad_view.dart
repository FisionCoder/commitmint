import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/git_repository.dart';
import '../../models/integration.dart';
import '../../services/git_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../repo/repo_actions.dart';
import '../widgets/mint_leaf.dart';

class LaunchpadView extends StatelessWidget {
  const LaunchpadView({super.key});

  static String genId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Container(
      color: AppColors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const MintLeafLogo(size: 34),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Commit Mint',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700)),
                      Text('Manage your repositories and connections',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.folder_open,
                      title: 'Open',
                      subtitle: 'A local repository',
                      color: AppColors.accent,
                      onTap: () => _openLocal(context, app),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.cloud_download_outlined,
                      title: 'Clone',
                      subtitle: 'From a remote URL',
                      color: AppColors.purple,
                      onTap: () => _clone(context, app),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.extension_outlined,
                      title: 'Integrations',
                      subtitle: 'Azure DevOps & more',
                      color: AppColors.accentTeal,
                      onTap: () => app.openIntegrations(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  const Text('Repositories',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(width: 8),
                  Text('${app.repositories.length}',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textMuted)),
                ],
              ),
              const SizedBox(height: 12),
              if (app.repositories.isEmpty)
                _emptyState()
              else
                for (final repo in app.repositories)
                  _RepoTile(repo: repo, app: app),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text('No repositories yet',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          SizedBox(height: 4),
          Text('Open a local repo, clone one, or connect an integration.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Future<void> _openLocal(BuildContext context, AppState app) async {
    final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select a local Git repository');
    if (dir == null) return;
    if (!context.mounted) return;
    final isRepo = await GitService.isGitRepo(dir);
    if (!isRepo) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That folder is not a Git repository.'),
          backgroundColor: AppColors.surfaceRaised,
        ));
      }
      return;
    }
    final name = dir.replaceAll('\\', '/').split('/').last;
    await app.addRepository(GitRepository(
      id: genId(),
      name: name.isEmpty ? dir : name,
      path: dir,
    ));
  }

  Future<void> _clone(BuildContext context, AppState app) async {
    final url = await promptText(context,
        title: 'Clone repository',
        hint: 'https://github.com/user/repo.git',
        confirm: 'Choose folder…');
    if (url == null || url.trim().isEmpty) return;
    if (!context.mounted) return;
    final parent = await FilePicker.platform
        .getDirectoryPath(dialogTitle: 'Choose destination folder');
    if (parent == null) return;

    final repoName = url
        .trim()
        .replaceAll(RegExp(r'\.git$'), '')
        .split('/')
        .last;
    final dest = '$parent/$repoName';
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Cloning $repoName…'),
      backgroundColor: AppColors.surfaceRaised,
      duration: const Duration(seconds: 30),
    ));
    try {
      await GitService.clone(url.trim(), dest);
      messenger.hideCurrentSnackBar();
      await app.addRepository(GitRepository(
        id: genId(),
        name: repoName,
        path: dest,
        remoteUrl: url.trim(),
      ));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text('Clone failed: $e'),
        backgroundColor: AppColors.red.withValues(alpha: 0.9),
      ));
    }
  }
}

class _ActionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceRaised : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _hover ? widget.color : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, color: widget.color, size: 20),
              ),
              const SizedBox(height: 14),
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(widget.subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepoTile extends StatefulWidget {
  final GitRepository repo;
  final AppState app;
  const _RepoTile({required this.repo, required this.app});

  @override
  State<_RepoTile> createState() => _RepoTileState();
}

class _RepoTileState extends State<_RepoTile> {
  bool _hover = false;

  /// Provider label for the integration this repo was cloned from, if any.
  String? get _providerLabel {
    final id = widget.repo.integrationId;
    if (id == null) return null;
    final matches = widget.app.integrations.where((i) => i.id == id);
    return matches.isEmpty ? 'Cloned' : matches.first.provider.label;
  }

  @override
  Widget build(BuildContext context) {
    final providerLabel = _providerLabel;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.app.openRepo(widget.repo),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceRaised : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_tree_outlined,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(widget.repo.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        if (providerLabel != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: AppColors.accentTeal
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(3)),
                            child: Text(providerLabel,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.accentTeal)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Tooltip(
                      message: widget.repo.path,
                      child: Text(widget.repo.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                    ),
                  ],
                ),
              ),
              if (_hover)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  color: AppColors.textMuted,
                  tooltip: 'Remove from list',
                  onPressed: () => widget.app.removeRepository(widget.repo),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
