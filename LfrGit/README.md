# LfrGit

Liferay git helpers: a safe `git clean`, fork sync from upstream, and a quick
interactive rebase. Loaded as shell functions via the root `lfrTools.sh`.

## Per-user config

Copy the example and set your team's fork org (gitignored, so it stays local):

```bash
cp lfr-git.local.conf.example lfr-git.local.conf
# edit LFR_GIT_FORK_ORG
```

| Variable | Meaning | Default |
| --- | --- | --- |
| `LFR_GIT_FORK_ORG` | Your team's fork org on GitHub | (required for sync) |
| `LFR_GIT_UPSTREAM_ORG` | Upstream org to sync from | `liferay` |

## Commands

| Command | What it does |
| --- | --- |
| `lfrGitCleanDry` | Preview what `git clean` would remove. Run this first. |
| `lfrGitClean` | Remove untracked and ignored files, keeping `*.iml`, `.idea`, and `app.server/build/test.$USER.properties`. |
| `lfrGitSync` | `gh repo sync <fork>/liferay-portal --source <upstream>/liferay-portal` |
| `lfrGitSyncEE` | Same for `liferay-portal-ee` master. |
| `lfrGitRebase [N]` | `git rebase -i HEAD~N` (N defaults to 20). |

`lfrGitClean` and `lfrGitCleanDry` accept extra `git clean` arguments, e.g.
`lfrGitClean modules/apps/some-app`.
