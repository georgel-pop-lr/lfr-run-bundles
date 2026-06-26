# lfr-cache.sh — per repo/worktree Gradle build cache toggle.
#
# Source this from your shell rc (normally via the root lfrTools.sh). It
# defines the lfrCache function. Build master once with the cache on to seed it,
# then enable it on each worktree so their builds reuse master's compiled module
# output and only recompile what that worktree changed.
#
# Usage:
#     lfrCache on      [path]   enable cache for a repo/worktree (default: cwd)
#     lfrCache off     [path]   disable cache for a repo/worktree
#     lfrCache status  [path]   show this repo's state, all enabled repos, install state
#     lfrCache install          install the Gradle init script into ~/.gradle/init.d
#     lfrCache uninstall        remove the Gradle init script
#
# on/off/status also accept the dashed forms -on, -off, -status.

_lfrCacheDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

lfrCache() {
	local tools_dir="${_lfrCacheDir}"
	local registry="${tools_dir}/enabled-repos.txt"
	local init_src="${tools_dir}/init.d/lfr-build-cache.gradle"
	local gradle_home="${GRADLE_USER_HOME:-$HOME/.gradle}"
	local init_dest="${gradle_home}/init.d/lfr-build-cache.gradle"

	local cmd="${1:-status}"
	cmd="${cmd#-}"
	local target="${2:-$PWD}"
	local repo

	mkdir -p "${tools_dir}"
	touch "${registry}"

	case "${cmd}" in
	install)
		mkdir -p "${gradle_home}/init.d"
		sed "s#@LFRCACHE_REGISTRY@#${registry}#g" "${init_src}" >"${init_dest}" &&
			echo "Installed init script: ${init_dest}"
		echo "Cache stays OFF until you run: lfrCache on <repo>"
		;;
	uninstall)
		rm -f "${init_dest}" && echo "Removed init script: ${init_dest}"
		;;
	on)
		repo="$(git -C "${target}" rev-parse --show-toplevel 2>/dev/null)" ||
			{ echo "Not inside a git repo: ${target}" >&2; return 1; }
		if grep -qxF "${repo}" "${registry}"; then
			echo "Already enabled: ${repo}"
		else
			echo "${repo}" >>"${registry}"
			echo "Enabled build cache for: ${repo}"
		fi
		;;
	off)
		repo="$(git -C "${target}" rev-parse --show-toplevel 2>/dev/null)" ||
			{ echo "Not inside a git repo: ${target}" >&2; return 1; }
		grep -vxF "${repo}" "${registry}" >"${registry}.tmp" || true
		mv "${registry}.tmp" "${registry}"
		echo "Disabled build cache for: ${repo}"
		;;
	status)
		repo="$(git -C "${target}" rev-parse --show-toplevel 2>/dev/null)"
		if [ -n "${repo}" ]; then
			if grep -qxF "${repo}" "${registry}"; then
				echo "ON   ${repo}"
			else
				echo "OFF  ${repo}"
			fi
		fi
		echo "--- all enabled repos ---"
		grep -vE '^[[:space:]]*(#|$)' "${registry}" 2>/dev/null || echo "(none)"
		echo "--- init script installed? ---"
		if [ -f "${init_dest}" ]; then
			echo "yes: ${init_dest}"
		else
			echo "no (run: lfrCache install)"
		fi
		;;
	help | --help | -h | "")
		echo "usage: lfrCache on|off|status|install|uninstall [path]"
		;;
	*)
		echo "lfrCache: unknown command '${cmd}'" >&2
		echo "usage: lfrCache on|off|status|install|uninstall [path]" >&2
		return 1
		;;
	esac
}
