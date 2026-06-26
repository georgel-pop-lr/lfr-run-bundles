# lfr-repo.sh — jump between Liferay repos across multiple roots.
#
# Source this from your shell rc (it must be sourced, not executed, so the
# `cd` lands in your current shell):
#
#     source /path/to/liferay-tools/LfrRepo/lfr-repo.sh
#
# Usage:
#     lfrRepo            # interactive picker over every repo in both roots
#     lfrRepo portal     # jump straight to the only match; picker if ambiguous
#     lfrRepo -l         # list all repos and their roots, no cd
#
# Per-user settings (repo roots, priority, worktree paths) live in
# lfr-repo.local.conf next to this file. It is gitignored, so each person keeps
# their own. Copy lfr-repo.local.conf.example to lfr-repo.local.conf and edit.

_lfrRepoDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -r "${_lfrRepoDir}/lfr-repo.local.conf" ] && . "${_lfrRepoDir}/lfr-repo.local.conf"

# Defaults if the local config did not set them.
[ -z "${LFR_REPO_ROOTS+x}" ] && LFR_REPO_ROOTS=("${HOME}/liferay/repos")
[ -z "${LFR_REPO_PRIORITY+x}" ] && LFR_REPO_PRIORITY=("liferay-portal")

# Emit "<path>\t<name>  (<root>)" for every git repo under the configured roots,
# with LFR_REPO_PRIORITY prefixes sorted first (stable within each rank).
_lfrRepoEntries() {
	local root dir name rank i seq=0
	{
		for root in "${LFR_REPO_ROOTS[@]}"; do
			[ -d "${root}" ] || continue
			for dir in "${root}"/*/; do
				[ -e "${dir}.git" ] || continue
				name="$(basename "${dir}")"
				rank=9999
				for i in "${!LFR_REPO_PRIORITY[@]}"; do
					if [ "${name#"${LFR_REPO_PRIORITY[$i]}"}" != "${name}" ]; then
						rank="${i}"
						break
					fi
				done
				printf '%d\t%d\t%s\t%s  (%s)\n' "${rank}" "${seq}" "${dir%/}" "${name}" "${root}"
				seq=$((seq + 1))
			done
		done
	} | sort -t$'\t' -k1,1n -k2,2n | cut -f3-
}

lfrRepo() {
	if [ "$1" = "-l" ] || [ "$1" = "--list" ]; then
		_lfrRepoEntries | cut -f2-
		return 0
	fi

	local entries
	entries="$(_lfrRepoEntries)"

	if [ -z "${entries}" ]; then
		echo "lfrRepo: no git repos found under: ${LFR_REPO_ROOTS[*]}" >&2
		return 1
	fi

	local selection

	if command -v fzf >/dev/null 2>&1; then
		selection="$(
			printf '%s\n' "${entries}" | fzf \
				--delimiter=$'\t' \
				--exit-0 \
				--height=40% \
				--prompt='repo> ' \
				--query="${1:-}" \
				--reverse \
				--select-1 \
				--with-nth=2..
		)"
	else
		local paths=() labels=() line
		while IFS=$'\t' read -r path label; do
			paths+=("${path}")
			labels+=("${label}")
		done <<< "${entries}"

		if [ -n "$1" ]; then
			local i matches=()
			for i in "${!labels[@]}"; do
				case "${labels[$i]}" in
					*"$1"*) matches+=("${i}") ;;
				esac
			done
			if [ "${#matches[@]}" -eq 1 ]; then
				cd "${paths[${matches[0]}]}" || return 1
				return 0
			fi
		fi

		echo "Select a repo:" >&2
		local choice
		select choice in "${labels[@]}"; do
			[ -n "${choice}" ] || continue
			selection=$'\t'"${choice}"
			for i in "${!labels[@]}"; do
				[ "${labels[$i]}" = "${choice}" ] && selection="${paths[$i]}"$'\t'"${choice}"
			done
			break
		done
	fi

	[ -z "${selection}" ] && return 1

	cd "${selection%%$'\t'*}" || return 1
}

# Tab-complete on repo names.
_lfrRepoComplete() {
	local names
	names="$(_lfrRepoEntries | sed -E 's/^[^\t]*\t([^ ]+).*/\1/')"
	COMPREPLY=($(compgen -W "${names}" -- "${COMP_WORDS[COMP_CWORD]}"))
}

complete -F _lfrRepoComplete lfrRepo
