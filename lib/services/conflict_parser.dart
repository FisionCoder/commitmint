// Parses a working-tree file containing Git conflict markers into ordered
// segments of plain text and conflict regions, and reassembles a resolved
// file from per-region choices — so the UI never has to show raw
// <<<<<<< / ======= / >>>>>>> markers.

/// How a single conflict region should be resolved.
enum ConflictChoice { unresolved, ours, theirs, both }

/// A conflicted span: the "ours" (current/HEAD) lines vs the "theirs"
/// (incoming) lines, plus the optional common ancestor (diff3 style).
class ConflictRegion {
  final List<String> ours;
  final List<String> theirs;
  final List<String> base;
  const ConflictRegion(
      {required this.ours, required this.theirs, this.base = const []});
}

/// One piece of a parsed file: either plain [text] lines, or a [region].
class ConflictSegment {
  final List<String>? text; // non-conflicting lines
  final ConflictRegion? region;
  const ConflictSegment.text(this.text) : region = null;
  const ConflictSegment.conflict(this.region) : text = null;
  bool get isConflict => region != null;
}

class ConflictDocument {
  final List<ConflictSegment> segments;
  final bool trailingNewline;
  const ConflictDocument(this.segments, {this.trailingNewline = true});

  int get conflictCount => segments.where((s) => s.isConflict).length;
  bool get hasConflicts => conflictCount > 0;

  /// Reassembles the file from [choices] (region index -> choice). Regions left
  /// [ConflictChoice.unresolved] are skipped if [skipUnresolved] is true,
  /// otherwise their "ours" side is used as a fallback.
  String resolve(List<ConflictChoice> choices, {bool skipUnresolved = false}) {
    final out = <String>[];
    var ci = 0;
    for (final seg in segments) {
      if (!seg.isConflict) {
        out.addAll(seg.text!);
        continue;
      }
      final r = seg.region!;
      final choice = ci < choices.length ? choices[ci] : ConflictChoice.unresolved;
      ci++;
      switch (choice) {
        case ConflictChoice.ours:
          out.addAll(r.ours);
          break;
        case ConflictChoice.theirs:
          out.addAll(r.theirs);
          break;
        case ConflictChoice.both:
          out..addAll(r.ours)..addAll(r.theirs);
          break;
        case ConflictChoice.unresolved:
          if (!skipUnresolved) out.addAll(r.ours);
          break;
      }
    }
    final joined = out.join('\n');
    return trailingNewline && joined.isNotEmpty ? '$joined\n' : joined;
  }
}

ConflictDocument parseConflicts(String content) {
  final trailingNewline = content.endsWith('\n');
  // Split into lines without keeping the trailing empty element.
  final lines = content.split('\n');
  if (trailingNewline && lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }

  final segments = <ConflictSegment>[];
  var common = <String>[];

  void flushCommon() {
    if (common.isNotEmpty) {
      segments.add(ConflictSegment.text(common));
      common = <String>[];
    }
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.startsWith('<<<<<<<')) {
      flushCommon();
      final ours = <String>[];
      final base = <String>[];
      final theirs = <String>[];
      i++;
      // ours until '|||||||' (diff3 base) or '======='
      while (i < lines.length &&
          !lines[i].startsWith('|||||||') &&
          !lines[i].startsWith('=======')) {
        ours.add(lines[i]);
        i++;
      }
      if (i < lines.length && lines[i].startsWith('|||||||')) {
        i++;
        while (i < lines.length && !lines[i].startsWith('=======')) {
          base.add(lines[i]);
          i++;
        }
      }
      // skip '======='
      if (i < lines.length && lines[i].startsWith('=======')) i++;
      while (i < lines.length && !lines[i].startsWith('>>>>>>>')) {
        theirs.add(lines[i]);
        i++;
      }
      // skip '>>>>>>>'
      if (i < lines.length && lines[i].startsWith('>>>>>>>')) i++;
      segments.add(ConflictSegment.conflict(
          ConflictRegion(ours: ours, theirs: theirs, base: base)));
    } else {
      common.add(line);
      i++;
    }
  }
  flushCommon();
  return ConflictDocument(segments, trailingNewline: trailingNewline);
}
