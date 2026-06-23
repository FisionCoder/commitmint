// Context here is the long-lived repo view; menu actions guard with mounted
// where it matters and are safe to dispatch after the menu closes.
// ignore_for_file: use_build_context_synchronously
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/git_commit.dart';
import '../../services/git_service.dart';
import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import 'git_links.dart';
import 'repo_actions.dart';

final commitMenuStyle = MenuStyle(
  backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceRaised),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.4)),
  padding:
      const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
  ),
);

Widget _leaf(String label, VoidCallback onTap, {Color? color}) {
  return MenuItemButton(
    onPressed: onTap,
    style: MenuItemButton.styleFrom(
      foregroundColor: color ?? AppColors.textPrimary,
      alignment: Alignment.centerLeft,
      minimumSize: const Size(240, 34),
      maximumSize: const Size(420, 34),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: const TextStyle(fontSize: 13),
    ),
    child: Text(label, overflow: TextOverflow.ellipsis),
  );
}

Widget _submenu(String label, List<Widget> children) {
  return SubmenuButton(
    menuStyle: commitMenuStyle,
    style: SubmenuButton.styleFrom(
      foregroundColor: AppColors.textPrimary,
      alignment: Alignment.centerLeft,
      minimumSize: const Size(240, 34),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: const TextStyle(fontSize: 13),
    ),
    menuChildren: children,
    child: Text(label),
  );
}

const _divider = Padding(
  padding: EdgeInsets.symmetric(vertical: 4),
  child: Divider(height: 1, thickness: 1, color: AppColors.border),
);

/// Builds the menu entries for a commit (used as MenuAnchor.menuChildren).
List<Widget> buildCommitMenuChildren(
    BuildContext context, RepoState state, GitCommit commit) {
  final branch = state.currentBranch;
  final isHead =
      commit.refs.any((r) => r == 'HEAD' || r.startsWith('HEAD -> '));

  final remoteRefs = commit.refs
      .where((r) => r.contains('/') && !r.startsWith('tag:'))
      .toList();
  final localRefs = <String>[];
  for (final ref in commit.refs) {
    if (ref.startsWith('HEAD -> ')) {
      localRefs.add(ref.substring('HEAD -> '.length));
    } else if (ref != 'HEAD' &&
        !ref.startsWith('tag:') &&
        !ref.contains('/')) {
      localRefs.add(ref);
    }
  }

  void handle(String v) =>
      _dispatch(context, state, commit, branch, isHead, v);

  // Checkout targets: remote/local branches at the commit, then the commit.
  final checkoutItems = <Widget>[
    for (final r in remoteRefs)
      _leaf(r, () => handle('checkout:${r.substring(r.indexOf('/') + 1)}')),
    for (final b in localRefs) _leaf(b, () => handle('checkout:$b')),
    _leaf('this commit', () => handle('checkoutCommit')),
  ];
  final worktreeItems = <Widget>[
    for (final r in remoteRefs) _leaf(r, () => handle('worktree:$r')),
    for (final b in localRefs) _leaf(b, () => handle('worktree:$b')),
    _leaf('this commit', () => handle('worktree:__commit__')),
  ];
  final refLabel = remoteRefs.isNotEmpty ? remoteRefs.first : 'origin/$branch';

  return [
    _leaf('Pull (fast-forward if possible)', () => handle('pull')),
    _leaf('Push', () => handle('push')),
    _leaf('Set Upstream', () => handle('setUpstream')),
    _divider,
    _submenu('Checkout', checkoutItems),
    _submenu('Create worktree from', worktreeItems),
    _divider,
    _leaf('Create branch here', () => handle('createBranch')),
    _submenu('Reset $branch to this commit', [
      _leaf('Soft — keep all changes staged', () => handle('reset:soft')),
      _leaf('Mixed — keep changes unstaged', () => handle('reset:mixed')),
      _leaf('Hard — discard all changes', () => handle('reset:hard'),
          color: AppColors.red),
    ]),
    _leaf('Edit commit message', () => handle('editMessage')),
    _leaf('Revert commit', () => handle('revert')),
    _divider,
    _leaf('Drop commit', () => handle('drop')),
    _leaf('Move commit down', () => handle('moveDown')),
    _divider,
    _leaf('Start a pull request to origin from $refLabel',
        () => handle('startPR')),
    _divider,
    _leaf('Apply patch', () => handle('applyPatch')),
    _leaf('Rename $branch', () => handle('renameBranch')),
    _leaf('Delete $branch', () => handle('deleteBranch')),
    _leaf('Delete origin/$branch', () => handle('deleteRemote')),
    _leaf('Delete $branch and origin/$branch', () => handle('deleteBoth')),
    _divider,
    _leaf('Copy branch name', () => handle('copyBranch')),
    _leaf('Copy commit sha', () => handle('copySha')),
    _leaf('Copy link to branch: origin/$branch', () => handle('copyBranchLink')),
    _leaf('Copy link to this commit on remote: origin',
        () => handle('copyCommitLink')),
    _leaf('Create patch from commit', () => handle('createPatch')),
    _leaf('Share commit as Cloud Patch', () => handle('cloudPatch')),
    _divider,
    _submenu('Pin to Left', [
      _leaf(refLabel, () => handle('pin')),
      _leaf('this commit', () => handle('pin')),
    ]),
    _submenu('Solo', [
      _leaf(refLabel, () => handle('solo')),
      _leaf('this commit', () => handle('solo')),
    ]),
    _divider,
    _leaf('Compare commit against working directory', () => handle('compare')),
    _divider,
    _leaf('Create tag here', () => handle('tag')),
    _leaf('Create annotated tag here', () => handle('annotatedTag')),
  ];
}

