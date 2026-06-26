<div align="center">

# 🌿 Commit Mint

**A modern, cross‑platform desktop Git client built with Flutter.**

A GitKraken‑style three‑pane workspace — branch sidebar, commit graph, and a
changes/commit‑details panel — with provider integrations, a built‑in terminal,
light/dark themes, and a system‑tray mode.

[![Latest release](https://img.shields.io/github/v/release/FisionCoder/commitmint?label=latest&sort=semver)](https://github.com/FisionCoder/commitmint/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/FisionCoder/commitmint/total)](https://github.com/FisionCoder/commitmint/releases)

</div>

---

## ⬇️ Download

Grab the latest build — no installer required, just unzip and run.

| Platform | Download |
|----------|----------|
| 🪟 **Windows** (x64) | **[Download for Windows](https://github.com/FisionCoder/commitmint/releases/latest/download/CommitMint-Windows-x64.zip)** (`.zip`) |
| 🐧 **Linux** (x64) | **[Download for Linux](https://github.com/FisionCoder/commitmint/releases/latest/download/CommitMint-Linux-x64.tar.gz)** (`.tar.gz`) |

📦 All versions & release notes: **[github.com/FisionCoder/commitmint/releases](https://github.com/FisionCoder/commitmint/releases)**

> These direct links always point to the **newest release**.

### Install & run

**Windows**
1. Download and **unzip** `CommitMint-Windows-x64.zip`.
2. Run **`commit_mint.exe`**.
3. Windows SmartScreen may warn that the publisher is unknown (the build is
   unsigned) — click **More info → Run anyway**.

**Linux**
```bash
tar -xzf CommitMint-Linux-x64.tar.gz
cd CommitMint-Linux-x64        # the extracted bundle folder
./commit_mint
```
If a shared library is missing, install the runtime deps (most distros already
have them):
```bash
sudo apt install libgtk-3-0 libsecret-1-0 libayatana-appindicator3-1
```
`libsecret` + a keyring (e.g. `gnome-keyring`/Seahorse) is used to store access
tokens; `appindicator` enables the system‑tray icon.

> **Requirement (both platforms):** `git` must be installed and on your `PATH`.

---

## ✨ Features

### Workspace
- **Tabbed repositories** — a Home launchpad, one tab per open repo, and an
  Integrations tab. Tabs persist across restarts.
- **Three‑pane, fully resizable layout** — branch sidebar, commit graph, and a
  changes/commit‑details panel; drag the splitters and graph column edges. Sizes
  and column choices persist.
- **Commit graph** — real multi‑lane layout with coloured lanes, merge nodes and
  branch/tag pills. The current branch's HEAD is pinned to the leftmost lane and
  the WIP node links to it.
- **Branch sidebar** — LOCAL / REMOTE / STASHES / TAGS with ahead/behind counts.
  Branches with `/` in their name group into **collapsible folders**, and each
  remote is collapsible. Double‑click a branch pill in the graph to check it out.
- **Embedded terminal** — a real shell (PowerShell/cmd/Git Bash on Windows, your
  `$SHELL` on Linux) rooted at the repo, with configurable font/size/cursor.

### Working with commits
- **Working changes panel** — staged/unstaged lists with Path **and Tree** views,
  stage/unstage/discard, amend, commit summary + description, and commit.
- **Commit details** — author, date, hash, and a **Files Changed browser** with a
  Path/Tree toggle, collapsible folders with per‑folder counts, and expand/collapse.
- **File diff & edit** — per‑hunk stage/discard/unstage, full‑file view, and inline
  editing that saves back to the working tree.
- **Rich commit context menu** — checkout, create worktree/branch/tag, reset,
  revert, reorder, start a pull request, rename/delete branches, copy SHA/links,
  Pin/Solo graph filters, and more.

### Integrations (browser sign‑in + token)
GitHub, GitHub Enterprise, GitLab (+ self‑managed), Bitbucket (+ Data Center),
Azure DevOps, Jira (Cloud + Data Center) and Trello. **Connect to <provider>**
opens the provider's sign‑in/token page in your browser; paste the token to
connect. Browse and clone repositories from connected hosts.

### Personalisation & convenience
- **Light & dark themes** with a mint accent, switchable in Settings.
- **Settings** (cog / File → Settings / `Ctrl+,`) — General, Profiles, SSH,
  Integrations, UI Customization and In‑App Terminal.
- **Profiles** with **customisable pixel‑art icons** (editable grid + colour
  picker); a profile's icon shows on its own commits in the graph.
- **System‑tray mode** — minimizing or closing hides Commit Mint to the
  notification area; the tray icon restores it and offers Show / Quit (File →
  Exit fully quits).

---

## 🛠️ Build from source

Requires the **Flutter SDK 3.44+** and **Git** on your `PATH`.

```bash
git clone https://github.com/FisionCoder/commitmint.git
cd commitmint
flutter pub get

flutter run -d windows      # or: flutter build windows --release
flutter run -d linux        # or: flutter build linux   --release
```

Linux build dependencies:
```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  liblzma-dev libsecret-1-dev libayatana-appindicator3-dev
```

Release binaries are produced by GitHub Actions (`.github/workflows/release.yml`)
on every `v*` tag — it builds Windows + Linux and publishes them to a GitHub
Release.

## 🧱 Architecture

```
lib/
  models/     GitCommit, GitRef, FileChange, GitRepository, integration models
  services/   git_service (system git CLI), git_config_service, integration_service
              (provider REST), storage_service (prefs + secure tokens), commit_graph
  state/      AppState (tabs/repos/integrations), RepoState (per‑repo live state),
              LayoutState, SettingsState
  ui/         home_shell, launchpad/, repo/ (toolbar, sidebar, graph, changes,
              file detail/diff/edit, terminal), integrations/, settings/, widgets/
  theme/      app_theme (runtime light/dark palette)
```

Local Git operations shell out to the system `git`; provider APIs use REST over
`http`; tokens are kept in the OS secure store (DPAPI / libsecret).

## 📄 License

Licensed under the **Apache License 2.0** — see [LICENSE](LICENSE) and
[NOTICE](NOTICE). You're free to use, modify, and distribute it; the license
includes a patent grant and an "as is" warranty/liability disclaimer.
Third‑party dependencies are MIT/BSD‑licensed and retain their own notices.
