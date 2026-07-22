import 'dart:io';

import 'package:commit_mint/services/git_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the interactive-rebase engine end-to-end against real `git` in
/// throwaway repositories. Each commit touches a distinct file so reordering /
/// squashing never conflicts.
void main() {
  Future<void> run(String dir, List<String> args) async {
    final r = await Process.run('git', args,
        workingDirectory: dir, runInShell: Platform.isWindows);
    if (r.exitCode != 0) {
      throw Exception('git ${args.join(' ')} failed: ${r.stderr}');
    }
  }

  Future<String> out(String dir, List<String> args) async {
    final r = await Process.run('git', args,
        workingDirectory: dir, runInShell: Platform.isWindows);
    return (r.stdout as String).trim();
  }

  /// Creates a repo with commits whose subjects are [subjects] (oldest first),
  /// each adding a distinct file. Returns the repo path.
  Future<String> makeRepo(List<String> subjects) async {
    final dir = Directory.systemTemp
        .createTempSync('cm_irebase_test_')
        .path;
    await run(dir, ['init', '-b', 'main']);
    await run(dir, ['config', 'user.email', 't@t.t']);
    await run(dir, ['config', 'user.name', 'T']);
    await run(dir, ['config', 'commit.gpgsign', 'false']);
    for (var i = 0; i < subjects.length; i++) {
      File('$dir/f$i.txt').writeAsStringSync('content $i\n');
      await run(dir, ['add', '.']);
      await run(dir, ['commit', '-m', subjects[i]]);
    }
    return dir;
  }

  Future<List<String>> subjects(String dir) async {
    final s = await out(dir, ['log', '--reverse', '--format=%s']);
    return s.isEmpty ? [] : s.split('\n');
  }

  test('reword changes a commit message and keeps order/count', () async {
    final dir = await makeRepo(['C1', 'C2', 'C3']);
    final git = GitService(dir);
    final range = await git.rebaseRange(null); // all, oldest first
    expect(range.map((c) => c.subject).toList(), ['C1', 'C2', 'C3']);
    final plan = [
      RebaseStep(sha: range[0].hash, subject: 'C1', action: RebaseAction.pick),
      RebaseStep(
          sha: range[1].hash,
          subject: 'C2',
          action: RebaseAction.reword,
          newMessage: 'C2 reworded'),
      RebaseStep(sha: range[2].hash, subject: 'C3', action: RebaseAction.pick),
    ];
    await git.runInteractiveRebase(null, plan);
    expect(await subjects(dir), ['C1', 'C2 reworded', 'C3']);
  });

  test('drop removes a commit and its file', () async {
    final dir = await makeRepo(['C1', 'C2', 'C3']);
    final git = GitService(dir);
    final range = await git.rebaseRange(null);
    final plan = [
      RebaseStep(sha: range[0].hash, subject: 'C1', action: RebaseAction.pick),
      RebaseStep(sha: range[1].hash, subject: 'C2', action: RebaseAction.drop),
      RebaseStep(sha: range[2].hash, subject: 'C3', action: RebaseAction.pick),
    ];
    await git.runInteractiveRebase(null, plan);
    expect(await subjects(dir), ['C1', 'C3']);
    expect(File('$dir/f1.txt').existsSync(), false); // C2's file gone
    expect(File('$dir/f0.txt').existsSync(), true);
    expect(File('$dir/f2.txt').existsSync(), true);
  });

  test('squash folds a commit into the previous, merging messages', () async {
    final dir = await makeRepo(['C1', 'C2', 'C3']);
    final git = GitService(dir);
    final range = await git.rebaseRange(null);
    final plan = [
      RebaseStep(sha: range[0].hash, subject: 'C1', action: RebaseAction.pick),
      RebaseStep(sha: range[1].hash, subject: 'C2', action: RebaseAction.pick),
      RebaseStep(sha: range[2].hash, subject: 'C3', action: RebaseAction.squash),
    ];
    await git.runInteractiveRebase(null, plan);
    final subs = await subjects(dir);
    expect(subs.length, 2); // C1, and the squashed C2+C3
    // Both files still present (squash keeps the changes).
    expect(File('$dir/f1.txt').existsSync(), true);
    expect(File('$dir/f2.txt').existsSync(), true);
    // The combined commit's body contains both messages.
    final body = await out(dir, ['log', '-1', '--format=%B']);
    expect(body.contains('C2'), true);
    expect(body.contains('C3'), true);
  });

  test('fixup folds in without keeping the message', () async {
    final dir = await makeRepo(['C1', 'C2', 'C3']);
    final git = GitService(dir);
    final range = await git.rebaseRange(null);
    final plan = [
      RebaseStep(sha: range[0].hash, subject: 'C1', action: RebaseAction.pick),
      RebaseStep(sha: range[1].hash, subject: 'C2', action: RebaseAction.pick),
      RebaseStep(sha: range[2].hash, subject: 'C3', action: RebaseAction.fixup),
    ];
    await git.runInteractiveRebase(null, plan);
    final subs = await subjects(dir);
    expect(subs, ['C1', 'C2']); // C3's message dropped, folded into C2
    expect(File('$dir/f2.txt').existsSync(), true); // C3's changes kept
  });

  test('edit pauses the rebase; amend folds staged changes into the commit',
      () async {
    final dir = await makeRepo(['C1', 'C2', 'C3']);
    final git = GitService(dir);
    final range = await git.rebaseRange(null);
    final plan = [
      RebaseStep(sha: range[0].hash, subject: 'C1', action: RebaseAction.pick),
      RebaseStep(sha: range[1].hash, subject: 'C2', action: RebaseAction.edit),
      RebaseStep(sha: range[2].hash, subject: 'C3', action: RebaseAction.pick),
    ];
    // The `edit` stop pauses the rebase, so the call throws.
    try {
      await git.runInteractiveRebase(null, plan);
      fail('expected the rebase to pause at the edit stop');
    } catch (_) {}
    expect(await git.currentOperation(), GitOperation.rebase);

    // Amend the paused commit with a new staged file, then continue.
    File('$dir/extra.txt').writeAsStringSync('folded\n');
    await git.stageAll();
    await git.amendNoEdit();
    await git.continueOperation(GitOperation.rebase);

    expect(await git.currentOperation(), GitOperation.none);
    expect(await subjects(dir), ['C1', 'C2', 'C3']);
    // extra.txt is part of history (it was folded into C2).
    final inC2 = await out(dir, ['log', '-1', '--name-only', '--format=', 'HEAD~1']);
    expect(inC2.contains('extra.txt'), true);
  });

  test('reorder swaps commit order', () async {
    final dir = await makeRepo(['C1', 'C2', 'C3']);
    final git = GitService(dir);
    final range = await git.rebaseRange(null);
    // Put C2 first, then C1, then C3.
    final plan = [
      RebaseStep(sha: range[1].hash, subject: 'C2', action: RebaseAction.pick),
      RebaseStep(sha: range[0].hash, subject: 'C1', action: RebaseAction.pick),
      RebaseStep(sha: range[2].hash, subject: 'C3', action: RebaseAction.pick),
    ];
    await git.runInteractiveRebase(null, plan);
    expect(await subjects(dir), ['C2', 'C1', 'C3']);
  });
}
