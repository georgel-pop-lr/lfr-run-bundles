# lfr.sh — single entry point for every Liferay tool under this folder.
#
# Source this one file from your shell rc. It loads every lfr-*.sh tool from
# each tool subfolder (LfrRepo, LfrCache, ...), defining their functions
# (lfrRepo, lfrWorktree, lfrCache, ...). It must be sourced, not executed, so
# the functions and their `cd`s land in your current shell:
#
#     source /path/to/liferay-tools/lfrTools.sh
#
# Each tool keeps living in its own folder. Drop a new lfr-<name>.sh in any
# subfolder and it gets picked up automatically. A folder's own lfr.sh
# aggregator is skipped (only lfr-<name>.sh files are loaded).

_lfr_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for _lfr_script in "${_lfr_root}"/*/lfr-*.sh; do
	[ -r "${_lfr_script}" ] && . "${_lfr_script}"
done

unset _lfr_root _lfr_script

# lfrTools — list the tool commands loaded by this entry point.
lfrTools() {
	echo "Liferay tools loaded. Commands:"
	compgen -A function | grep -E '^lfr[A-Z]' | sort | sed 's/^/  /'
	echo "Run any with --help (e.g. lfrCache help)."
}
