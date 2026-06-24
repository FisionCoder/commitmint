import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../models/git_repository.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import '../theme/app_theme.dart';
import 'integrations/integrations_view.dart';
import 'launchpad/launchpad_view.dart';
import 'repo/repo_view.dart';
import 'widgets/common.dart';
import 'widgets/mint_leaf.dart';

// --------------------------------------------------------- View actions ----
/// Toggles the OS window between full screen and normal.
Future<void> toggleFullScreen() async {
  final fs = await windowManager.isFullScreen();
  await windowManager.setFullScreen(!fs);
}

/// Toggles the embedded terminal of the active repository tab (no-op if the
/// active tab isn't a repository).
void toggleActiveTerminal(BuildContext context) {
  final app = context.read<AppState>();
  final tab = app.activeTab;
  if (tab.kind == TabKind.repo && tab.repoId != null) {
    app.repoState(tab.repoId!).toggleTerminal();
  }
}

/// Toggles the commit search/filter on the active repository tab (Ctrl+F):
/// opens it if hidden, dismisses it if already showing.
void toggleCommitSearch(BuildContext context) {
  final app = context.read<AppState>();
  final tab = app.activeTab;
  if (tab.kind == TabKind.repo && tab.repoId != null) {
    app.repoState(tab.repoId!).toggleSearch();
  }
}

/// Toggles the branch filter on the active repository tab (Ctrl+Alt+F): focuses
/// it (expanding the sidebar first) when inactive; clears and blurs it when it
/// already has focus.
void toggleBranchFilter(BuildContext context) {
  final app = context.read<AppState>();
  final layout = context.read<LayoutState>();
  final tab = app.activeTab;
  if (tab.kind != TabKind.repo || tab.repoId == null) return;
  final repo = app.repoState(tab.repoId!);
  if (repo.branchFilterFocus.hasFocus) {
    repo.clearBranchFilter();
    repo.branchFilterFocus.unfocus();
    return;
  }
  if (layout.sidebarCollapsed) layout.toggleSidebarCollapsed();
  WidgetsBinding.instance.addPostFrameCallback(
      (_) => repo.branchFilterFocus.requestFocus());
}

bool _activeTerminalVisible(BuildContext context) {
  final app = context.read<AppState>();
  final tab = app.activeTab;
  if (tab.kind == TabKind.repo && tab.repoId != null) {
    return app.repoState(tab.repoId!).terminalVisible;
  }
  return false;
}

/// A quick-switcher listing all open tabs (View → Tabs → Open Tabs List).
Future<void> showTabsList(BuildContext context) async {
  final app = context.read<AppState>();
  await showDialog<void>(
    context: context,
    builder: (ctx) => SimpleDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Open Tabs', style: TextStyle(fontSize: 15)),
      children: [
        for (var i = 0; i < app.tabs.length; i++)
          ListTile(
            dense: true,
            selected: i == app.activeTabIndex,
            selectedTileColor: AppColors.selection,
            leading: Text('${i + 1}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted)),
            title: Text(app.tabTitle(app.tabs[i]),
                style: const TextStyle(fontSize: 13)),
            onTap: () {
              app.selectTab(i);
              Navigator.pop(ctx);
            },
          ),
      ],
    ),
  );
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return CallbackShortcuts(
      bindings: _shortcuts(context, app),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              const _MenuBar(),
              const _TabStrip(),
              Expanded(child: _buildBody(context, app)),
            ],
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(
      BuildContext context, AppState app) {
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    return {
      const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
          toggleFullScreen,
      const SingleActivator(LogicalKeyboardKey.tab, control: true):
          app.selectNextTab,
      const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
          app.selectPreviousTab,
      const SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true):
          () => showTabsList(context),
      const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () =>
          context.read<LayoutState>().toggleSidebarCollapsed(),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
          context.read<LayoutState>().toggleChangesPanel(),
      const SingleActivator(LogicalKeyboardKey.backquote, control: true): () =>
          toggleActiveTerminal(context),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
          toggleCommitSearch(context),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true, alt: true):
          () => toggleBranchFilter(context),
      for (var n = 0; n < 9; n++)
        SingleActivator(digits[n], control: true): () =>
            app.selectTabNumber(n + 1),
    };
  }

  Widget _buildBody(BuildContext context, AppState app) {
    final tab = app.activeTab;
    switch (tab.kind) {
      case TabKind.launchpad:
        return const LaunchpadView();
      case TabKind.integrations:
        return const IntegrationsView();
      case TabKind.repo:
        final state = app.repoState(tab.repoId!);
        return ChangeNotifierProvider.value(
          value: state,
          key: ValueKey(tab.repoId),
          child: const RepoView(),
        );
    }
  }
}

class _MenuBar extends StatefulWidget {
  const _MenuBar();
  @override
  State<_MenuBar> createState() => _MenuBarState();
}

