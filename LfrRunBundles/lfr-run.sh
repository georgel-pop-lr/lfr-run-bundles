# lfr-run.sh — expose start-liferay.sh as the lfrRunBundle command.
#
# start-liferay.sh is a standalone executable, so the lfrTools.sh aggregator
# (which loads lfr-*.sh function files) does not pick it up on its own. This thin
# wrapper defines lfrRunBundle so it loads like every other tool, no alias needed.

_lfrRunDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

lfrRunBundle() {
	"${_lfrRunDir}/start-liferay.sh" "$@"
}
