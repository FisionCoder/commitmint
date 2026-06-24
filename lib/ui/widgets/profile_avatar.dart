import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_state.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// Renders a [GitProfile]'s avatar: the customised pixel icon when set,
/// otherwise the deterministic auto-generated sprite from the profile's email.
class ProfileAvatar extends StatelessWidget {
  final GitProfile profile;
  final double size;
  const ProfileAvatar({super.key, required this.profile, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final identity =
        profile.authorName.trim().isNotEmpty ? profile.authorName : profile.name;
    return UserAvatar(
      name: identity,
      email: profile.authorEmail,
      size: size,
      showTooltip: false,
      color: profile.avatarColor != null ? Color(profile.avatarColor!) : null,
      cells: profile.avatarGrid,
    );
  }
}

/// Renders a commit author's avatar. If the author's email matches a profile
/// with a customised icon, that custom icon is used; otherwise the usual
/// auto-generated sprite (tinted with [fallbackColor]) is shown.
class AuthorAvatar extends StatelessWidget {
  final String name;
  final String email;
  final double size;
  final Color? fallbackColor;
  final bool showTooltip;
  const AuthorAvatar({
    super.key,
    required this.name,
    required this.email,
    required this.size,
    this.fallbackColor,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsState>().profileForEmail(email);
    if (p != null && p.hasCustomAvatar) {
      return UserAvatar(
        name: name,
        email: email,
        size: size,
        showTooltip: showTooltip,
        color: p.avatarColor != null ? Color(p.avatarColor!) : fallbackColor,
        cells: p.avatarGrid,
      );
    }
    return UserAvatar(
      name: name,
      email: email,
      size: size,
      showTooltip: showTooltip,
      color: fallbackColor,
    );
  }
}

/// Swatches offered in the avatar editor's colour picker.
const List<Color> _swatches = [
  Color(0xFF2DD4BF), Color(0xFF34D399), Color(0xFF4ADE80), Color(0xFF60A5FA),
  Color(0xFF818CF8), Color(0xFFA78BFA), Color(0xFFF472B6), Color(0xFFFB7185),
  Color(0xFFFBBF24), Color(0xFFFB923C), Color(0xFF22D3EE), Color(0xFF94A3B8),
];

/// A self-contained colour picker: a saturation/value field, a hue slider and
/// a hex input. Returns the chosen colour, or null if cancelled.
Future<Color?> showColorPicker(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _ColorPickerDialog(initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _ColorPickerDialog({required this.initial});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hex = TextEditingController(text: _hexOf(widget.initial));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();
  static String _hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _setHsv(HSVColor v) {
    setState(() {
      _hsv = v;
      _hex.text = _hexOf(v.toColor());
    });
  }

  void _applyHex(String s) {
    var t = s.trim().replaceAll('#', '');
    if (t.length == 6) {
      final v = int.tryParse(t, radix: 16);
      if (v != null) _setHsv(HSVColor.fromColor(Color(0xFF000000 | v)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Custom Colour', style: TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Saturation / value field.
            SizedBox(
              height: 160,
              child: _SVField(hsv: _hsv, onChanged: _setHsv),
            ),
            const SizedBox(height: 14),
            // Hue slider.
            SizedBox(
              height: 22,
              child: _HueSlider(hue: _hsv.hue, onChanged: (h) => _setHsv(_hsv.withHue(h))),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: const InputDecoration(
                        prefixText: '', isDense: true, labelText: 'Hex'),
                    style: const TextStyle(fontSize: 13),
                    onChanged: _applyHex,
                    onSubmitted: _applyHex,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

/// Saturation (x) / value (y) selection square for the current hue.
class _SVField extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _SVField({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      void handle(Offset local) {
        final s = (local.dx / c.maxWidth).clamp(0.0, 1.0);
        final v = (1 - local.dy / c.maxHeight).clamp(0.0, 1.0);
        onChanged(hsv.withSaturation(s).withValue(v));
      }

      return GestureDetector(
        onPanDown: (d) => handle(d.localPosition),
        onPanUpdate: (d) => handle(d.localPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CustomPaint(
            painter: _SVPainter(hsv),
            size: Size(c.maxWidth, c.maxHeight),
          ),
        ),
      );
    });
  }
}

class _SVPainter extends CustomPainter {
  final HSVColor hsv;
  _SVPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Base hue → white horizontal, then black vertical overlay.
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [Colors.white, hueColor],
          ).createShader(rect));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
          ).createShader(rect));
    // Thumb.
    final cx = hsv.saturation * size.width;
    final cy = (1 - hsv.value) * size.height;
    canvas.drawCircle(
        Offset(cx, cy),
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
    canvas.drawCircle(
        Offset(cx, cy),
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black26);
  }

  @override
  bool shouldRepaint(covariant _SVPainter old) => old.hsv != hsv;
}

/// Horizontal hue slider (0–360).
class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueSlider({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      void handle(Offset local) =>
          onChanged((local.dx / c.maxWidth).clamp(0.0, 1.0) * 360);
      return GestureDetector(
        onPanDown: (d) => handle(d.localPosition),
        onPanUpdate: (d) => handle(d.localPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CustomPaint(
            painter: _HuePainter(hue),
            size: Size(c.maxWidth, c.maxHeight),
          ),
        ),
      );
    });
  }
}

class _HuePainter extends CustomPainter {
  final double hue;
  _HuePainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ]).createShader(rect));
    final x = (hue / 360) * size.width;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 3, 0, 6, size.height), const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _HuePainter old) => old.hue != hue;
}

