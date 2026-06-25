import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'repo_actions.dart';

class RepoToolbar extends StatelessWidget {
  const RepoToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RepoState>();

    final leftGroup = <Widget>[
      Flexible(
        child: _LabeledDropdown(
          label: 'repository',
          value: state.repo.name,
          icon: Icons.account_tree_outlined,
          items: const [],
          onSelected: (_) {},
        ),
      ),
      const SizedBox(width: 18),
      Flexible(
        child: _LabeledDropdown(
          label: 'branch',
          value: state.currentBranch,
          icon: Icons.call_split,
          items: state.localBranches.map((b) => b.name).toList(),
          onSelected: (b) => runRepoAction(
            context,
            () => state.checkout(b),
            success: 'Checked out $b',
          ),
        ),
      ),
      const SizedBox(width: 10),
      IconAction(
        icon: Icons.sync,
        tooltip: 'Fetch all',
        onTap: state.busy
            ? null
            : () => runRepoAction(context, state.fetch,
                success: 'Fetched from remotes'),
      ),
    ];

    final actions = <Widget>[
      if (state.busy)
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      const ToolbarButton(icon: Icons.undo, label: 'Undo'),
      const ToolbarButton(icon: Icons.redo, label: 'Redo'),
      _toolbarDivider(),
      ToolbarButton(
        icon: Icons.south,
        label: 'Pull',
        onTap: state.busy
            ? null
            : () =>
                runRepoAction(context, state.pull, success: 'Pull complete'),
      ),
      ToolbarButton(
        icon: Icons.north,
        label: 'Push',
        onTap: state.busy
            ? null
            : () =>
                runRepoAction(context, state.push, success: 'Push complete'),
      ),
      ToolbarButton(
        icon: Icons.call_split,
        label: 'Branch',
        onTap: state.busy
            ? null
            : () async {
                final name = await promptText(context,
                    title: 'New branch',
                    hint: 'branch name',
                    confirm: 'Create');
                if (name != null &&
                    name.trim().isNotEmpty &&
                    context.mounted) {
                  await runRepoAction(
                      context, () => state.createBranch(name.trim()),
                      success: 'Created $name');
                }
              },
      ),
      _toolbarDivider(),
      ToolbarButton(
        icon: Icons.inventory_2_outlined,
        label: 'Stash',
        onTap: state.busy
            ? null
            : () => runRepoAction(context, state.stashPush,
                success: 'Changes stashed'),
      ),
      ToolbarButton(
        icon: Icons.unarchive_outlined,
        label: 'Pop',
        onTap: state.busy || state.stashes.isEmpty
            ? null
            : () => runRepoAction(context, state.stashPop,
                success: 'Stash popped'),
      ),
      _toolbarDivider(),
      ToolbarButton(
        icon: Icons.terminal,
        label: 'Terminal',
        color: state.terminalVisible ? AppColors.accent : null,
        onTap: state.toggleTerminal,
      ),
    ];

    // Search is pinned to the far-right corner, outside the spread/scroll
    // logic below, so it stays in the corner at any width / DPI.
    final searchButton = ToolbarButton(
      icon: Icons.search,
      label: 'Search',
      color: state.searchVisible ? AppColors.accent : null,
      onTap: state.toggleSearch,
    );

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
        boxShadow: AppColors.elevation(y: 2, blur: 8, alpha: 0.16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              // Spread on wide toolbars; scroll horizontally when too narrow.
              if (c.maxWidth >= 820) {
                // Unwrap the Flexible dropdowns (ample room when wide) so the
                // Spacer is the only flex child and the actions sit flush to
                // the right, next to the pinned Search button.
                return Row(children: [
                  ...leftGroup.map((w) => w is Flexible ? w.child : w),
                  const Spacer(),
                  ...actions,
                ]);
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: c.maxWidth),
                  child: Row(
                    children: [
                      // Keep the left group from forcing overflow; let it size
                      // to content within the scrollable row.
                      ...leftGroup.map((w) => w is Flexible ? w.child : w),
                      const SizedBox(width: 24),
                      ...actions,
                    ],
                  ),
                ),
              );
            }),
          ),
          _toolbarDivider(),
          searchButton,
        ],
      ),
    );
  }

  Widget _toolbarDivider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: AppColors.border,
      );
}

class _LabeledDropdown extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final List<String> items;
  final ValueChanged<String> onSelected;

  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.icon,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label,
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        PopupMenuButton<String>(
          enabled: items.isNotEmpty,
          color: AppColors.surfaceRaised,
          offset: const Offset(0, 28),
          tooltip: '',
          itemBuilder: (_) => [
            for (final i in items)
              PopupMenuItem(
                value: i,
                height: 36,
                child: Row(
                  children: [
                    Icon(
                      i == value ? Icons.check : icon,
                      size: 14,
                      color: i == value
                          ? AppColors.green
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(i, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
          ],
          onSelected: onSelected,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Tooltip(
                  message: value,
                  child: Text(value,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
              ),
              if (items.isNotEmpty)
                Icon(Icons.arrow_drop_down,
                    size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ],
    );
  }
}
