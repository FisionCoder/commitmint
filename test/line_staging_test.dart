import 'dart:io';

import 'package:commit_mint/services/diff_parser.dart';
import 'package:commit_mint/services/git_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the line-level staging patch builder by applying its output with
/// real `git apply --cached` and checking what ended up staged vs. unstaged.
void main() {
  Future<void> run(String dir, List<String> args) async {
    final r = await Process.run('git', args,
        workingDirectory: dir, runInShell: Platform.isWindows);
    if (r.exitCode != 0) {
      throw Exception('git ${args.join(' ')} failed: ${r.stderr}');
    }
  }

  Future<String> makeRepo() async {
    final dir = Directory.systemTemp.createTempSync('cm_linestage_').path;
    await run(dir, ['init', '-b', 'main']);
    await run(dir, ['config', 'user.email', 't@t.t']);
    await run(dir, ['config', 'user.name', 'T']);
    await run(dir, ['config', 'core.autocrlf', 'false']);
    return dir;
  }

  test('stages only the selected added lines', () async {
    final dir = await makeRepo();
    // Base file with 3 lines committed.
    File('$dir/a.txt').writeAsStringSync('one\ntwo\nthree\n');
    await run(dir, ['add', '.']);
    await run(dir, ['commit', '-m', 'base']);
    // Add two new lines in the working tree.
    File('$dir/a.txt').writeAsStringSync('one\ntwo\nthree\nfour\nfive\n');

    final git = GitService(dir);
    final raw = await git.rawFileDiff('a.txt', staged: false);
    final diff = DiffParser.parse(raw);
    expect(diff.hunks.length, 1);
    final hunk = diff.hunks.first;
    // The two additions ("four", "five") are the addition-typed lines.
    final adds = [
      for (var i = 0; i < hunk.lines.length; i++)
        if (hunk.lines[i].type == DiffLineType.addition) i
    ];
    expect(adds.length, 2);

    // Stage only the first added line ("four").
    final patch = diff.patchForLines(hunk, {adds.first});
    expect(patch, isNotNull);
    await git.applyPatch(patch!, cached: true);

    // Staged diff should contain "four" but not "five".
    final staged = await git.rawFileDiff('a.txt', staged: true);
    expect(staged.contains('+four'), true);
    expect(staged.contains('+five'), false);
    // "five" remains unstaged.
    final unstaged = await git.rawFileDiff('a.txt', staged: false);
    expect(unstaged.contains('+five'), true);
  });

  test('stages only the selected deleted line, keeping the other', () async {
    final dir = await makeRepo();
    File('$dir/a.txt').writeAsStringSync('one\ntwo\nthree\nfour\n');
    await run(dir, ['add', '.']);
    await run(dir, ['commit', '-m', 'base']);
    // Delete "two" and "three" in the working tree.
    File('$dir/a.txt').writeAsStringSync('one\nfour\n');

    final git = GitService(dir);
    final diff = DiffParser.parse(await git.rawFileDiff('a.txt', staged: false));
    final hunk = diff.hunks.first;
    final dels = [
      for (var i = 0; i < hunk.lines.length; i++)
        if (hunk.lines[i].type == DiffLineType.deletion) i
    ];
    expect(dels.length, 2);

    // Stage only the first deletion ("two").
    final patch = diff.patchForLines(hunk, {dels.first});
    await git.applyPatch(patch!, cached: true);

    final staged = await git.rawFileDiff('a.txt', staged: true);
    expect(staged.contains('-two'), true);
    expect(staged.contains('-three'), false); // "three" still in the index
  });
}
