import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_state.dart';
import '../../theme/app_theme.dart';

/// Shows a transient notification toast anchored to the corner chosen in
/// Settings → UI Customization → Notification Location. Used app-wide instead
/// of SnackBar so the location setting actually takes effect (SnackBar can only
/// anchor to the bottom).
void notify(BuildContext context, String message,
    {IconData? icon, Color? iconColor, Duration duration = const Duration(seconds: 3)}) {
  _Toaster.show(context, message, icon: icon, iconColor: iconColor, duration: duration);
}

class _ToastData {
  final String message;
  final IconData? icon;
  final Color? iconColor;
  final NotificationLocation location;
  OverlayEntry? entry;
  _ToastData(this.message, this.icon, this.iconColor, this.location);
}

class _Toaster {
  static final List<_ToastData> _active = [];

  static void show(BuildContext context, String message,
      {IconData? icon, Color? iconColor, required Duration duration}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final loc = context.read<SettingsState>().notificationLocation;
    final data = _ToastData(message, icon, iconColor, loc);
    final entry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        data: data,
        indexOf: () => _active.where((t) => t.location == data.location).toList().indexOf(data),
      ),
    );
    data.entry = entry;
    _active.add(data);
    overlay.insert(entry);
    Future.delayed(duration, () {
      data.entry?.remove();
      _active.remove(data);
      for (final t in _active) {
        t.entry?.markNeedsBuild();
      }
    });
  }
}

class _ToastWidget extends StatelessWidget {
  final _ToastData data;
  final int Function() indexOf;
  const _ToastWidget({required this.data, required this.indexOf});

  @override
  Widget build(BuildContext context) {
    const toastHeight = 50.0;
    const margin = 16.0;
    final idx = indexOf().clamp(0, 999);
    final offset = margin + idx * (toastHeight + 8);
    final loc = data.location;
    final top = loc == NotificationLocation.topLeft ||
        loc == NotificationLocation.topRight;
    final left = loc == NotificationLocation.topLeft ||
        loc == NotificationLocation.bottomLeft;

    final card = Material(
      color: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 160),
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset((left ? -1 : 1) * (1 - t) * 12, 0),
            child: child,
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (data.icon != null) ...[
                Icon(data.icon,
                    size: 18, color: data.iconColor ?? AppColors.accentTeal),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(data.message,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textPrimary)),
              ),
            ],
          ),
        ),
      ),
    );

    return Positioned(
      top: top ? offset : null,
      bottom: top ? null : offset,
      left: left ? margin : null,
      right: left ? null : margin,
      child: card,
    );
  }
}