class _MenuBarState extends State<_MenuBar> {
  final MenuController _edit = MenuController();
  final MenuController _view = MenuController();

  /// Click: toggle this menu (closing any other first).
  void _toggle(MenuController c) {
    if (c.isOpen) {
      c.close();
      return;
    }
    _edit.close();
    _view.close();
    c.open();
  }

  /// Hover: while one of the menus is already open, switch to the hovered one.
  void _hover(MenuController c) {
    if (c.isOpen) return;
    if (!_edit.isOpen && !_view.isOpen) return;
    _edit.close();
    _view.close();
    c.open();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      color: AppColors.titleBar,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const _StaticMenuLabel('File'),
          _EditMenu(
              controller: _edit,
              onTap: () => _toggle(_edit),
              onHover: () => _hover(_edit)),
          _ViewMenu(
              controller: _view,
              onTap: () => _toggle(_view),
              onHover: () => _hover(_view)),
          const Spacer(),
          const MintLeafLogo(size: 16),
          const SizedBox(width: 7),
          const Text('Commit Mint',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

class _StaticMenuLabel extends StatelessWidget {
  final String label;
  const _StaticMenuLabel(this.label);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(label,
          style:
              const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
    );
  }
}

const _viewMenuStyle = MenuStyle(
  backgroundColor: WidgetStatePropertyAll(AppColors.surfaceRaised),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
);

class _ViewMenu extends StatefulWidget {
  final MenuController controller;
  final VoidCallback onTap;
  final VoidCallback onHover;
  const _ViewMenu(
      {required this.controller, required this.onTap, required this.onHover});
  @override
  State<_ViewMenu> createState() => _ViewMenuState();
}

class _ViewMenuState extends State<_ViewMenu> {
  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LayoutState>();
    final app = context.watch<AppState>();
    final repoActive = app.activeTab.kind == TabKind.repo;
    final termVisible = _activeTerminalVisible(context);
    final tabCount = app.tabs.length;

    return MenuAnchor(
      controller: widget.controller,
      onOpen: () {
        if (mounted) setState(() {}); // refresh checkmarks on open
      },
      style: _viewMenuStyle,
      menuChildren: [
        _viewItem('Toggle Full Screen', 'Ctrl+Shift+F',
            onPressed: toggleFullScreen),
        SubmenuButton(
          menuStyle: _viewMenuStyle,
          menuChildren: [
            _viewItem('Select Next Tab', 'Ctrl+Tab',
                onPressed: tabCount > 1 ? app.selectNextTab : null),
            _viewItem('Select Previous Tab', 'Ctrl+Shift+Tab',
                onPressed: tabCount > 1 ? app.selectPreviousTab : null),
            _viewItem('Open Tabs List', 'Ctrl+Shift+A',
                onPressed: () => showTabsList(context)),
            for (var n = 1; n <= 9; n++)
              _viewItem('Select Tab $n', 'Ctrl+$n',
                  onPressed:
                      n <= tabCount ? () => app.selectTabNumber(n) : null),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: Text('Tabs', style: TextStyle(fontSize: 13)),
          ),
        ),
        _viewItem('Show Left Panel', 'Ctrl+J',
            checked: !layout.sidebarCollapsed,
            onPressed: layout.toggleSidebarCollapsed),
        _viewItem('Show Commit Details Panel', 'Ctrl+K',
            checked: layout.changesPanelVisible,
            onPressed: layout.toggleChangesPanel),
        _viewItem('Show Terminal Panel', 'Ctrl+`',
            checked: termVisible,
            onPressed:
                repoActive ? () => toggleActiveTerminal(context) : null),
      ],
      builder: (context, controller, child) => _MenuBarButton(
        label: 'View',
        onTap: widget.onTap,
        onHover: widget.onHover,
      ),
    );
  }

  Widget _viewItem(String label, String shortcut,
      {VoidCallback? onPressed, bool? checked}) {
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: checked == null
          ? null
          : SizedBox(
              width: 18,
              child: checked
                  ? const Icon(Icons.check, size: 15, color: AppColors.accent)
                  : null,
            ),
      trailingIcon: shortcut.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(shortcut,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted)),
            ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

/// The Edit menu — standard text-editing commands dispatched to the input that
/// was focused before the menu opened (the keys themselves are handled by
/// Flutter's default text-editing shortcuts).
class _EditMenu extends StatefulWidget {
  final MenuController controller;
  final VoidCallback onTap;
  final VoidCallback onHover;
  const _EditMenu(
      {required this.controller, required this.onTap, required this.onHover});
  @override
  State<_EditMenu> createState() => _EditMenuState();
}

class _EditMenuState extends State<_EditMenu> {
  FocusNode? _lastEditable;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_trackFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_trackFocus);
    super.dispose();
  }

