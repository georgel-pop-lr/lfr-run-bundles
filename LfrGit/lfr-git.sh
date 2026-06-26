# lfr-git.sh — Liferay git helpers: safe clean, fork sync, rebase.
#
# Source this from your shell rc (normally via the root lfrTools.sh). It defines:
#     lfrGitCleanDry   preview what `git clean` would remove (safe, no deletion)
#     lfrGitClean      remove untracked + ignored files, keeping IDE and per-user props
#     lfrGitSync       sync your team fork's liferay-portal from upstream
#     lfrGitSyncEE     sync your team fork's liferay-portal-ee master from upstream
#     lfrGitRebase     interactive rebase over the last N commits (default 20)
#
# Per-user settings (your team fork org) live in lfr-git.local.conf next to this
# file. It is gitignored. Copy lfr-git.local.conf.example to lfr-git.local.conf.

_lfrGitDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -r "${_lfrGitDir}/lfr-git.local.conf" ] && . "${_lfrGitDir}/lfr-git.local.conf"

: "${LFR_GIT_UPSTREAM_ORG:=liferay}"

# Files kept during a clean: IDE project files and per-developer properties.
_lfrGitCleanExcludes=(
	-e '**/*.iml'
	-e '.idea'
	-e "app.server.${USER}.properties"
	-e "build.${USER}.properties"
	-e "test.${USER}.properties"
)

# Preview what would be removed. Run this before lfrGitClean.
lfrGitCleanDry() {
	git clean -xdn "${_lfrGitCleanExcludes[@]}" "$@"
}

# Actually remove untracked and ignored files (keeps the excludes above).
lfrGitClean() {
	git clean -xdf "${_lfrGitCleanExcludes[@]}" "$@"
}

_lfrGitForkReady() {
	if [ -z "${LFR_GIT_FORK_ORG:-}" ]; then
		echo "lfrGitSync: set LFR_GIT_FORK_ORG in ${_lfrGitDir}/lfr-git.local.conf" >&2
		return 1
	fi
}

# Sync your team fork's liferay-portal from upstream.
lfrGitSync() {
	_lfrGitForkReady || return 1
	gh repo sync "${LFR_GIT_FORK_ORG}/liferay-portal" \
		--source "${LFR_GIT_UPSTREAM_ORG}/liferay-portal"
}

# Sync your team fork's liferay-portal-ee master from upstream.
lfrGitSyncEE() {
	_lfrGitForkReady || return 1
	gh repo sync "${LFR_GIT_FORK_ORG}/liferay-portal-ee" --branch master \
		--source "${LFR_GIT_UPSTREAM_ORG}/liferay-portal-ee" --branch master
}

# Interactive rebase over the last N commits (default 20).
lfrGitRebase() {
	git rebase -i "HEAD~${1:-20}"
}
