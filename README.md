# Commit Mint

A desktop Git client (Flutter, Windows) for managing repositories and commits, with
integrations for **Azure DevOps, GitHub, GitLab, Bitbucket, Jira and Trello**. The UI is modeled on a GitKraken-style
three-pane layout: branch sidebar, commit graph, and a changes/commit panel.

## Features

### Repository management
- **Tabbed repositories** — Launchpad + one tab per open repo, plus an Integrations tab.
- **Resizable layout** — drag the splitters between the branch sidebar, graph, and
  changes panel (and the integrations provider rail), and drag the commit-graph
  column edges (branch/tag, date). Sizes persist across restarts.
- **Column settings** — the cog in the graph header opens a menu to toggle each
  column (Branch/Tag, Graph, Commit message, Author, Date/Time, Sha), switch on
  Compact Graph Column / Smart Branch Visibility, or reset to the default/compact
  layout. All choices persist. Columns shrink to fit so the row never overflows.
- **Hover tooltips** — any truncated/ellipsized content (commit messages, dates,
  branch & ref labels, file paths, hunk headers, tab names, dropdowns) reveals its
  full value on hover.
- **Open** any local Git repository or **Clone** from a remote URL (Launchpad cards).
- **Commit graph** with a real multi-lane lane-assignment algorithm, colored lanes,
  merge nodes, branch/tag ref pills, commit messages and dates.
- **Branch sidebar** grouped into LOCAL / REMOTE / STASHES / TAGS with ahead/behind
  counts; click a branch to check it out; live filter.
- **Working changes panel** — unstaged/staged file lists, stage/unstage/discard,
  amend toggle, commit summary + description, and commit.
- **File diff & edit view** — click any changed file to open a detail pane with
  Diff View (line-numbered, red/green hunks, **Stage/Discard/Unstage Hunk** per
  hunk), File View (full content), an Unstaged/Staged toggle, and **Edit This
  File** for inline editing that saves back to the working tree.
- **Toolbar actions** — Fetch, Pull, Push, create Branch, Stash, Pop, branch switcher.
- **Author avatars** — each commit node shows a dynamically generated 8-bit
  "space-invader" sprite: a 5×7 symmetric pixel grid derived from the author's email
  on a modern rounded tile. Each author is assigned a distinct, **persisted** colour
  (golden-angle hue spacing) so it stays identical across sessions and repos. Hover
  to see the author's name (and email). The same sprite appears in commit details.
- **Session persistence** — open tabs (and the active tab) and author avatar colours
  are cached, so the app reopens exactly as you left it.
- **Commit details** — selecting a commit shows author, date, hash, and files changed.
- **Commit context menu** — right-click any commit. Hover **Checkout**, **Create
  worktree from**, and **Reset** to open cascading submenus. Every option is wired:
  pull/push/set-upstream, checkout (branch or detached), create worktree, create
  branch/tag (incl. annotated), reset (soft/mixed/hard), edit message (HEAD), revert,
  drop, **move commit down** (safe reorder, auto-restores on conflict), start a pull
  request (opens the host's PR page), rename/delete branch (local/remote/both),
  apply/create patch, copy sha / branch name / remote links, share patch to clipboard,
  and **Pin to Left / Solo** graph filters (with a clearable banner).

### Integrations
- Provider rail matching common services (GitHub, GitLab, Bitbucket, Azure DevOps,
  Jira, Trello). **Azure DevOps is fully implemented.**
- Connect with **Host Domain** (`dev.azure.com/org`) + **Personal Access Token**.
  The PAT is validated against the org's REST API on connect.
- **Saved Azure DevOps instances** are listed with their org, user, and date added.
- **Browse repos** on any saved instance to list the org's repositories and clone
  one directly (the stored PAT is injected into the HTTPS clone URL).

## Architecture

```
lib/
  models/        GitCommit, GitRef, FileChange, GitRepository, integration models
  services/      git_service (system git CLI), azure_devops_service (REST),
                 storage_service (prefs + secure token store), commit_graph (lanes)
  state/         AppState (tabs/repos/instances), RepoState (per-repo live state)
  ui/            home_shell, launchpad/, repo/ (toolbar, sidebar, graph, changes,
                 file detail/diff/edit), integrations/ (rail, Azure panel, browser)
  theme/         app_theme (dark palette)
```

- Local Git operations shell out to the system `git` executable (`git` must be on PATH).
- Azure DevOps uses the REST API (`/_apis/projects`, `/_apis/git/repositories`) with
  Basic auth (`:PAT`).
- PATs are stored via `flutter_secure_storage` (Windows DPAPI); repo/instance metadata
  in `shared_preferences`.

## Running

```bash
flutter pub get
flutter run -d windows      # or: flutter build windows
```

Requires Flutter 3.44+ and Git installed and on PATH.

## Notes
- Undo/Redo and Terminal toolbar buttons are placeholders.
- Non–Azure DevOps providers show an informational "not configured" panel.
