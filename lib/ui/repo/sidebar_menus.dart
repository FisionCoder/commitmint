// Context here is the long-lived repo view; menu actions are safe to dispatch
// after the menu closes.
// ignore_for_file: use_build_context_synchronously
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/git_branch.dart';
import '../../models/git_commit.dart';
import '../../models/pull_request.dart';
import '../../services/git_service.dart';
import '../../state/layout_state.dart';
import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/notifier.dart';
import 'git_links.dart';
import 'repo_actions.dart';

RelativeRect _at(BuildContext context, Offset pos) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return RelativeRect.fromRect(
      pos & const Size(1, 1), Offset.zero & overlay.size);
}

PopupMenuItem<String> _item(String value, String label, {Color? color}) =>
    PopupMenuItem<String>(
      value: value,
      height: 38,
      child: Text(label,
          style: TextStyle(fontSize: 13.5, color: color ?? AppColors.textPrimary)),
    );

void _toast(BuildContext context, String msg) {
  notify(context, msg, duration: const Duration(seconds: 2));
}

Future<bool> _confirm(BuildContext context, String title, String body) async {
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

// ----------------------------------------------------- section header menu ---
Future<void> showSectionContextMenu(
  BuildContext context,
  RepoState state,
  LayoutState layout,
  SidebarSectionId section,
  Offset pos, {
  required VoidCallback onMaximize,
}) async {
  const labels = {
    SidebarSectionId.local: 'Local',
    SidebarSectionId.remote: 'Remote',
    SidebarSectionId.worktrees: 'Worktrees',
    SidebarSectionId.stashes: 'Stashes',
    SidebarSectionId.cloudPatches: 'Cloud Patches',
    SidebarSectionId.pullRequests: 'Pull Requests',
    SidebarSectionId.issues: 'Issues',
    SidebarSectionId.teams: 'Teams',
    SidebarSectionId.tags: 'Tags',
    SidebarSectionId.submodules: 'Submodules',
  };

  final isBranchSection =
      section == SidebarSectionId.local || section == SidebarSectionId.remote;
  final branchWord = section == SidebarSectionId.remote ? 'remote' : 'local';

  final sel = await showMenu<String>(
    context: context,
    color: AppColors.surfaceRaised,
    position: _at(context, pos),
    constraints: const BoxConstraints(minWidth: 240),
    items: [
      if (isBranchSection) ...[
        _item('hideAll', 'Hide all $branchWord branches'),
        _item('showAll', 'Show all $branchWord branches'),
        const PopupMenuDivider(),
      ],
      _item('maximize', 'Maximize this section'),
      const PopupMenuDivider(),
      for (final s in SidebarSectionId.values)
        CheckedPopupMenuItem<String>(
          value: 'sec:${s.name}',
          checked: layout.sectionVisible(s),
          padding: EdgeInsets.zero,
          child: Text(labels[s]!, style: const TextStyle(fontSize: 13.5)),
        ),
    ],
  );
  if (sel == null) return;
  if (sel == 'maximize') {
    onMaximize();
  } else if (sel == 'hideAll') {
    section == SidebarSectionId.remote
        ? state.hideAllRemote()
        : state.hideAllLocal();
  } else if (sel == 'showAll') {
    section == SidebarSectionId.remote
        ? state.showAllRemote()
        : state.showAllLocal();
  } else if (sel.startsWith('sec:')) {
    final name = sel.substring(4);
    final s = SidebarSectionId.values.firstWhere((e) => e.name == name);
    layout.toggleSection(s);
  }
}

// ------------------------------------------------------------- branch menu ---
Future<void> showBranchContextMenu(
  BuildContext context,
  RepoState state,
  GitRef branch,
  Offset pos,
) async {
  final isRemote = branch.kind == RefKind.remoteBranch;
  final ref = branch.name; // e.g. "foo" or "origin/foo"
  final shortName = branch.displayName; // strips remote prefix
  final current = state.currentBranch;
  final sha = branch.targetHash ?? ref;
  final remoteName = branch.remoteName ?? 'origin';

  final sel = await showMenu<String>(
    context: context,
    color: AppColors.surfaceRaised,
    position: _at(context, pos),
    constraints: const BoxConstraints(minWidth: 280),
    items: [
      _item('pull', 'Pull (fast-forward if possible)'),
      _item('push', 'Push'),
      _item('setUpstream', 'Set Upstream'),
      const PopupMenuDivider(),
      _item('merge', 'Merge $ref into $current'),
      _item('rebase', 'Rebase $current onto $ref'),
      _item('irebase', 'Interactive Rebase $current onto $ref'),
      const PopupMenuDivider(),
      _item('checkout', 'Checkout $ref'),
      const PopupMenuDivider(),
      _item('worktree', 'Create worktree from $ref'),
      const PopupMenuDivider(),
      _item('createBranch', 'Create branch here'),
      _item('cherry', 'Cherry pick commit'),
      _item('resetSoft', 'Reset $current to this commit (soft)'),
      _item('resetMixed', 'Reset $current to this commit (mixed)'),
      _item('resetHard', 'Reset $current to this commit (hard)',
          color: AppColors.red),
      _item('revert', 'Revert commit'),
      const PopupMenuDivider(),
      if (!isRemote) _item('rename', 'Rename $ref'),
      _item('delete', 'Delete $ref', color: AppColors.red),
      const PopupMenuDivider(),
      _item('copyName', 'Copy branch name'),
      _item('copySha', 'Copy commit sha'),
      _item('copyBranchLink', 'Copy link to branch: $ref'),
      _item('copyCommitLink', 'Copy link to this commit on remote: $remoteName'),
      const PopupMenuDivider(),
      _item('hide', 'Hide'),
      _item('pin', 'Pin to Left'),
      _item('solo', 'Solo'),
      const PopupMenuDivider(),
      _item('compare', 'Compare commit against working directory'),
      const PopupMenuDivider(),
      _item('tag', 'Create tag here'),
      _item('annotatedTag', 'Create annotated tag here'),
    ],
  );
  if (sel == null || !context.mounted) return;

  void copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    _toast(context, 'Copied $what');
  }

  switch (sel) {
    case 'pull':
      return runRepoAction(context, state.pull, success: 'Pull complete');
    case 'push':
      return runRepoAction(context, state.push, success: 'Push complete');
    case 'setUpstream':
      return runRepoAction(context, state.setUpstreamToTracking,
          success: 'Upstream set');
    case 'merge':
      return runRepoAction(context, () => state.merge(ref),
          success: 'Merged $ref into $current');
    case 'rebase':
      return runRepoAction(context, () => state.rebaseOnto(ref),
          success: 'Rebased onto $ref');
    case 'irebase':
      return runRepoAction(context, () => state.interactiveRebase(ref),
          success: 'Rebased onto $ref');
    case 'checkout':
      return runRepoAction(context, () => state.checkout(shortName),
          success: 'Checked out $shortName');
    case 'worktree':
      final parent = await FilePicker.platform
          .getDirectoryPath(dialogTitle: 'Choose a parent folder for the worktree');
      if (parent != null && context.mounted) {
        final name = shortName.replaceAll(RegExp(r'[\\/]'), '-');
        return runRepoAction(
            context, () => state.worktreeAdd('$parent/$name', ref),
            success: 'Worktree created');
      }
      return;
    case 'createBranch':
      final name = await promptText(context,
          title: 'Create branch here', hint: 'branch name', confirm: 'Create');
      if (name != null && name.trim().isNotEmpty && context.mounted) {
        return runRepoAction(
            context, () => state.createBranchAt(name.trim(), sha),
            success: 'Created ${name.trim()}');
      }
      return;
    case 'cherry':
      return runRepoAction(context, () => state.cherryPick(sha),
          success: 'Cherry-picked ${_short(sha)}');
    case 'resetSoft':
      return runRepoAction(context, () => state.resetTo(sha, 'soft'),
          success: 'Reset (soft)');
    case 'resetMixed':
      return runRepoAction(context, () => state.resetTo(sha, 'mixed'),
          success: 'Reset (mixed)');
    case 'resetHard':
      if (await _confirm(context, 'Reset $current (hard)?',
          'Discard all changes after this commit? This cannot be undone.')) {
        return runRepoAction(context, () => state.resetTo(sha, 'hard'),
            success: 'Reset (hard)');
      }
      return;
    case 'revert':
      return runRepoAction(context, () => state.revertCommit(sha),
          success: 'Reverted ${_short(sha)}');
    case 'rename':
      final name = await promptText(context,
          title: 'Rename $ref',
          hint: 'new branch name',
          initial: shortName,
          confirm: 'Rename');
      if (name != null && name.trim().isNotEmpty && context.mounted) {
        return runRepoAction(
            context, () => state.renameBranch(shortName, name.trim()),
            success: 'Renamed to ${name.trim()}');
      }
      return;
    case 'delete':
      if (await _confirm(context, 'Delete $ref?', 'Delete branch "$ref"?')) {
        return runRepoAction(
            context,
            () => isRemote
                ? state.deleteRemoteBranch(remoteName, shortName)
                : state.deleteBranch(shortName),
            success: 'Deleted $ref');
      }
      return;
    case 'copyName':
      return copy(ref, 'branch name');
    case 'copySha':
      return copy(sha, 'commit sha');
    case 'copyBranchLink':
      final url = gitBranchUrl(await state.git.remoteUrl(), shortName);
      return url == null
          ? _toast(context, 'No remote configured.')
          : copy(url, 'branch link');
    case 'copyCommitLink':
      final url = gitCommitUrl(await state.git.remoteUrl(), sha);
      return url == null
          ? _toast(context, 'No remote configured.')
          : copy(url, 'commit link');
    case 'hide':
      state.hideRef(branch);
      return _toast(context, 'Hidden $ref');
    case 'pin':
      state.pinToLeft(sha);
      return _toast(context, 'Pinned to the left');
    case 'solo':
      state.soloCommit(sha);
      return _toast(context, 'Soloing $ref');
    case 'compare':
      final commit = _findCommit(state, sha);
      if (commit != null) state.selectCommit(commit);
      return _toast(context, 'Showing ${_short(sha)}');
    case 'tag':
      final name = await promptText(context,
          title: 'Create tag here', hint: 'tag name', confirm: 'Create');
      if (name != null && name.trim().isNotEmpty && context.mounted) {
        return runRepoAction(context, () => state.createTag(name.trim(), sha),
            success: 'Tagged ${_short(sha)}');
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
            success: 'Created tag ${name.trim()}');
      }
      return;
  }
}

