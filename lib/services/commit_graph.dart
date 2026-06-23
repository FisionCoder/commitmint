import '../models/git_commit.dart';

/// One lane (a vertical line) crossing a commit row.
class GraphLane {
  final int lane;
  final String hash;
  final int color;

  /// True when this lane belongs to a stash (WIP) branch — drawn dashed.
  final bool stash;
  const GraphLane(this.lane, this.hash, this.color, {this.stash = false});
}

/// Layout data for a single row of the commit graph.
class GraphRow {
  final GitCommit commit;
  final int dotLane;
  final int dotColor;

  /// Lines entering this row from the top (state above the dot).
  final List<GraphLane> incoming;

  /// Lines leaving this row at the bottom (state below the dot).
  final List<GraphLane> outgoing;

  GraphRow({
    required this.commit,
    required this.dotLane,
    required this.dotColor,
    required this.incoming,
    required this.outgoing,
  });

  int get maxLane {
    var m = dotLane;
    for (final l in incoming) {
      if (l.lane > m) m = l.lane;
    }
    for (final l in outgoing) {
      if (l.lane > m) m = l.lane;
    }
    return m;
  }
}

/// Assigns lanes/colors to a list of commits (must be in child-before-parent
/// order, e.g. from `git log --date-order`). Produces draw-ready rows.
class CommitGraph {
  /// [pinnedTip] forces that commit's branch into the leftmost lane (lane 0).
  static List<GraphRow> layout(List<GitCommit> commits, {String? pinnedTip}) {
    final rows = <GraphRow>[];
    final List<String?> active = []; // lane -> hash it is waiting for
    final List<int?> colorOf = []; // lane -> color
    final List<bool> stashLane = []; // lane -> belongs to a stash branch
    var colorCounter = 0;

    // Pre-seed lane 0 with the pinned branch tip so it stays leftmost.
    if (pinnedTip != null && commits.any((c) => c.hash == pinnedTip)) {
      active.add(pinnedTip);
      colorOf.add(colorCounter++);
      stashLane.add(false);
    }

    int firstFree() {
      for (var i = 0; i < active.length; i++) {
        if (active[i] == null) return i;
      }
      return active.length;
    }

    void ensure(int idx) {
      while (active.length <= idx) {
        active.add(null);
        colorOf.add(null);
        stashLane.add(false);
      }
    }

    List<GraphLane> snapshot() {
      final out = <GraphLane>[];
      for (var i = 0; i < active.length; i++) {
        if (active[i] != null) {
          out.add(GraphLane(i, active[i]!, colorOf[i]!, stash: stashLane[i]));
        }
      }
      return out;
    }

    for (final commit in commits) {
      final incoming = snapshot();

      var myLane = active.indexOf(commit.hash);
      int myColor;
      if (myLane == -1) {
        myLane = firstFree();
        ensure(myLane);
        myColor = colorCounter++;
      } else {
        myColor = colorOf[myLane]!;
      }

      // All lanes that were waiting for this commit collapse into the dot.
      for (var i = 0; i < active.length; i++) {
        if (active[i] == commit.hash) {
          active[i] = null;
          colorOf[i] = null;
          stashLane[i] = false;
        }
      }

      commit.lane = myLane;
      commit.color = myColor;
      commit.parentLanes = {};

      for (var pi = 0; pi < commit.parents.length; pi++) {
        final p = commit.parents[pi];
        final existing = active.indexOf(p);
        if (existing != -1) {
          commit.parentLanes[p] = existing;
          continue;
        }
        int laneForP;
        int colorForP;
        if (pi == 0 && myLane < active.length && active[myLane] == null) {
          laneForP = myLane;
          colorForP = myColor;
        } else if (pi == 0) {
          laneForP = firstFree();
          colorForP = myColor;
        } else {
          laneForP = firstFree();
          colorForP = colorCounter++;
        }
        ensure(laneForP);
        active[laneForP] = p;
        colorOf[laneForP] = colorForP;
        stashLane[laneForP] = commit.isStash;
        commit.parentLanes[p] = laneForP;
      }

      rows.add(GraphRow(
        commit: commit,
        dotLane: myLane,
        dotColor: myColor,
        incoming: incoming,
        outgoing: snapshot(),
      ));
    }
    return rows;
  }
}
