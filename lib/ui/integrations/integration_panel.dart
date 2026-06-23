import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/integration.dart';
import '../../services/integration_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../launchpad/launchpad_view.dart';
import 'repo_browser_dialog.dart';

/// Connect form + saved-instance list for any [ProviderType]. Adapts its
/// fields to the provider's auth scheme (token-only vs identity + secret) and
/// whether it hosts browsable repositories.
class IntegrationPanel extends StatefulWidget {
  final ProviderType provider;
  const IntegrationPanel({super.key, required this.provider});

  @override
  State<IntegrationPanel> createState() => _IntegrationPanelState();
}

class _IntegrationPanelState extends State<IntegrationPanel> {
  final _host = TextEditingController();
  final _principal = TextEditingController();
  final _secret = TextEditingController();
  final _hostFocus = FocusNode();

  bool _connecting = false;
  String? _error;

  ProviderType get _p => widget.provider;

  @override
  void dispose() {
    _host.dispose();
    _principal.dispose();
    _secret.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final app = context.read<AppState>();
    try {
      final result = await IntegrationService.connect(
        _p,
        _host.text,
        _principal.text,
        _secret.text,
      );
      final instance = Integration(
        id: LaunchpadView.genId(),
        provider: _p,
        host: result.host,
        principal: _p.authMode == AuthMode.principalSecret
            ? _principal.text.trim()
            : null,
        userName: result.displayName,
        addedAt: DateTime.now(),
      );
      await app.addIntegration(instance, _secret.text.trim());
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _host.clear();
        _principal.clear();
        _secret.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Connected to ${instance.title}'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final instances = app.integrationsOf(_p);

    return ListView(
      padding: const EdgeInsets.fromLTRB(48, 40, 48, 40),
      children: [
        Text(_p.label,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300)),
        const SizedBox(height: 28),
        _statusCard(instances.length),
        const SizedBox(height: 28),
        const Center(
          child: Text('or',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ),
        const SizedBox(height: 24),
        _connectForm(),
        if (instances.isNotEmpty) ...[
          const SizedBox(height: 40),
          Row(
            children: [
              const Text('Saved Connections',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${instances.length}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final inst in instances) _InstanceCard(instance: inst),
        ],
      ],
    );
  }

  Widget _statusCard(int count) {
    final connected = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: AppColors.surfaceRaised),
            child: Icon(connected ? Icons.check : Icons.person_outline,
                color: connected ? AppColors.green : AppColors.textMuted,
                size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Row(
              children: [
                Icon(connected ? Icons.check_circle : Icons.block,
                    size: 18,
                    color: connected ? AppColors.green : AppColors.red),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    connected
                        ? '$count connection${count == 1 ? '' : 's'}'
                        : 'Not Connected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        color: connected ? AppColors.green : AppColors.red),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _hostFocus.requestFocus(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.green,
              side: const BorderSide(color: AppColors.green),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text('Connect to ${_p.label}'),
          ),
        ],
      ),
    );
  }

  Widget _connectForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_p.needsHost) ...[
          _formRow(
            _p.hostLabel,
            TextField(
              controller: _host,
              focusNode: _hostFocus,
              decoration: InputDecoration(hintText: _p.hostHint),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_p.authMode == AuthMode.principalSecret) ...[
          _formRow(
            _p.principalLabel,
            TextField(
              controller: _principal,
              focusNode: _p.needsHost ? null : _hostFocus,
              decoration:
                  InputDecoration(hintText: 'Your ${_p.principalLabel}'),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _formRow(
          _p.secretLabel,
          TextField(
            controller: _secret,
            obscureText: true,
            decoration: InputDecoration(hintText: _p.secretLabel),
            onSubmitted: (_) => _connect(),
          ),
          help: _p.tokenHelp,
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.only(left: 180),
          child: Row(
            children: [
              SizedBox(
                height: 40,
                child: OutlinedButton(
                  onPressed: _connecting ? null : _connect,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.green,
                    side: const BorderSide(color: AppColors.green),
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                  ),
                  child: _connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Connect'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(width: 16),
                Flexible(
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.red)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _formRow(String label, Widget field, {String? help}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 180,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(label,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textPrimary)),
              ),
              if (help != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: help,
                  child: const Icon(Icons.help_outline,
                      size: 15, color: AppColors.accent),
                ),
              ],
              const SizedBox(width: 16),
            ],
          ),
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: field,
          ),
        ),
      ],
    );
  }
}

class _InstanceCard extends StatelessWidget {
  final Integration instance;
  const _InstanceCard({required this.instance});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final repoCount =
        app.repositories.where((r) => r.integrationId == instance.id).length;
    final hostsRepos = instance.provider.hostsRepositories;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentTeal.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.cloud_done_outlined,
                color: AppColors.accentTeal, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(instance.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  '${instance.host}'
                  '${instance.userName != null ? '  •  ${instance.userName}' : ''}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Added ${DateFormat('MMM d, yyyy').format(instance.addedAt)}'
                  '${hostsRepos && repoCount > 0 ? '  •  $repoCount repo${repoCount == 1 ? '' : 's'} cloned' : ''}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (hostsRepos)
            FilledButton.icon(
              onPressed: () => _browse(context, instance),
              icon: const Icon(Icons.folder_copy_outlined, size: 16),
              label: const Text('Browse repos'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('Issue tracking',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Remove connection',
            color: AppColors.textMuted,
            onPressed: () => _confirmRemove(context, app, instance),
          ),
        ],
      ),
    );
  }

  Future<void> _browse(BuildContext context, Integration inst) async {
    final app = context.read<AppState>();
    final secret = await app.secretFor(inst.id);
    if (secret == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Stored token not found — reconnect this instance.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => RepoBrowserDialog(instance: inst, secret: secret),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, AppState app, Integration inst) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remove connection?', style: TextStyle(fontSize: 16)),
        content: Text('Remove ${inst.title} and its stored token? '
            'Cloned repositories stay on disk.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) app.removeIntegration(inst);
  }
}
