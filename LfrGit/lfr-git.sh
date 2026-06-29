# lfr-git.sh — Liferay git helpers: safe clean, fork sync, rebase.
#
# Source this from your shell rc (normally via the root lfrTools.sh). It defines:
#     lfrGitCleanDry   preview what `git clean` would remove (safe, no deletion)
#     lfrGitClean      remove untracked + ignored files, keeping IDE and per-user props
#     lfrGitSync       sync a fork's liferay-portal from upstream ([org] optional)
#     lfrGitSyncEE     sync a fork's liferay-portal-ee master from upstream ([org] optional)
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

# Resolve the fork org: use the passed argument, else LFR_GIT_FORK_ORG. Echoes
# the org on success; errors if neither is set.
_lfrGitForkOrg() {
	local org="${1:-${LFR_GIT_FORK_ORG:-}}"
	if [ -z "${org}" ]; then
		echo "lfrGitSync: pass a fork org or set LFR_GIT_FORK_ORG in ${_lfrGitDir}/lfr-git.local.conf" >&2
		return 1
	fi
	printf '%s\n' "${org}"
}

# Sync a team fork's liferay-portal from upstream. Pass a fork org to override
# the configured LFR_GIT_FORK_ORG: lfrGitSync [org]
lfrGitSync() {
	local org
	org="$(_lfrGitForkOrg "${1-}")" || return 1
	gh repo sync "${org}/liferay-portal" \
		--source "${LFR_GIT_UPSTREAM_ORG}/liferay-portal"
}

# Sync a team fork's liferay-portal-ee master from upstream. Pass a fork org to
# override the configured LFR_GIT_FORK_ORG: lfrGitSyncEE [org]
lfrGitSyncEE() {
	local org
	org="$(_lfrGitForkOrg "${1-}")" || return 1
	gh repo sync "${org}/liferay-portal-ee" --branch master \
		--source "${LFR_GIT_UPSTREAM_ORG}/liferay-portal-ee" --branch master
}

# Interactive rebase over the last N commits (default 20).
lfrGitRebase() {
	git rebase -i "HEAD~${1:-20}"
}