  /// Remember the most recently focused text field, so the Edit commands target
  /// it regardless of how the menu was opened (click or hover-switch).
  void _trackFocus() {
    final n = FocusManager.instance.primaryFocus;
    if (n != null &&
        n.context?.findAncestorStateOfType<EditableTextState>() != null) {
      _lastEditable = n;
    }
  }

  void _run(Intent intent) {
    final node = _lastEditable;
    if (node == null || node.context == null) return;
    // Restore focus to the editable, then dispatch once it's settled.
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx != null) Actions.maybeInvoke<Intent>(ctx, intent);
    });
  }

  Widget _item(String label, String shortcut, Intent intent) {
    return MenuItemButton(
      onPressed: () => _run(intent),
      trailingIcon: Padding(
        padding: const EdgeInsets.only(left: 24),
        child: Text(shortcut,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: widget.controller,
      style: _viewMenuStyle,
      menuChildren: [
        _item('Undo', 'Ctrl+Z',
            const UndoTextIntent(SelectionChangedCause.keyboard)),
        _item('Redo', 'Ctrl+Y',
            const RedoTextIntent(SelectionChangedCause.keyboard)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Divider(height: 1, color: AppColors.border),
        ),
        _item('Cut', 'Ctrl+X',
            const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard)),
        _item('Copy', 'Ctrl+C', CopySelectionTextIntent.copy),
        _item('Paste', 'Ctrl+V',
            const PasteTextIntent(SelectionChangedCause.keyboard)),
        _item('Select All', 'Ctrl+A',
            const SelectAllTextIntent(SelectionChangedCause.keyboard)),
      ],
      builder: (context, controller, child) => _MenuBarButton(
        label: 'Edit',
        onTap: widget.onTap,
        onHover: widget.onHover,
      ),
    );
  }
}

class _MenuBarButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onHover;
  const _MenuBarButton({required this.label, required this.onTap, this.onHover});
  @override
  State<_MenuBarButton> createState() => _MenuBarButtonState();
}

class _MenuBarButtonState extends State<_MenuBarButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hover = true);
        widget.onHover?.call();
      },
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(widget.label,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary)),
        ),
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: AppColors.titleBar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < app.tabs.length; i++)
                    _Tab(index: i, tab: app.tabs[i]),
                  _AddTabButton(),
                ],
              ),
            ),
          ),
          IconAction(
            icon: Icons.extension_outlined,
            tooltip: 'Integrations',
            onTap: () => app.openIntegrations(),
          ),
          const SizedBox(width: 4),
          const IconAction(
              icon: Icons.notifications_none, tooltip: 'Notifications'),
          const IconAction(icon: Icons.settings_outlined, tooltip: 'Settings'),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final int index;
  final AppTab tab;
  const _Tab({required this.index, required this.tab});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final active = app.activeTabIndex == index;

    String title;
    IconData icon;
    String tooltip;
    switch (tab.kind) {
      case TabKind.launchpad:
        title = 'Home';
        tooltip = title;
        icon = Icons.home_outlined;
        break;
      case TabKind.integrations:
        title = 'Integrations';
        tooltip = title;
        icon = Icons.extension_outlined;
        break;
      case TabKind.repo:
        final repo = app.repositories.firstWhere(
          (r) => r.id == tab.repoId,
          orElse: () => const GitRepository(id: '', name: '?', path: ''),
        );
        title = repo.name;
        tooltip = '${repo.name}\n${repo.path}';
        icon = Icons.account_tree_outlined;
        break;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: () => app.selectTab(index),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.only(left: 14, right: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          border: Border(
            top: BorderSide(
                color: active ? AppColors.accent : Colors.transparent,
                width: 2),
            right: const BorderSide(color: AppColors.borderSubtle),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? AppColors.textPrimary : AppColors.textMuted),
            const SizedBox(width: 8),
            Flexible(
              child: Tooltip(
                message: tooltip,
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 13,
                        color: active
                            ? AppColors.textPrimary
                            : AppColors.textSecondary)),
              ),
            ),
            const SizedBox(width: 8),
            if (tab.kind != TabKind.launchpad)
              InkWell(
                onTap: () => app.closeTab(index),
                borderRadius: BorderRadius.circular(3),
                child: const Icon(Icons.close,
                    size: 13, color: AppColors.textMuted),
              )
            else
              const SizedBox(width: 13),
          ],
        ),
      ),
      ),
    );
  }
}

class _AddTabButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return PopupMenuButton<String>(
      tooltip: 'Open',
      color: AppColors.surfaceRaised,
      offset: const Offset(0, 36),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'open', child: Text('Open local repository…')),
        PopupMenuItem(value: 'clone', child: Text('Clone repository…')),
        PopupMenuItem(value: 'integrations', child: Text('Integrations…')),
      ],
      onSelected: (v) {
        if (v == 'integrations') {
          app.openIntegrations();
        } else {
          // Both open/clone live on the Launchpad.
          app.selectTab(0);
        }
      },
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Icon(Icons.add, size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}
