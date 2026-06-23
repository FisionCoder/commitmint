enum DiffLineType { context, addition, deletion, meta }

class DiffLine {
  final DiffLineType type;
  final String text; // line content without the +/-/space prefix
  final int? oldNo;
  final int? newNo;
  const DiffLine(this.type, this.text, this.oldNo, this.newNo);
}

class DiffHunk {
  final String header; // the "@@ ... @@" line
  final List<DiffLine> lines;
  final String rawText; // exact original hunk text (header + body), no trailing \n

  const DiffHunk({
    required this.header,
    required this.lines,
    required this.rawText,
  });
}

class FileDiff {
  final List<String> headerLines; // everything before the first hunk
  final List<DiffHunk> hunks;
  final bool isBinary;
  final bool isEmpty;

  const FileDiff({
    required this.headerLines,
    required this.hunks,
    this.isBinary = false,
    this.isEmpty = false,
  });

  /// Builds a minimal, applyable patch containing just [hunk].
  String patchFor(DiffHunk hunk) {
    final buffer = StringBuffer();
    for (final h in headerLines) {
      buffer.writeln(h);
    }
    buffer.write(hunk.rawText);
    if (!hunk.rawText.endsWith('\n')) buffer.write('\n');
    return buffer.toString();
  }
}

/// Parses the output of `git diff --no-color` for a single file.
class DiffParser {
  static FileDiff parse(String raw) {
    if (raw.trim().isEmpty) {
      return const FileDiff(headerLines: [], hunks: [], isEmpty: true);
    }
    final lines = raw.split('\n');
    final header = <String>[];
    final hunks = <DiffHunk>[];
    var binary = false;

    var i = 0;
    // Header: everything up to the first hunk marker.
    while (i < lines.length && !lines[i].startsWith('@@')) {
      if (lines[i].startsWith('Binary files') ||
          lines[i].startsWith('GIT binary patch')) {
        binary = true;
      }
      header.add(lines[i]);
      i++;
    }

    while (i < lines.length) {
      if (!lines[i].startsWith('@@')) {
        i++;
        continue;
      }
      final headerLine = lines[i];
      final (oldStart, newStart) = _parseHunkHeader(headerLine);
      final body = <DiffLine>[];
      final raw0 = <String>[headerLine];
      var oldNo = oldStart;
      var newNo = newStart;
      i++;
      while (i < lines.length && !lines[i].startsWith('@@')) {
        final l = lines[i];
        // Stop if a new file diff begins (multi-file safety).
        if (l.startsWith('diff --git')) break;
        raw0.add(l);
        if (l.startsWith('+')) {
          body.add(DiffLine(DiffLineType.addition, l.substring(1), null, newNo));
          newNo++;
        } else if (l.startsWith('-')) {
          body.add(DiffLine(DiffLineType.deletion, l.substring(1), oldNo, null));
          oldNo++;
        } else if (l.startsWith('\\')) {
          // "\ No newline at end of file"
          body.add(DiffLine(DiffLineType.meta, l.substring(1).trim(), null, null));
        } else {
          final text = l.isNotEmpty ? l.substring(1) : '';
          body.add(DiffLine(DiffLineType.context, text, oldNo, newNo));
          oldNo++;
          newNo++;
        }
        i++;
      }
      hunks.add(DiffHunk(
        header: headerLine,
        lines: body,
        rawText: raw0.join('\n'),
      ));
    }

    return FileDiff(headerLines: header, hunks: hunks, isBinary: binary);
  }

  /// Returns (oldStart, newStart) from a "@@ -a,b +c,d @@" header.
  static (int, int) _parseHunkHeader(String header) {
    final m = RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(header);
    if (m == null) return (1, 1);
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  /// Builds a synthetic all-addition diff for an untracked file's content.
  static FileDiff forNewFile(String path, String content) {
    final contentLines = content.split('\n');
    if (contentLines.isNotEmpty && contentLines.last.isEmpty) {
      contentLines.removeLast();
    }
    final body = <DiffLine>[];
    for (var i = 0; i < contentLines.length; i++) {
      body.add(DiffLine(DiffLineType.addition, contentLines[i], null, i + 1));
    }
    final hunk = DiffHunk(
      header: '@@ -0,0 +1,${contentLines.length} @@',
      lines: body,
      rawText: '',
    );
    return FileDiff(
      headerLines: ['--- /dev/null', '+++ b/$path'],
      hunks: body.isEmpty ? [] : [hunk],
    );
  }
}
