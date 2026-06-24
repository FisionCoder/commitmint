import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_state.dart';
import '../../theme/app_theme.dart';

/// Single-line text that ellipsizes, and shows a tooltip with the full content
/// (or [tooltipText]) ONLY when it actually overflows the available width.
class TruncatedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String? tooltipText;

  const TruncatedText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.tooltipText,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final effStyle =
          (style == null) ? DefaultTextStyle.of(context).style : style!;
      final tp = TextPainter(
        text: TextSpan(text: text, style: effStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
      )..layout(maxWidth: c.maxWidth);
      final overflows = tp.didExceedMaxLines;
      tp.dispose();

      final child = Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: style,
        textAlign: textAlign,
      );
      if (!overflows) return child;
      return Tooltip(message: tooltipText ?? text, child: child);
    });
  }
}

/// A vertical toolbar action: icon above a small label.
class ToolbarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? badge;

  const ToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.badge,
  });

  @override
  State<ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final showLabel = context.select<SettingsState, bool>(
        (s) => s.showToolbarLabels);
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: 10, vertical: showLabel ? 6 : 9),
          decoration: BoxDecoration(
            color: _hover && enabled
                ? AppColors.surfaceRaised
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(widget.icon,
                      size: 20,
                      color: enabled
                          ? (widget.color ?? AppColors.textSecondary)
                          : AppColors.textMuted),
                  if (widget.badge != null)
                    Positioned(right: -6, top: -4, child: widget.badge!),
                ],
              ),
              if (showLabel) ...[
                const SizedBox(height: 3),
                Text(widget.label,
                    style: TextStyle(
                        fontSize: 11,
                        color: enabled
                            ? AppColors.textSecondary
                            : AppColors.textMuted)),
              ],
            ],
          ),
        ),
      ),
    );
    // With labels hidden, surface the name as a tooltip instead.
    return showLabel ? button : Tooltip(message: widget.label, child: button);
  }
}

/// Small rounded badge pill used for ref labels and counts.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color? textColor;
  final IconData? icon;

  /// When true, hovering the pill shows its full text (useful when truncated).
  final bool tooltip;
  const Pill(this.text,
      {super.key,
      required this.color,
      this.textColor,
      this.icon,
      this.tooltip = false});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: textColor ?? color),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    color: textColor ?? color,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
    if (!tooltip) return pill;
    return Tooltip(message: text, child: pill);
  }
}

/// A collapsible sidebar section header (e.g. LOCAL, REMOTE).
class SidebarSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? count;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;
  final void Function(Offset globalPosition)? onSecondaryTap;

  const SidebarSection({
    super.key,
    required this.icon,
    required this.title,
    required this.expanded,
    required this.onToggle,
    this.count,
    this.children = const [],
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onSecondaryTapDown: onSecondaryTap == null
              ? null
              : (d) => onSecondaryTap!(d.globalPosition),
          child: InkWell(
          onTap: onToggle,
          hoverColor: AppColors.surfaceRaised,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: 2),
                Icon(icon, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: AppColors.textSecondary)),
                const Spacer(),
                if (count != null)
                  Text('$count',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
        ),
        if (expanded) ...children,
      ],
    );
  }
}

/// A dynamically generated, deterministic "8-bit" sprite avatar for a git
/// author. A symmetric pixel grid and colour are both derived from the
/// author's email/name, so each person gets a unique little character.
/// Hovering shows their name.
class UserAvatar extends StatelessWidget {
  final String name;
  final String email;
  final double size;
  final bool showTooltip;

  /// Overrides the auto-generated colour (e.g. an evenly-spaced palette colour
  /// so users are clearly distinct). The sprite shape still derives from the
  /// author hash unless [cells] is given.
  final Color? color;

  /// An explicit 7-row x 5-col on/off grid (a customised avatar). When null the
  /// grid is derived deterministically from the author's email/name.
  final List<List<bool>>? cells;

  const UserAvatar({
    super.key,
    required this.name,
    this.email = '',
    this.size = 18,
    this.showTooltip = true,
    this.color,
    this.cells,
  });

  String get _key =>
      (email.trim().isNotEmpty ? email : name).toLowerCase().trim();

  int get _hash {
    var h = 2166136261; // FNV-1a 32-bit
    final key = _key.isEmpty ? '?' : _key;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return h;
  }

  /// 5-wide x 7-tall horizontally-symmetric on/off grid (the "sprite").
  List<List<bool>> _grid(int hash) => gridFromHash(hash);

  /// FNV-1a hash of an author identity (email preferred, else name).
  static int hashFor(String name, String email) {
    var key = (email.trim().isNotEmpty ? email : name).toLowerCase().trim();
    if (key.isEmpty) key = '?';
    var h = 2166136261;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return h;
  }