// -------------------------------------------------------------- stash menu ---
Future<void> showStashContextMenu(
  BuildContext context,
  RepoState state,
  GitRef stash,
  int index,
  Offset pos,
) async {
  final sel = await showMenu<String>(
    context: context,
    color: AppColors.surfaceRaised,
    position: _at(context, pos),
    constraints: const BoxConstraints(minWidth: 240),
    items: [
      _item('apply', 'Apply Stash'),
      _item('pop', 'Pop Stash'),
      _item('delete', 'Delete Stash', color: AppColors.red),
      const PopupMenuDivider(),
      _item('edit', 'Edit stash message'),
      const PopupMenuDivider(),
      _item('cloud', 'Share stash as Cloud Patch'),
      const PopupMenuDivider(),
      _item('hide', 'Hide'),
    ],
  );
  if (sel == null || !context.mounted) return;

  switch (sel) {
    case 'apply':
      return runRepoAction(context, () => state.stashApply(index),
          success: 'Stash applied');
    case 'pop':
      return runRepoAction(context, () => state.stashPopAt(index),
          success: 'Stash popped');
    case 'delete':
      if (await _confirm(context, 'Delete stash?',
          'Permanently delete this stash? This cannot be undone.')) {
        return runRepoAction(context, () => state.stashDrop(index),
            success: 'Stash deleted');
      }
      return;
    case 'edit':
      final msg = await promptText(context,
          title: 'Edit stash message',
          hint: 'stash message',
          confirm: 'Save');
      if (msg != null && msg.trim().isNotEmpty && context.mounted) {
        return runRepoAction(
            context, () => state.editStashMessage(index, msg.trim()),
            success: 'Stash message updated');
      }
      return;
    case 'cloud':
      final patch = await state.git.stashPatch(index);
      Clipboard.setData(ClipboardData(text: patch));
      return _toast(context, 'Stash patch copied to clipboard');
    case 'hide':
      state.hideStash(stash);
      return _toast(context, 'Stash hidden');
  }
}

