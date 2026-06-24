import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/integration.dart';
import '../../state/app_state.dart';
import '../../state/layout_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'integration_panel.dart';

class IntegrationsView extends StatefulWidget {
  const IntegrationsView({super.key});

  @override
  State<IntegrationsView> createState() => _IntegrationsViewState();
}

class _IntegrationsViewState extends State<IntegrationsView> {
  ProviderType _selected = ProviderType.azureDevOps;

  IconData _iconFor(ProviderType p) {
    switch (p) {
      case ProviderType.github:
      case ProviderType.githubEnterprise:
        return Icons.hub_outlined;
      case ProviderType.gitlab:
      case ProviderType.gitlabSelfManaged:
        return Icons.merge_outlined;
      case ProviderType.bitbucket:
      case ProviderType.bitbucketDataCenter:
        return Icons.inventory_2_outlined;
      case ProviderType.azureDevOps:
        return Icons.cloud_sync_outlined;
      case ProviderType.jiraCloud:
      case ProviderType.jiraDataCenter:
        return Icons.dashboard_outlined;
      case ProviderType.trello:
        return Icons.view_kanban_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LayoutState>();
    return Row(
      children: [
        SizedBox(width: layout.providerRailWidth, child: _providerRail()),
        ResizeHandle(
          onDelta: (dx) =>
              layout.setProviderRailWidth(layout.providerRailWidth + dx),
          onEnd: layout.persist,
        ),
        Expanded(
          child: Container(
            color: AppColors.background,
            child: IntegrationPanel(
                key: ValueKey(_selected), provider: _selected),
          ),
        ),
      ],
    );
  }

  Widget _providerRail() {
    final app = context.watch<AppState>();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final p in ProviderType.values)
            _ProviderTile(
              icon: _iconFor(p),
              label: p.label,
              selected: _selected == p,
              badge: app.integrationsOf(p).isNotEmpty
                  ? app.integrationsOf(p).length
                  : null,
              onTap: () => setState(() => _selected = p),
            ),
        ],
      ),
    );
  }
}

class _ProviderTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;
  const _ProviderTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  State<_ProviderTile> createState() => _ProviderTileState();
}

class _ProviderTileState extends State<_ProviderTile> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: widget.selected
              ? AppColors.selection
              : (_hover ? AppColors.surfaceRaised : Colors.transparent),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              Icon(widget.icon,
                  size: 20,
                  color: widget.selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(widget.label,
                    style: TextStyle(
                        fontSize: 14,
                        color: widget.selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.normal)),
              ),
              if (widget.badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.accentTeal,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${widget.badge}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