  /// The deterministic symmetric sprite grid for a hash (used to seed the
  /// avatar editor from the current generated icon).
  static List<List<bool>> gridFromHash(int hash) {
    final g = List.generate(7, (_) => List<bool>.filled(5, false));
    var bit = 0;
    for (var r = 0; r < 7; r++) {
      for (var c = 0; c < 3; c++) {
        final on = ((hash >> (bit % 31)) & 1) == 1;
        g[r][c] = on;
        g[r][4 - c] = on; // mirror
        bit++;
      }
    }
    return g;
  }

  Color get _color {
    final hue = (_hash >> 8) % 360;
    // Vary saturation/lightness a little per author for more variety.
    final sat = 0.55 + ((_hash >> 4) & 0x7) / 20.0; // 0.55–0.90
    final light = 0.52 + ((_hash >> 1) & 0x3) / 25.0; // 0.52–0.64
    return HSLColor.fromAHSL(1, hue.toDouble(), sat.clamp(0.0, 1.0),
            light.clamp(0.0, 1.0))
        .toColor();
  }

  /// Up to two uppercase initials derived from the name (or email).
  String get _initials {
    final source = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (source.isEmpty) return '?';
    final words =
        source.split(RegExp(r'[\s@._-]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return source[0].toUpperCase();
    if (words.length == 1) return words.first[0].toUpperCase();
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hash = _hash;
    final radius = size * 0.3;
    final useInitials =
        context.watch<SettingsState>().useInitialsAvatars;
    final tile = color ?? _color;
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF242C38), Color(0xFF141921)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF3A434F), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 2.5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: useInitials
          ? Center(
              child: Text(_initials,
                  style: TextStyle(
                      fontSize: size * 0.42,
                      fontWeight: FontWeight.w700,
                      color: tile)),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(radius - 1),
              child: CustomPaint(
                painter: _SpritePainter(cells ?? _grid(hash), tile),
                size: Size.square(size),
              ),
            ),
    );
    if (!showTooltip) return avatar;
    final msg = email.trim().isNotEmpty && email.trim() != name.trim()
        ? '$name\n$email'
        : name;
    return Tooltip(
      message: msg.trim().isEmpty ? 'Unknown' : msg,
      child: avatar,
    );
  }
}

class _SpritePainter extends CustomPainter {
  final List<List<bool>> grid;
  final Color color;
  _SpritePainter(this.grid, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const cols = 5, rows = 7;
    // Inset so the sprite sits within the rounded tile, with square cells
    // sized by the taller (7-row) axis and centred horizontally.
    final pad = size.width * 0.12;
    final cell = (size.height - pad * 2) / rows;
    final offX = (size.width - cell * cols) / 2;
    final offY = pad;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (!grid[r][c]) continue;
        canvas.drawRect(
          Rect.fromLTWH(
              offX + c * cell, offY + r * cell, cell + 0.4, cell + 0.4),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) =>
      old.color != color || old.grid != grid;
}

/// A thin vertical splitter for resizing panel/column widths by horizontal drag.
class ResizeHandle extends StatefulWidget {
  final ValueChanged<double> onDelta; // drag delta in px (dx, or dy if vertical)
  final VoidCallback? onEnd;
  final double thickness;
  final bool vertical; // resize up/down instead of left/right
  const ResizeHandle(
      {super.key,
      required this.onDelta,
      this.onEnd,
      this.thickness = 6,
      this.vertical = false});

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hover || _dragging;
    final line = Container(
      width: widget.vertical ? double.infinity : (active ? 2 : 1),
      height: widget.vertical ? (active ? 2 : 1) : double.infinity,
      color: active ? AppColors.accent : AppColors.border,
    );
    return MouseRegion(
      cursor: widget.vertical
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart:
            widget.vertical ? null : (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate:
            widget.vertical ? null : (d) => widget.onDelta(d.delta.dx),
        onHorizontalDragEnd: widget.vertical
            ? null
            : (_) {
                setState(() => _dragging = false);
                widget.onEnd?.call();
              },
        onVerticalDragStart:
            widget.vertical ? (_) => setState(() => _dragging = true) : null,
        onVerticalDragUpdate:
            widget.vertical ? (d) => widget.onDelta(d.delta.dy) : null,
        onVerticalDragEnd: widget.vertical
            ? (_) {
                setState(() => _dragging = false);
                widget.onEnd?.call();
              }
            : null,
        child: widget.vertical
            ? SizedBox(height: widget.thickness, child: Center(child: line))
            : SizedBox(width: widget.thickness, child: Center(child: line)),
      ),
    );
  }
}

/// A flat icon button used in toolbars/headers.
class IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.color,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        hoverColor: AppColors.surfaceRaised,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon,
              size: size, color: color ?? AppColors.textSecondary),
        ),
      ),
    );
  }
}