// ------------------------------------------------------------ remote menu ---
Future<void> showRemoteContextMenu(
  BuildContext context,
  RepoState state,
  String remote,
  Offset pos,
) async {
  final sel = await showMenu<String>(
    context: context,
    color: AppColors.surfaceRaised,
    position: _at(context, pos),
    constraints: const BoxConstraints(minWidth: 220),
    items: [
      _item('add', 'Add remote…'),
      const PopupMenuDivider(),
      _item('rename', 'Rename "$remote"'),
      _item('seturl', 'Change URL…'),
      _item('remove', 'Remove "$remote"', color: AppColors.red),
    ],
  );
  if (sel == null || !context.mounted) return;

  switch (sel) {
    case 'add':
      return _addRemoteFlow(context, state);
    case 'rename':
      final name = await promptText(context,
          title: 'Rename remote',
          hint: 'new remote name',
          initial: remote,
          confirm: 'Rename');
      if (name != null && name.trim().isNotEmpty && context.mounted) {
        return runRepoAction(
            context, () => state.renameRemote(remote, name.trim()),
            success: 'Renamed remote to ${name.trim()}');
      }
      return;
    case 'seturl':
      final url = await promptText(context,
          title: 'Change URL for "$remote"',
          hint: 'https://… or git@…',
          initial: await state.git.remoteUrl(remote),
          confirm: 'Save');
      if (url != null && url.trim().isNotEmpty && context.mounted) {
        return runRepoAction(
            context, () => state.setRemoteUrl(remote, url.trim()),
            success: 'Updated URL for $remote');
      }
      return;
    case 'remove':
      if (await _confirm(context, 'Remove remote "$remote"?',
          'This removes the remote and its remote-tracking branches locally.')) {
        return runRepoAction(context, () => state.removeRemote(remote),
            success: 'Removed remote $remote');
      }
      return;
  }
}