Future<void> _dispatch(BuildContext context, RepoState state,
    GitCommit commit, String branch, bool isHead, String action) async {
  final sha = commit.hash;

  void copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    _toast(context, 'Copied $what');
  }

  if (action.startsWith('checkout:')) {
    final b = action.substring('checkout:'.length);
    return runRepoAction(context, () => state.checkout(b),
        success: 'Checked out $b');
  }
  if (action.startsWith('worktree:')) {
    final ref = action.substring('worktree:'.length);
    final isCommit = ref == '__commit__';
    final refArg = isCommit ? sha : ref;
    final name =
        isCommit ? commit.shortHash : ref.replaceAll(RegExp(r'[\\/]'), '-');
    final parent = await FilePicker.platform
        .getDirectoryPath(dialogTitle: 'Choose a parent folder for the worktree');
    if (parent != null && context.mounted) {
      return runRepoAction(
          context, () => state.worktreeAdd('$parent/$name', refArg),
          success: 'Worktree created at $parent/$name');
    }
    return;
  }
  if (action.startsWith('reset:')) {
    final mode = action.substring('reset:'.length);
    if (mode == 'hard' &&
        !await _confirm(context, 'Reset $branch to this commit (hard)?',
            'This discards all changes after ${commit.shortHash}. '
                'This cannot be undone.')) {
      return;
    }
    return runRepoAction(context, () => state.resetTo(sha, mode),
        success: 'Reset ($mode) to ${commit.shortHash}');
  }

  switch (action) {
    case 'pull':
      return runRepoAction(context, state.pull, success: 'Pull complete');
    case 'push':
      return runRepoAction(context, state.push, success: 'Push complete');
    case 'setUpstream':
      return runRepoAction(context, state.setUpstreamToTracking,
          success: 'Upstream set to origin/$branch');
    case 'checkoutCommit':
      return runRepoAction(context, () => state.checkoutCommit(sha),
          success: 'Checked out ${commit.shortHash}');
    case 'createBranch':
      final name = await promptText(context,
          title: 'Create branch here', hint: 'branch name', confirm: 'Create');
      if (name != null && name.trim().isNotEmpty && context.mounted) {
        return runRepoAction(
            context, () => state.createBranchAt(name.trim(), sha),
            success: 'Created ${name.trim()}');
      }
      return;
    case 'editMessage':
      if (!isHead) {
        return _toast(context,
            'Only the latest commit (HEAD) can be edited in this build.');
      }
      final current = await state.git.commitMessage(sha);
      if (!context.mounted) return;
      final msg = await promptText(context,
          title: 'Edit commit message',
          hint: 'commit message',
          initial: current,
          confirm: 'Amend');
      if (msg != null && msg.trim().isNotEmpty && context.mounted) {
        return runRepoAction(context, () => state.amendMessage(msg.trim()),
            success: 'Commit message updated');
      }
      return;
    case 'revert':
      return runRepoAction(context, () => state.revertCommit(sha),
          success: 'Reverted ${commit.shortHash}');
    case 'drop':
      if (await _confirm(context, 'Drop commit ${commit.shortHash}?',
          'This rewrites history by removing the commit. '
              'Requires a clean working tree.')) {
        return runRepoAction(context, () => state.dropCommit(sha),
            success: 'Dropped ${commit.shortHash}');
      }
      return;
    case 'moveDown':
      if (await _confirm(context, 'Move commit down?',
          'This reorders history by swapping ${commit.shortHash} with its '
              'parent. The repository is restored automatically on conflict.')) {
        return runRepoAction(context, () => state.moveCommitDown(sha),
            success: 'Moved ${commit.shortHash} down');
      }
      return;
    case 'startPR':
      final url = gitPrCreateUrl(await state.git.remoteUrl(), branch);
      if (url == null) return _toast(context, 'No remote URL configured.');
      await GitService.openUrl(url);
      return _toast(context, 'Opening pull request page…');
    case 'renameBranch':
      final name = await promptText(context,
          title: 'Rename $branch',
          hint: 'new branch name',
          initial: branch,
          confirm: 'Rename');
      if (name != null && name.trim().isNotEmpty && context.mounted) {
        return runRepoAction(
            context, () => state.renameBranch(branch, name.trim()),
            success: 'Renamed to ${name.trim()}');
      }
      return;
    case 'deleteBranch':
      if (await _confirm(
          context, 'Delete $branch?', 'Delete local branch "$branch"?')) {
        return runRepoAction(context, () => state.deleteBranch(branch),
            success: 'Deleted $branch');
      }
      return;
    case 'deleteRemote':
      if (await _confirm(context, 'Delete origin/$branch?',
          'Delete the remote branch "origin/$branch"?')) {
        return runRepoAction(
            context, () => state.deleteRemoteBranch('origin', branch),
            success: 'Deleted origin/$branch');
      }
      return;
    case 'deleteBoth':
      if (await _confirm(context, 'Delete $branch and origin/$branch?',
          'Delete both the local and remote branch "$branch"?')) {
        return runRepoAction(context, () async {
          await state.deleteRemoteBranch('origin', branch);
          await state.deleteBranch(branch, force: true);
        }, success: 'Deleted $branch and origin/$branch');
      }
      return;
    case 'copyBranch':
      return copy(branch, 'branch name');
    case 'copySha':
      return copy(sha, 'commit sha');
    case 'copyBranchLink':
      final url = gitBranchUrl(await state.git.remoteUrl(), branch);
      return url == null
          ? _toast(context, 'No remote URL configured.')
          : copy(url, 'branch link');
    case 'copyCommitLink':
      final url = gitCommitUrl(await state.git.remoteUrl(), sha);
      return url == null
          ? _toast(context, 'No remote URL configured.')
          : copy(url, 'commit link');
    case 'createPatch':
      return runRepoAction(context, () async {
        await state.git.formatPatch(sha);
      }, success: 'Patch written to repository folder');
    case 'cloudPatch':
      final patch = await state.git.commitPatchText(sha);
      Clipboard.setData(ClipboardData(text: patch));
      return _toast(context, 'Commit patch copied to clipboard');
    case 'applyPatch':
      final picked = await FilePicker.platform.pickFiles(
          dialogTitle: 'Select a patch file',
          type: FileType.custom,
          allowedExtensions: ['patch', 'diff']);
      final path = picked?.files.single.path;
      if (path != null && context.mounted) {
        return runRepoAction(context, () => state.applyPatchFile(path),
            success: 'Patch applied');
      }
      return;
    case 'pin':
      state.pinToLeft(sha);
      return _toast(context, 'Pinned ${commit.shortHash} to the left');
    case 'solo':
      state.soloCommit(sha);
      return _toast(context, 'Soloing ${commit.shortHash}');
    case 'tag':
      final name = await promptText(context,
          title: 'Create tag here', hint: 'tag name', confirm: 'Create');
      if (name != null && name.trim().isNotEmpty && context.mounted) {
        return runRepoAction(context, () => state.createTag(name.trim(), sha),
            success: 'Tagged ${commit.shortHash}');
      }
      return;
    case 'annotatedTag':
      final name = await promptText(context,
          title: 'Create annotated tag here',
          hint: 'tag name',
          confirm: 'Next');
      if (name == null || name.trim().isEmpty || !context.mounted) return;
      final msg = await promptText(context,
          title: 'Tag message', hint: 'annotation message', confirm: 'Create');
      if (msg != null && msg.trim().isNotEmpty && context.mounted) {
        return runRepoAction(
            context,
            () => state.createAnnotatedTag(name.trim(), msg.trim(), sha),
            success: 'Created annotated tag ${name.trim()}');
      }
      return;
    case 'compare':
      state.selectCommit(commit);
      return _toast(context, 'Showing commit details for ${commit.shortHash}');
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: AppColors.surfaceRaised,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 2),
  ));
}

Future<bool> _confirm(
    BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return ok == true;
}

