# LfrCache

Lets several repos and worktrees share a single Gradle build cache, so you do
not burn CPU compiling the same modules twice. Build master once with the cache
on and it stores every module's output; the other repos and worktrees then reuse
that output for anything they did not change, and only recompile their own diff.
You decide which repos/worktrees take part by toggling each one on or off.

It is loaded as a shell function (`lfrCache`) through the root aggregator
`/path/to/liferay-tools/lfrTools.sh`, alongside the other tools.

## How it works

`init.d/lfr-build-cache.gradle` is a Gradle init script. Gradle only auto-applies
init scripts from `~/.gradle/init.d`, so `lfrCache install` copies it there. On
every Gradle build it reads `enabled-repos.txt`; if the build's directory is
under a listed repo path, it turns the build cache on for that build. Unlisted
builds are left untouched. The cache itself is the shared default
(`~/.gradle/caches/build-cache-1`), so all enabled repos and worktrees share it.

Only the Gradle (module) layer is cached. The `ant compile` portal core step
(portal-impl, portal-kernel) is not a Gradle task and is never cached.

## Setup

Source the root aggregator once (it loads this and every other tool):

```bash
source /path/to/liferay-tools/lfrTools.sh
```

Then install the Gradle init script once:

```bash
lfrCache install
```

## Typical flow

```bash
# 1. Enable the cache on master and build it fully to seed the cache.
lfrCache on ~/liferay/repos/liferay-portal
cd ~/liferay/repos/liferay-portal && ant all

# 2. Enable it on each worktree. Their builds now reuse master's cached output
#    and only recompile the modules they changed.
lfrCache on ~/liferay/repos/liferay-portal-7.4.x

# 3. Turn it off for a repo whenever you want a fully cold build.
lfrCache off ~/liferay/repos/liferay-portal-7.4.x
```

## Commands

Run with no path argument to act on the current directory's repo.

| Command | Effect |
| --- | --- |
| `lfrCache install` | Copy the init script into `~/.gradle/init.d` |
| `lfrCache uninstall` | Remove the init script (nothing is cached anymore) |
| `lfrCache on [path]` | Enable the cache for a repo/worktree |
| `lfrCache off [path]` | Disable the cache for a repo/worktree |
| `lfrCache status [path]` | Show this repo's state, all enabled repos, install status |

`on`, `off`, and `status` also accept dashed forms (`-on`, `-off`, `-status`).