/// Opens the customise-profile-icon dialog for [profile].
Future<void> showAvatarEditor(BuildContext context, GitProfile profile) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AvatarEditorDialog(profile: profile),
  );
}

class _AvatarEditorDialog extends StatefulWidget {
  final GitProfile profile;
  const _AvatarEditorDialog({required this.profile});

  @override
  State<_AvatarEditorDialog> createState() => _AvatarEditorDialogState();
}

class _AvatarEditorDialogState extends State<_AvatarEditorDialog> {
  late List<List<bool>> _grid;
  late Color _color;

  @override
  void initState() {
    super.initState();
    // Seed from the existing custom avatar, or the auto-generated one.
    final p = widget.profile;
    _grid = p.avatarGrid ??
        UserAvatar.gridFromHash(
            UserAvatar.hashFor(p.authorName.isNotEmpty ? p.authorName : p.name,
                p.authorEmail));
    // Deep copy so edits don't mutate the stored grid.
    _grid = _grid.map((r) => List<bool>.from(r)).toList();
    _color = p.avatarColor != null ? Color(p.avatarColor!) : _swatches.first;
  }

  void _toggle(int r, int c) => setState(() => _grid[r][c] = !_grid[r][c]);

  void _regenerate() {
    final rnd = Random();
    final g = List.generate(7, (_) => List<bool>.filled(5, false));
    for (var r = 0; r < 7; r++) {
      for (var c = 0; c < 3; c++) {
        final on = rnd.nextBool();
        g[r][c] = on;
        g[r][4 - c] = on;
      }
    }
    setState(() {
      _grid = g;
      _color = _swatches[rnd.nextInt(_swatches.length)];
    });
  }

  void _clear() =>
      setState(() => _grid = List.generate(7, (_) => List<bool>.filled(5, false)));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Customize Profile Icon', style: TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Preview + quick actions.
            Row(
              children: [
                _preview(),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Tap blocks to toggle them, pick a colour below, or '
                    'regenerate a random icon.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('COLOUR',
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _swatches) _swatch(s),
                _customSwatch(),
              ],
            ),
            const SizedBox(height: 18),
            Text('PIXELS',
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Center(child: _editorGrid()),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _regenerate,
                  icon: const Icon(Icons.casino_outlined, size: 16),
                  label: const Text('Regenerate'),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _clear, child: const Text('Clear')),
              ],
            ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: () {
            context
                .read<SettingsState>()
                .setProfileAvatar(widget.profile.id, _color.toARGB32(), _grid);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _preview() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF242C38), Color(0xFF141921)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3A434F)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: CustomPaint(painter: _PreviewPainter(_grid, _color)),
      ),
    );
  }

  Widget _swatch(Color c) {
    final selected = c.toARGB32() == _color.toARGB32();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _color = c),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: selected ? AppColors.textPrimary : Colors.transparent,
                width: 2),
          ),
          child: selected
              ? const Icon(Icons.check, size: 14, color: Colors.black)
              : null,
        ),
      ),
    );
  }

  /// Rainbow "custom colour" swatch — opens the full picker. Shows the current
  /// colour (with a check) when it isn't one of the presets.
  Widget _customSwatch() {
    final isPreset =
        _swatches.any((s) => s.toARGB32() == _color.toARGB32());
    final selected = !isPreset;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final picked = await showColorPicker(context, _color);
          if (picked != null) setState(() => _color = picked);
        },
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: selected ? _color : null,
            gradient: selected
                ? null
                : const SweepGradient(colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ]),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: selected ? AppColors.textPrimary : AppColors.border,
                width: selected ? 2 : 1),
          ),
          child: Icon(selected ? Icons.check : Icons.add,
              size: 14,
              color: selected ? Colors.black : Colors.white),
        ),
      ),
    );
  }

  Widget _editorGrid() {
    const cell = 26.0;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < 7; r++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var c = 0; c < 5; c++)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _toggle(r, c),
                      child: Container(
                        width: cell,
                        height: cell,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: _grid[r][c]
                              ? _color
                              : AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                              color: AppColors.borderSubtle, width: 0.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final List<List<bool>> grid;
  final Color color;
  _PreviewPainter(this.grid, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const cols = 5, rows = 7;
    final pad = size.width * 0.12;
    final c = (size.height - pad * 2) / rows;
    final offX = (size.width - c * cols) / 2;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (var r = 0; r < rows; r++) {
      for (var col = 0; col < cols; col++) {
        if (!grid[r][col]) continue;
        canvas.drawRect(
            Rect.fromLTWH(offX + col * c, pad + r * c, c + 0.4, c + 0.4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) =>
      old.color != color || old.grid != grid;
}
