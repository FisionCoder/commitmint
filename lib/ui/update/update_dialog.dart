import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/notifier.dart';

/// Opens the update dialog. When [prefetched] is supplied (e.g. from the
/// silent startup check) the "Checking…" phase is skipped.
Future<void> showUpdateDialog(BuildContext context,
    {UpdateCheckResult? prefetched}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(prefetched: prefetched),
  );
}

enum _Phase { checking, upToDate, available, downloading, installing, error }

class _UpdateDialog extends StatefulWidget {
  final UpdateCheckResult? prefetched;
  const _UpdateDialog({this.prefetched});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  late _Phase _phase;
  String _current = '';
  UpdateInfo? _update;
  double _progress = -1;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final pre = widget.prefetched;
    if (pre != null) {
      _current = pre.currentVersion;
      _update = pre.update;
      _phase = pre.hasUpdate ? _Phase.available : _Phase.upToDate;
    } else {
      _phase = _Phase.checking;
      _check();
    }
  }

  Future<void> _check() async {
    try {
      final res = await UpdateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _current = res.currentVersion;
        _update = res.update;
        _phase = res.hasUpdate ? _Phase.available : _Phase.upToDate;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    final info = _update;
    if (info == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = -1;
    });
    try {
      final archive = await UpdateService.download(info, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() => _phase = _Phase.installing);
      // Hands off to the detached updater and exits this process; execution
      // does not return past this call on success.
      await UpdateService.applyAndRestart(archive);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _phase = _Phase.error;
      });
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '');
    return s.isEmpty ? 'Something went wrong.' : s;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Row(
        children: [
          Icon(Icons.system_update_alt, size: 20, color: AppColors.accent),
          const SizedBox(width: 10),
          const Text('Software Update', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(width: 440, child: _body()),
      actions: _actions(),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.checking:
        return _centered('Checking for updates…', spinner: true);
      case _Phase.upToDate:
        return _centered(
          "You're on the latest version"
          '${_current.isNotEmpty ? ' (v$_current)' : ''}.',
          icon: Icons.check_circle_outline,
          iconColor: AppColors.green,
        );
      case _Phase.error:
        return _centered(
          'Could not complete the update:\n$_error',
          icon: Icons.error_outline,
          iconColor: AppColors.red,
        );
      case _Phase.installing:
        return _centered(
          'Installing update…\nCommit Mint will restart automatically.',
          spinner: true,
        );
      case _Phase.downloading:
      case _Phase.available:
        return _updateDetails();
    }
  }

  Widget _updateDetails() {
    final info = _update!;
    final downloading = _phase == _Phase.downloading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            children: [
              const TextSpan(text: 'A new version is available: '),
              TextSpan(
                  text: 'v${info.version}',
                  style: TextStyle(
                      color: AppColors.accent, fontWeight: FontWeight.w600)),
              TextSpan(text: '   (you have v${info.currentVersion})'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (info.notes.trim().isNotEmpty) ...[
          Text("What's new",
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                info.notes.trim(),
                style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        GestureDetector(
          onTap: () => launchUrl(Uri.parse(info.htmlUrl),
              mode: LaunchMode.externalApplication),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text('View release on GitHub',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.accent,
                    decoration: TextDecoration.underline)),
          ),
        ),
        if (downloading) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _progress >= 0 ? _progress : null,
            backgroundColor: AppColors.background,
            color: AppColors.accent,
          ),
          const SizedBox(height: 6),
          Text(
            _progress >= 0
                ? 'Downloading… ${(_progress * 100).round()}%'
                : 'Downloading…',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _centered(String text, {IconData? icon, Color? iconColor, bool spinner = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        if (spinner)
          const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5))
        else if (icon != null)
          Icon(icon, size: 30, color: iconColor),
        const SizedBox(height: 14),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
      ],
    );
  }

  List<Widget> _actions() {
    switch (_phase) {
      case _Phase.checking:
      case _Phase.installing:
        return const [];
      case _Phase.downloading:
        return [
          TextButton(
            onPressed: null,
            child: Text('Downloading…',
                style: TextStyle(color: AppColors.textMuted)),
          ),
        ];
      case _Phase.upToDate:
      case _Phase.error:
        return [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ];
      case _Phase.available:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Later',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: _downloadAndInstall,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download & Install'),
          ),
        ];
    }
  }
}

/// Runs a silent update check and, if a newer version exists, opens the update
/// dialog. Errors are swallowed (startup should never be blocked by this).
Future<void> checkForUpdatesOnStartup(BuildContext context) async {
  if (!UpdateService.isSupported) return;
  try {
    final res = await UpdateService.checkForUpdate();
    if (!res.hasUpdate) return;
    if (!context.mounted) return;
    await showUpdateDialog(context, prefetched: res);
  } catch (_) {
    // Offline or rate-limited — stay quiet on startup.
  }
}

/// Entry point for the "Check for Updates…" menu item: always opens the dialog
/// (showing "up to date" or errors inline). [context] must be mounted.
Future<void> checkForUpdatesManually(BuildContext context) async {
  if (!UpdateService.isSupported) {
    notify(context, 'Auto-update is not available on this platform.');
    return;
  }
  await showUpdateDialog(context);
}
