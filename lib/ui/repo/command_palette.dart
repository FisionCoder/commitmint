import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_screen.dart';
import 'repo_actions.dart';

/// Subsequence fuzzy score of [query] against [text] (case-insensitive).
/// Returns null when [query] isn't a subsequence; higher is a better match,
/// rewarding contiguous and leading matches and shorter targets.
int? fuzzyScore(String query, String text) {
  final q = query.toLowerCase().trim();
  final t = text.toLowerCase();
  if (q.isEmpty) return 0;
  var ti = 0;
  var score = 0;
  var streak = 0;
  for (var qi = 0; qi < q.length; qi++) {
    final c = q.codeUnitAt(qi);
    var found = -1;
    for (var k = ti; k < t.length; k++) {
      if (t.codeUnitAt(k) == c) {
        found = k;
        break;
      }
    }
    if (found == -1) return null;
    if (found == ti) {
      streak++;
      score += 6 + streak;
    } else {
      streak = 0;
      score += 1;
    }
    ti = found + 1;
  }
  score += ((80 - t.length).clamp(0, 80)) ~/ 8; // prefer shorter targets
  return score;
}

class _Entry {
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback run;
  const _Entry(
      {required this.icon, required this.label, this.sub, required this.run});
  String get haystack => sub == null ? label : '$label $sub';
}

/// Opens the command palette (Ctrl+P): fuzzy quick-open over branches, commits
/// and common actions for [state].
Future<void> showCommandPalette(BuildContext context, RepoState state) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CommandPalette(outer: context, state: state),
  );
}

class _CommandPalette extends StatefulWidget {
  final BuildContext outer;
  final RepoState state;
  const _CommandPalette({required this.outer, required this.state});

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  String _query = '';
  int _sel = 0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<_Entry> _allEntries() {
    final s = widget.state;
    final ctx = widget.outer;
    final entries = <_Entry>[
      _Entry(
          icon: Icons.download,
          label: 'Fetch all',
          run: () =>
              runRepoAction(ctx, s.fetch, success: 'Fetched from remotes')),
      _Entry(
          icon: Icons.south,
          label: 'Pull',
          run: () => runRepoAction(ctx, s.pull, success: 'Pull complete')),
      _Entry(
          icon: Icons.north,
          label: 'Push',
          run: () => runRepoAction(ctx, s.push, success: 'Push complete')),
      _Entry(
          icon: Icons.inventory_2_outlined,
          label: 'Stash changes',
          run: () => stashWithOptions(ctx, s)),
      _Entry(
          icon: Icons.terminal,
          label: 'Toggle terminal',
          run: s.toggleTerminal),
      _Entry(
          icon: Icons.settings_outlined,
          label: 'Open settings',
          run: () => openSettings(ctx)),
    ];
    for (final b in s.localBranches) {
      entries.add(_Entry(
        icon: Icons.call_split,
        label: b.name,
        sub: 'local branch',
        run: () => runRepoAction(ctx, () => s.checkout(b.name),
            success: 'Checked out ${b.name}'),
      ));
    }
    for (final b in s.remoteBranches) {
      entries.add(_Entry(
        icon: Icons.cloud_outlined,
        label: b.displayName,
        sub: 'remote branch',
        run: () => runRepoAction(ctx, () => s.checkout(b.displayName),
            success: 'Checked out ${b.displayName}'),
      ));
    }
    for (final t in s.tags) {
      entries.add(_Entry(icon: Icons.sell_outlined, label: t.name, sub: 'tag',
          run: () {}));
    }
    for (final c in s.commits) {
      if (c.subject.isEmpty) continue;
      entries.add(_Entry(
        icon: Icons.commit,
        label: c.subject,
        sub: c.shortHash,
        run: () => s.selectCommit(c),
      ));
    }
    return entries;
  }

  List<_Entry> _filtered(List<_Entry> all) {
    if (_query.trim().isEmpty) return all.take(60).toList();
    final scored = <(int, _Entry)>[];
    for (final e in all) {
      final sc = fuzzyScore(_query, e.haystack);
      if (sc != null) scored.add((sc, e));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final s in scored.take(60)) s.$2];
  }

  void _run(List<_Entry> results) {
    if (results.isEmpty) return;
    final e = results[_sel.clamp(0, results.length - 1)];
    Navigator.of(context).pop();
    e.run();
  }

  KeyEventResult _onKey(List<_Entry> results, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _sel = (_sel + 1).clamp(0, results.length - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _sel = (_sel - 1).clamp(0, results.length - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _run(results);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered(_allEntries());
    if (_sel >= results.length) _sel = results.isEmpty ? 0 : results.length - 1;
    return Dialog(
      backgroundColor: AppColors.surface,
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 90, left: 40, right: 40),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 560,
        child: Focus(
          onKeyEvent: (_, e) => _onKey(results, e),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _sel = 0;
                  }),
                  onSubmitted: (_) => _run(results),
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Jump to a branch, commit, or action…',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('No matches',
                            style: TextStyle(color: AppColors.textMuted)),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final e = results[i];
                          final selected = i == _sel;
                          return InkWell(
                            onTap: () {
                              setState(() => _sel = i);
                              _run(results);
                            },
                            child: Container(
                              color: selected
                                  ? AppColors.selection
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 9),
                              child: Row(
                                children: [
                                  Icon(e.icon,
                                      size: 15, color: AppColors.textMuted),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(e.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textPrimary)),
                                  ),
                                  if (e.sub != null)
                                    Text(e.sub!,
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
