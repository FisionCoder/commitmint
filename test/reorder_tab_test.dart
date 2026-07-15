import 'package:commit_mint/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  AppState makeApp() {
    final app = AppState();
    app.tabs = [
      const AppTab(TabKind.launchpad),
      AppTab(TabKind.repo, repoId: 'a'),
      AppTab(TabKind.repo, repoId: 'b'),
      AppTab(TabKind.repo, repoId: 'c'),
    ];
    app.activeTabIndex = 0;
    return app;
  }

  List<String?> ids(AppState app) => app.tabs.map((t) => t.repoId).toList();

  test('moves a tab to a later slot', () {
    final app = makeApp();
    app.reorderTab(1, 3); // move A to C's slot
    expect(ids(app), [null, 'b', 'c', 'a']);
  });

  test('moves a tab to an earlier slot', () {
    final app = makeApp();
    app.reorderTab(3, 1); // move C to A's slot
    expect(ids(app), [null, 'c', 'a', 'b']);
  });

  test('Home stays pinned: cannot be dragged', () {
    final app = makeApp();
    app.reorderTab(0, 2);
    expect(ids(app), [null, 'a', 'b', 'c']);
  });

  test('Home stays pinned: nothing can take index 0', () {
    final app = makeApp();
    app.reorderTab(3, 0); // dropping onto Home -> clamps to index 1
    expect(ids(app), [null, 'c', 'a', 'b']);
  });

  test('active tab follows its content after reorder', () {
    final app = makeApp();
    app.activeTabIndex = 1; // active = A
    app.reorderTab(3, 1); // C jumps ahead of A -> A shifts to index 2
    expect(app.activeTab.repoId, 'a');
    expect(app.activeTabIndex, 2);
  });

  test('no-op when from == to', () {
    final app = makeApp();
    app.reorderTab(2, 2);
    expect(ids(app), [null, 'a', 'b', 'c']);
  });
}