Future<void> _addRemoteFlow(BuildContext context, RepoState state) async {
  final name = await promptText(context,
      title: 'Add remote', hint: 'remote name (e.g. upstream)', confirm: 'Next');
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  final url = await promptText(context,
      title: 'Add remote "${name.trim()}"',
      hint: 'https://… or git@…',
      confirm: 'Add');
  if (url != null && url.trim().isNotEmpty && context.mounted) {
    return runRepoAction(
        context, () => state.addRemote(name.trim(), url.trim()),
        success: 'Added remote ${name.trim()}');
  }
}

// --------------------------------------------------------- submodule menu ---
Future<void> showSubmoduleContextMenu(
  BuildContext context,
  RepoState state,
  GitSubmodule submodule,
  Offset pos,
) async {
  final sel = await showMenu<String>(
    context: context,
    color: AppColors.surfaceRaised,
    position: _at(context, pos),
    constraints: const BoxConstraints(minWidth: 240),
    items: [
      _item('update', 'Update (init & checkout)'),
      _item('sync', 'Sync URL from .gitmodules'),
      const PopupMenuDivider(),
      _item('copy', 'Copy path'),
    ],
  );
  if (sel == null || !context.mounted) return;

  switch (sel) {
    case 'update':
      return runRepoAction(context, state.submoduleUpdate,
          success: 'Submodules updated');
    case 'sync':
      return runRepoAction(context, state.submoduleSync,
          success: 'Submodule URLs synced');
    case 'copy':
      Clipboard.setData(ClipboardData(text: submodule.path));
      return _toast(context, 'Copied submodule path');
  }
}

// ---------------------------------------------------------- worktree menu ---
Future<void> showWorktreeContextMenu(
  BuildContext context,
  RepoState state,
  GitWorktree worktree,
  Offset pos,
) async {
  final sel = await showMenu<String>(
    context: context,
    color: AppColors.surfaceRaised,
    position: _at(context, pos),
    constraints: const BoxConstraints(minWidth: 240),
    items: [
      _item('copy', 'Copy path'),
      const PopupMenuDivider(),
      _item('prune', 'Prune stale worktrees'),
      if (!worktree.isMain)
        _item('remove', 'Remove worktree', color: AppColors.red),
    ],
  );
  if (sel == null || !context.mounted) return;

  switch (sel) {
    case 'copy':
      Clipboard.setData(ClipboardData(text: worktree.path));
      return _toast(context, 'Copied worktree path');
    case 'prune':
      return runRepoAction(context, state.worktreePrune,
          success: 'Pruned stale worktrees');
    case 'remove':
      if (await _confirm(context, 'Remove worktree?',
          'Remove the worktree at "${worktree.path}"? '
              'The folder and its checked-out files are deleted.')) {
        return runRepoAction(
            context, () => state.worktreeRemove(worktree.path, force: true),
            success: 'Worktree removed');
      }
      return;
  }
}

