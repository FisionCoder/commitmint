/// A single commit parsed from `git log`.
class GitCommit {
  final String hash;
  final String shortHash;
  final List<String> parents;
  final String author;
  final String authorEmail;
  final DateTime date;
  final String subject;
  final String body;

  /// Refs pointing at this commit (branches, tags, HEAD).
  final List<String> refs;

  /// True when this node represents a stash (WIP) entry rather than a real
  /// commit in branch history. Drawn with a dashed lane + tray icon.
  final bool isStash;

  /// For stash nodes, the `stash@{N}` index (so menu actions can target it).
  final int? stashIndex;

  // ---- Graph layout (assigned by the lane algorithm) ----
  int lane = 0;
  int color = 0;

  /// For each parent: the lane it occupies in the row immediately below.
  /// Used to draw the connecting edges.
  Map<String, int> parentLanes = {};

  /// Lanes that pass straight through this row without terminating here,
  /// recorded as (lane index -> color) so the painter can draw them.
  Map<int, int> passThrough = {};

  GitCommit({
    required this.hash,
    required this.parents,
    required this.author,
    required this.authorEmail,
    required this.date,
    required this.subject,
    required this.body,
    required this.refs,
    this.isStash = false,
    this.stashIndex,
  }) : shortHash = hash.length >= 7 ? hash.substring(0, 7) : hash;

  bool get isMerge => parents.length > 1;
}
