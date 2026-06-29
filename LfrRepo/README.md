# LfrRepo tools

A small set of shell functions for working with Liferay git repos scattered
across more than one root directory. `lfrRepo` jumps between clones without
typing full paths; `lfrWorktree` spins up a new worktree off `upstream/master`.

Both load via the top-level `lfrTools.sh` aggregator (see the repo's top-level
README). They are shell functions, so they must be sourced, not executed: a
script runs in a subshell and its `cd` would not reach your interactive shell.

## Contents

| File | Purpose |
|---|---|
| `lfr-repo.sh` | Defines the `lfrRepo` switcher and its tab-completion. |
| `lfr-worktree.sh` | Defines the `lfrWorktree` creator. |

The repo list, picker, and per-user config live in the shared module
`../LfrCommon/lfr-repo-list.sh` (config in `../LfrCommon/repos.local.conf`),
since `lfrCache` reuses the same picker.

## Setup

1. Source the top-level aggregator from your shell rc (it defines `lfrRepo`,
   `lfrWorktree`, and the other tools):

   ```bash
   source /path/to/liferay-tools/lfrTools.sh
   ```

2. Create your per-user config from the example and edit it (in `LfrCommon`):

   ```bash
   cp ../LfrCommon/repos.local.conf.example ../LfrCommon/repos.local.conf
   ```

   Set `LFR_REPO_ROOTS` (the directories scanned, in listing order),
   `LFR_REPO_PRIORITY` (name prefixes floated to the top of the picker), and the
   `LFR_WORKTREE_*` defaults. The file is gitignored, so your paths stay local.
   When it is missing, the scripts fall back to built-in defaults.

3. (Optional) Install `fzf` for the fuzzy picker. Without it, the numbered menu
   still works.

## Commands

### `lfrRepo`: jump between repos

Scans each directory in `LFR_REPO_ROOTS` for immediate subdirectories that
contain a `.git` entry, then `cd`s into the one you pick. When
[`fzf`](https://github.com/junegunn/fzf) is installed it drives an interactive
fuzzy picker; otherwise it falls back to a numbered `select` menu. Each entry
shows its root in parentheses, so repos that share a name across roots (such as
two `liferay-portal` clones) stay distinguishable.

| Invocation | Behavior |
|---|---|
| `lfrRepo` | Open the picker over every repo in all roots. |
| `lfrRepo <name>` | Jump straight to the only match; open the picker prefiltered by `<name>` when more than one matches. |
| `lfrRepo -l`, `lfrRepo --list` | List every repo and its root, without changing directory. |
| `lfrRepo <prefix><Tab>` | Tab-complete repo names. |

```bash
lfrRepo                 # pick interactively
lfrRepo portal          # filter to repos matching "portal"
lfrRepo -l              # just list, stay put
```

Repos whose names match a `LFR_REPO_PRIORITY` prefix float to the top of every
listing.

### `lfrWorktree`: create a worktree

Creates a new git worktree and branch, then `cd`s into it. Run it from inside
any `liferay-portal` clone. The worktree is created under `LFR_WORKTREE_ROOT`
as a sibling named `liferay-portal-<branch>`, branched off `LFR_WORKTREE_BASE`
(`upstream/master` by default). When the base ref is qualified as
`<remote>/<ref>`, that remote ref is fetched first so the branch starts current.

| Invocation | Behavior |
|---|---|
| `lfrWorktree <branch>` | Worktree + branch off `upstream/master` at `liferay-portal-<branch>`, then `cd` in. |
| `lfrWorktree <branch> <base-ref>` | Same, but branch off the given base ref instead. |

```bash
lfrWorktree LPD-12345                  # branch LPD-12345 off upstream/master
lfrWorktree LPD-12345 upstream/7.4.x   # branch off a different base
```

It refuses to run when no branch is given, when not inside a git repo, or when
the target directory already exists, leaving no half-made worktree behind.
Because the new directory is named `liferay-portal-*`, it shows up at the top
of `lfrRepo` alongside your other portal clones.

## Configuration

All settings live in `../LfrCommon/repos.local.conf` (gitignored; copy the
`.example`). The shared module sources it, and the `LFR_WORKTREE_*` values also
honor an environment override when the config does not set them.

| Variable | Default | Override via env? | Purpose |
|---|---|---|---|
| `LFR_REPO_ROOTS` | `$HOME/liferay/repos` | no | Directories scanned for repos, in listing order. |
| `LFR_REPO_PRIORITY` | `liferay-portal` | no | Name prefixes floated to the top of the picker, in order. |
| `LFR_WORKTREE_ROOT` | `$HOME/liferay/repos` | yes | Where new worktrees are created. |
| `LFR_WORKTREE_BASE` | `upstream/master` | yes | Default base ref for new branches. |