// --------------------------------------------------------------- tag menu ---
Future<void> showTagContextMenu(
  BuildContext context,
  RepoState state,
  GitRef tag,
  Offset pos,
) async {
  final name = tag.name;
  final sel = await showMenu<String>(
    context: context,
    color: AppColors.surfaceRaised,
    position: _at(context, pos),
    constraints: const BoxConstraints(minWidth: 240),
    items: [
      _item('push', 'Push tag to origin'),
      const PopupMenuDivider(),
      _item('copy', 'Copy tag name'),
      const PopupMenuDivider(),
      _item('delete', 'Delete tag', color: AppColors.red),
      _item('deleteRemote', 'Delete tag on origin', color: AppColors.red),
      const PopupMenuDivider(),
      _item('hide', 'Hide'),
    ],
  );
  if (sel == null || !context.mounted) return;

  switch (sel) {
    case 'push':
      return runRepoAction(context, () => state.pushTag(name),
          success: 'Pushed tag $name to origin');
    case 'copy':
      Clipboard.setData(ClipboardData(text: name));
      return _toast(context, 'Copied tag name');
    case 'delete':
      if (await _confirm(
          context, 'Delete tag?', 'Delete local tag "$name"?')) {
        return runRepoAction(context, () => state.deleteTag(name),
            success: 'Deleted tag $name');
      }
      return;
    case 'deleteRemote':
      if (await _confirm(context, 'Delete tag on origin?',
          'Delete the remote tag "origin/$name"?')) {
        return runRepoAction(context, () => state.deleteRemoteTag(name),
            success: 'Deleted origin tag $name');
      }
      return;
    case 'hide':
      state.hideRef(tag);
      return _toast(context, 'Tag hidden');
  }
}

// --------------------------------------------------- pull request menu ---
Future<void> showPullRequestContextMenu(
  BuildContext context,
  RepoState state,
  PullRequest pr,
  Offset pos,
) async {
  final sel = await showMenu<String>(
    context: context,
    color: AppColors.surfaceRaised,
    position: _at(context, pos),
    constraints: const BoxConstraints(minWidth: 280),
    items: [
      _item('view', 'View pull request #${pr.id} in browser'),
      _item('copy', 'Copy link for pull request #${pr.id}'),
      const PopupMenuDivider(),
      _item('checkout', 'Checkout origin/${pr.sourceBranch}'),
      _item('worktree', 'Create Worktree from Pull Request'),
      const PopupMenuDivider(),
      _item('approve', 'Approve pull request #${pr.id}'),
      _item('merge', 'Merge pull request #${pr.id}'),
      _item('squash', 'Squash & merge #${pr.id}'),
    ],
  );
  if (sel == null || !context.mounted) return;

  // Prefer the PR's own web URL (set by generic providers); fall back to a
  // URL derived from the remote (Azure and older entries).
  Future<String?> prUrl() async => pr.url.isNotEmpty
      ? pr.url
      : gitPrViewUrl(await state.git.remoteUrl(), pr.id);

  switch (sel) {
    case 'view':
      final url = await prUrl();
      if (url == null || !context.mounted) return;
      await GitService.openUrl(url);
      return _toast(context, 'Opening pull request #${pr.id}…');
    case 'copy':
      final url = await prUrl();
      if (url == null || !context.mounted) return;
      Clipboard.setData(ClipboardData(text: url));
      return _toast(context, 'Copied link for #${pr.id}');
    case 'approve':
      return runRepoAction(
          context, () => state.approvePullRequestById(pr.id),
          success: 'Approved pull request #${pr.id}');
    case 'merge':
    case 'squash':
      if (await _confirm(
          context,
          '${sel == 'squash' ? 'Squash & merge' : 'Merge'} #${pr.id}?',
          'Merge "${pr.title}" (${pr.sourceBranch} → ${pr.targetBranch}) '
              'on the remote?')) {
        return runRepoAction(
            context,
            () => state.mergePullRequestById(pr.id,
                method: sel == 'squash' ? 'squash' : 'merge'),
            success: 'Merged pull request #${pr.id}');
      }
      return;
    case 'checkout':
      return runRepoAction(context, () => state.checkout(pr.sourceBranch),
          success: 'Checked out ${pr.sourceBranch}');
    case 'worktree':
      final parent = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose a parent folder for the worktree');
      if (parent != null && context.mounted) {
        final name = pr.sourceBranch.replaceAll(RegExp(r'[\\/]'), '-');
        return runRepoAction(
            context, () => state.worktreeAdd('$parent/$name', pr.sourceBranch),
            success: 'Worktree created');
      }
      return;
  }
}

String _short(String sha) => sha.length >= 7 ? sha.substring(0, 7) : sha;

GitCommit? _findCommit(RepoState state, String sha) {
  for (final c in state.commits) {
    if (c.hash == sha) return c;
  }
  return null;
}
