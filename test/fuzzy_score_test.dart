import 'package:commit_mint/ui/repo/command_palette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty query scores 0 (matches everything)', () {
    expect(fuzzyScore('', 'anything'), 0);
  });

  test('non-subsequence returns null', () {
    expect(fuzzyScore('xyz', 'feature/login'), isNull);
    expect(fuzzyScore('zzz', 'main'), isNull);
  });

  test('subsequence matches', () {
    expect(fuzzyScore('flogin', 'feature/login'), isNotNull);
    expect(fuzzyScore('main', 'main'), isNotNull);
  });

  test('contiguous / leading matches rank higher', () {
    final exact = fuzzyScore('main', 'main')!;
    final scattered = fuzzyScore('main', 'm-a-i-n')!;
    expect(exact, greaterThan(scattered));
  });

  test('shorter target preferred for equal matches', () {
    final short = fuzzyScore('dev', 'dev')!;
    final long = fuzzyScore('dev', 'development-branch')!;
    expect(short, greaterThan(long));
  });
}
