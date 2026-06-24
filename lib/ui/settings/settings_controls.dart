import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

const double _labelWidth = 240;
const double _controlMaxWidth = 420;

/// A label (right-aligned, fixed width) + a control, with an optional muted
/// hint beneath. Mirrors the GitKraken preferences row layout.
class SettingRow extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;
  const SettingRow({super.key, required this.label, required this.child, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 7, right: 16),
              child: Text(label,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _controlMaxWidth),
                  child: Align(alignment: Alignment.centerLeft, child: child),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: Text(hint!,
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: AppColors.textMuted)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 6),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: AppColors.border, height: 1)),
        ],
      ),
    );
  }
}

class CheckControl extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const CheckControl({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 30,
      child: Checkbox(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// A single-line text field bound to [value]. Calls [onChanged] live and
/// [onSubmit] when editing finishes (focus loss / Enter).
class TextFieldControl extends StatefulWidget {
  final String value;
  final String? hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmit;
  const TextFieldControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.onSubmit,
  });

  @override
  State<TextFieldControl> createState() => _TextFieldControlState();
}

class _TextFieldControlState extends State<TextFieldControl> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onSubmit?.call();
    });
  }

  @override
  void didUpdateWidget(TextFieldControl old) {
    super.didUpdateWidget(old);
    // Keep external changes in sync without disturbing the caret while typing.
    if (widget.value != _c.text && !_focus.hasFocus) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: _c,
        focusNode: _focus,
        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: widget.hintText),
        onChanged: widget.onChanged,
        onSubmitted: (_) => widget.onSubmit?.call(),
      ),
    );
  }
}

/// Integer field with min/max clamping and a [step].
class NumberField extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  const NumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999999,
    this.step = 1,
  });

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value.toString());
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  void _commit() {
    final v = int.tryParse(_c.text) ?? widget.value;
    final clamped = v.clamp(widget.min, widget.max);
    _c.text = clamped.toString();
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    if (widget.value.toString() != _c.text && !_focus.hasFocus) {
      _c.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      height: 34,
      child: TextField(
        controller: _c,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

class DropdownControl<T> extends StatelessWidget {
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  const DropdownControl({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.containsKey(value) ? value : items.keys.first,
          isDense: true,
          dropdownColor: AppColors.surfaceRaised,
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          icon: Icon(Icons.keyboard_arrow_down,
              size: 18, color: AppColors.textSecondary),
          items: [
            for (final e in items.entries)
              DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// A read-only path field with a Browse button. When [enabled] is false the
/// button is disabled and the value greys out.
class BrowseField extends StatelessWidget {
  final String value;
  final Future<void> Function() onPick;
  final bool enabled;
  const BrowseField(
      {super.key,
      required this.value,
      required this.onPick,
      this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButtonControl(
            label: 'Browse', onPressed: enabled ? onPick : null),
        const SizedBox(width: 10),
        Expanded(
          child: Text(value.isEmpty ? '—' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  color: enabled ? AppColors.textMuted : AppColors.borderSubtle)),
        ),
      ],
    );
  }
}

class OutlinedButtonControl extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const OutlinedButtonControl(
      {super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontSize: 12.5),
        ),
        child: Text(label),
      ),
    );
  }
}
