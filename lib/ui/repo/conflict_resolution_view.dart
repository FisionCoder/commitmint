import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/conflict_parser.dart';
import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import 'repo_actions.dart';

const _mono = TextStyle(
    fontFamily: 'Consolas', fontFamilyFallback: ['monospace'], fontSize: 12.5);

const _oursColor = Color(0xFF4ADE80); // green — current (ours)
const _theirsColor = Color(0xFF60A5FA); // blue — incoming (theirs)

/// A user-friendly conflict editor: instead of raw `<<<<<<<` markers, each
/// conflict shows the **Current (ours)** and **Incoming (theirs)** sides with
/// "Use" buttons; the resolved file is reassembled and staged on Save.
class ConflictResolutionView extends StatefulWidget {
  const ConflictResolutionView({super.key});

  @override
  State<ConflictResolutionView> createState() => _ConflictResolutionViewState();
}

class _ConflictResolutionViewState extends State<ConflictResolutionView> {
  final ScrollController _scroll = ScrollController();
  ConflictDocument? _doc;
  List<ConflictChoice> _choices = [];
  List<GlobalKey> _keys = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final content = await context.read<RepoState>().loadOpenFileContent();
      final doc = parseConflicts(content);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _choices =
            List.filled(doc.conflictCount, ConflictChoice.unresolved);
        _keys = List.generate(doc.conflictCount, (_) => GlobalKey());
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int get _resolvedCount =>
      _choices.where((c) => c != ConflictChoice.unresolved).length;
  bool get _allResolved =>
      _doc != null && _resolvedCount == _doc!.conflictCount;

  void _jumpTo(int conflictIndex) {
    if (conflictIndex < 0 || conflictIndex >= _keys.length) return;
    final ctx = _keys[conflictIndex].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.1,
          curve: Curves.easeOut);
    }
  }

  void _save(BuildContext context) {
    final doc = _doc;
    if (doc == null) return;
    final content = doc.resolve(_choices);
    runRepoAction(context, () => context.read<RepoState>().saveResolvedFile(content),
        success: 'Conflict resolved');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<RepoState>();
    final path = state.openFile?.path ?? '';
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, path),
          const Divider(height: 1),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String path) {
    final n = _doc?.conflictCount ?? 0;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
          if (n > 0) ...[
            Text('$_resolvedCount / $n resolved',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(width: 6),
            _navButton(Icons.keyboard_arrow_up, () {
              final i = _choices.indexWhere((c) => c == ConflictChoice.unresolved);
              _jumpTo(i < 0 ? 0 : i);
            }),
            _navButton(Icons.keyboard_arrow_down, () {
              final i = _choices.indexWhere((c) => c == ConflictChoice.unresolved);
              _jumpTo(i < 0 ? n - 1 : i);
            }),
            const SizedBox(width: 10),
          ],
          FilledButton(
            onPressed: _allResolved ? () => _save(context) : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor: AppColors.surfaceRaised,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('Save resolution', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.textSecondary,
            tooltip: 'Close',
            onPressed: () => context.read<RepoState>().closeFileDetail(),
          ),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icon, size: 18, color: AppColors.textSecondary)),
      );

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
          child: Text('Could not load file:\n$_error',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary)));
    }
    final doc = _doc!;
    if (!doc.hasConflicts) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 30, color: AppColors.green),
            const SizedBox(height: 10),
            Text('No conflict markers found in this file.',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => runRepoAction(
                  context, () => context.read<RepoState>().markResolved(
                      context.read<RepoState>().openFile!),
                  success: 'Marked resolved'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('Mark resolved'),
            ),
          ],
        ),
      );
    }

    final children = <Widget>[];
    var ci = 0;
    for (final seg in doc.segments) {
      if (!seg.isConflict) {
        children.add(_commonBlock(seg.text!));
      } else {
        final idx = ci;
        children.add(KeyedSubtree(
            key: _keys[idx],
            child: _conflictCard(idx, seg.region!)));
        ci++;
      }
    }
    return Scrollbar(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        children: children,
      ),
    );
  }

  Widget _commonBlock(List<String> lines) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(lines.join('\n'),
          style: _mono.copyWith(color: AppColors.textSecondary)),
    );
  }

  Widget _conflictCard(int index, ConflictRegion r) {
    final choice = _choices[index];
    void choose(ConflictChoice c) => setState(() => _choices[index] = c);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: choice == ConflictChoice.unresolved
                ? AppColors.amber.withValues(alpha: 0.5)
                : AppColors.green.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Icon(
                    choice == ConflictChoice.unresolved
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle,
                    size: 14,
                    color: choice == ConflictChoice.unresolved
                        ? AppColors.amber
                        : AppColors.green),
                const SizedBox(width: 8),
                Text('Conflict ${index + 1}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const Spacer(),
                if (choice != ConflictChoice.unresolved)
                  TextButton(
                    onPressed: () => choose(ConflictChoice.unresolved),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28)),
                    child: const Text('Reset', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          // Ours | Theirs side by side.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _side(
                    label: 'Current (ours)',
                    color: _oursColor,
                    lines: r.ours,
                    selected: choice == ConflictChoice.ours ||
                        choice == ConflictChoice.both,
                    onUse: () => choose(ConflictChoice.ours),
                  ),
                ),
                Container(width: 1, color: AppColors.border),
                Expanded(
                  child: _side(
                    label: 'Incoming (theirs)',
                    color: _theirsColor,
                    lines: r.theirs,
                    selected: choice == ConflictChoice.theirs ||
                        choice == ConflictChoice.both,
                    onUse: () => choose(ConflictChoice.theirs),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                _chip('Use both', choice == ConflictChoice.both,
                    () => choose(ConflictChoice.both)),
                const Spacer(),
                Text(_choiceLabel(choice),
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _choiceLabel(ConflictChoice c) {
    switch (c) {
      case ConflictChoice.ours:
        return 'using current (ours)';
      case ConflictChoice.theirs:
        return 'using incoming (theirs)';
      case ConflictChoice.both:
        return 'using both (ours, then theirs)';
      case ConflictChoice.unresolved:
        return 'choose a side';
    }
  }

  Widget _side({
    required String label,
    required Color color,
    required List<String> lines,
    required bool selected,
    required VoidCallback onUse,
  }) {
    return Container(
      color: selected ? color.withValues(alpha: 0.10) : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: color.withValues(alpha: 0.12),
            child: Row(
              children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                _chip('Use', selected, onUse, accent: color),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: SelectableText(
              lines.isEmpty ? '(empty)' : lines.join('\n'),
              style: _mono.copyWith(
                  color: lines.isEmpty
                      ? AppColors.textMuted
                      : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color? accent}) {
    final c = accent ?? AppColors.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.22) : AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: selected ? c : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 12, color: c),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: selected ? c : AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
