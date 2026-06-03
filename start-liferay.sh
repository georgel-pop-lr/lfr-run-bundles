#!/usr/bin/env bash
#
# Starts a Liferay bundle, picking free ports if the defaults are taken.
# Modifies tomcat/conf/server.xml in place (with backup) so the bundle's
# stored config matches the running ports — useful for parallel bundles.
#
# Usage:
#   start-liferay.sh                              # uses BUNDLE default below
#   start-liferay.sh /path/to/bundle              # explicit bundle path
#   start-liferay.sh --debug                      # default bundle, debug mode
#   start-liferay.sh --debug /path/to/bundle      # explicit bundle, debug mode
#   start-liferay.sh --pick                       # list bundles and pick one
#   start-liferay.sh --pick --debug               # pick + debug mode
#   start-liferay.sh --jdk /path/to/jdk           # override the JDK
#   start-liferay.sh --clean                      # wipe state + reset DB, then start
#   start-liferay.sh --pick --clean --yes         # pick, clean without prompting, start
#   start-liferay.sh --clean --db-docker pg-db    # reset DB via docker exec, then start
#
# DEBUG mode runs Tomcat via 'catalina.sh jpda run' so a remote debugger can
# attach. The JPDA port defaults to 8000, with the same auto-bump behaviour as
# the other ports if it's already in use.
#
# PICK mode lists every Liferay-looking bundle under BUNDLES_DIR and lets you
# select one interactively.
#
# CLEAN mode (--clean / -c) wipes the resolved bundle's runtime state before
# starting: data, work, elasticsearch, logs, osgi/state, and tomcat
# logs/work/temp, then drops and recreates the database configured in the
# bundle's portal-ext.properties (PostgreSQL and MySQL/MariaDB). It prompts for
# confirmation first; pass --yes / -y to skip the prompt. Make sure the bundle
# is stopped, or the database drop will fail on active connections. The database
# is reset before any folder is deleted, so a failed reset aborts cleanly.
#
# Database location is handled in this order: a Docker DB that publishes its
# port to the host is reached by the normal host:port path; if that host reset
# fails, the script prints what portal-ext.properties expects plus the running
# containers and their ports, and lets you pick one to retry the reset inside
# via `docker exec`. Pass --db-docker <container> to target a container directly
# (and skip the prompt, e.g. together with --yes).
#
# JDK selection: by default the script picks a JDK based on the bundle name
# (Liferay version family) using JDK_BY_FAMILY below. Override per-run with
# --jdk <path> or by exporting JAVA_HOME before invoking the script.

set -euo pipefail

# Directories that hold your Liferay bundles. Edit these for your machine; add
# as many as you like (e.g. a second one on an external drive).
BUNDLES_DIRS=(
	"${HOME}/liferay/bundles"
	# "/mnt/data/liferay/bundles"
)
BUNDLE_DEFAULT="${BUNDLES_DIRS[0]}/liferay-bundle-master"

# JDK roots on this machine, one per Liferay version family. Point these at your
# own JDK installs. The mapping from bundle name to JDK lives in choose_jdk().
JDK_8="${HOME}/liferay/tools/jvm/jdk-8"
JDK_11="${HOME}/liferay/tools/jvm/jdk-11"
JDK_17="${HOME}/liferay/tools/jvm/jdk-17"
JDK_21="${HOME}/liferay/tools/jvm/jdk-21"

DEBUG=0
PICK=0
CLEAN=0
ASSUME_YES=0
BUNDLE=""
JDK_OVERRIDE=""
DB_DOCKER=""

# Manual two-pass parser so we can consume --jdk's value.
args=("$@")
i=0
while [ $i -lt ${#args[@]} ]; do
	arg="${args[$i]}"
	case "$arg" in
		--debug)
			DEBUG=1
			;;
		--pick|--list)
			PICK=1
			;;
		--clean|-c)
			CLEAN=1
			;;
		--yes|-y)
			ASSUME_YES=1
			;;
		--db-docker)
			i=$((i + 1))
			DB_DOCKER="${args[$i]:-}"
			if [ -z "$DB_DOCKER" ]; then
				echo "--db-docker requires a container name" >&2
				exit 1
			fi
			;;
		--db-docker=*)
			DB_DOCKER="${arg#--db-docker=}"
			;;
		--jdk)
			i=$((i + 1))
			JDK_OVERRIDE="${args[$i]:-}"
			if [ -z "$JDK_OVERRIDE" ]; then
				echo "--jdk requires a path argument" >&2
				exit 1
			fi
			;;
		--jdk=*)
			JDK_OVERRIDE="${arg#--jdk=}"
			;;
		*)
			if [ -z "$BUNDLE" ]; then
				BUNDLE="$arg"
			fi
			;;
	esac
	i=$((i + 1))
done

# --pick: list bundles under every BUNDLES_DIRS entry and prompt for a
# selection. Missing directories are silently skipped so this still works on
# machines where only a subset of the configured locations exists.
if [ "$PICK" = "1" ]; then
	bundles=()
	scanned=()

	for dir in "${BUNDLES_DIRS[@]}"; do
		if [ ! -d "$dir" ]; then
			continue
		fi

		scanned+=("$dir")

		for entry in "$dir"/*/; do
			entry="${entry%/}"
			# Accept any directory that has a tomcat folder we can find.
			for c in "$entry/tomcat" $entry/tomcat-* "$entry/liferay-dxp/tomcat" $entry/liferay-dxp/tomcat-*; do
				if [ -d "$c" ]; then
					bundles+=("$entry")
					break
				fi
			done
		done
	done

	if [ "${#scanned[@]}" -eq 0 ]; then
		echo "None of the configured bundles directories exist:" >&2
		printf "  %s\n" "${BUNDLES_DIRS[@]}" >&2
		exit 1
	fi

	if [ "${#bundles[@]}" -eq 0 ]; then
		echo "No Liferay bundles found under:" >&2
		printf "  %s\n" "${scanned[@]}" >&2
		exit 1
	fi

	echo "Available bundles (from ${#scanned[@]} location(s)):"
	for dir in "${scanned[@]}"; do
		echo "  $dir"
	done
	echo

	PS3=$'\nPick a bundle (number, or Ctrl+C to abort): '

	select choice in "${bundles[@]}"; do
		if [ -n "$choice" ]; then
			BUNDLE="$choice"
			break
		fi
		echo "Invalid selection — try again." >&2
	done

	echo
fi

BUNDLE="${BUNDLE:-$BUNDLE_DEFAULT}"

if [ ! -d "$BUNDLE" ]; then
	echo "Bundle directory not found: $BUNDLE" >&2
	exit 1
fi

# Liferay bundles have either tomcat/ or tomcat-9.x.y/ — collect every match
# so we can prompt if a bundle has more than one (e.g. after an upgrade left
# the old tomcat-9.0.50 next to the new tomcat-9.0.60).
TOMCAT_CANDIDATES=()
seen_tomcat() {
	local t
	for t in "${TOMCAT_CANDIDATES[@]:-}"; do
		[ "$t" = "$1" ] && return 0
	done
	return 1
}
for candidate in "$BUNDLE/tomcat" $BUNDLE/tomcat-* "$BUNDLE/liferay-dxp/tomcat" $BUNDLE/liferay-dxp/tomcat-*; do
	if [ -d "$candidate" ] && ! seen_tomcat "$candidate"; then
		TOMCAT_CANDIDATES+=("$candidate")
	fi
done

if [ "${#TOMCAT_CANDIDATES[@]}" -eq 0 ]; then
	echo "No tomcat directory found under $BUNDLE" >&2
	exit 1
elif [ "${#TOMCAT_CANDIDATES[@]}" -eq 1 ]; then
	TOMCAT_DIR="${TOMCAT_CANDIDATES[0]}"
else
	echo "Multiple tomcat directories found under $BUNDLE:"
	TOMCAT_LABELS=()
	for t in "${TOMCAT_CANDIDATES[@]}"; do
		mtime=$(stat -c '%y' "$t" 2>/dev/null | cut -d'.' -f1 || echo "unknown")
		TOMCAT_LABELS+=("$t  (modified $mtime)")
	done
	PS3=$'\nPick a tomcat (number, or Ctrl+C to abort): '
	select choice in "${TOMCAT_LABELS[@]}"; do
		if [ -n "$choice" ]; then
			TOMCAT_DIR="${TOMCAT_CANDIDATES[$((REPLY - 1))]}"
			break
		fi
		echo "Invalid selection — try again." >&2
	done
	echo
fi

SERVER_XML="$TOMCAT_DIR/conf/server.xml"
CATALINA="$TOMCAT_DIR/bin/catalina.sh"

if [ ! -f "$SERVER_XML" ] || [ ! -x "$CATALINA" ]; then
	echo "Tomcat layout looks wrong:" >&2
	echo "  server.xml : $SERVER_XML" >&2
	echo "  catalina.sh: $CATALINA" >&2
	exit 1
fi

echo "Bundle : $BUNDLE"
echo "Tomcat : $TOMCAT_DIR"
echo

# --clean: wipe runtime state (data, work, logs, elasticsearch, osgi/state,
# tomcat logs/work/temp) and reset the database read from portal-ext.properties.
# Runs only after the bundle and tomcat are resolved so we know exactly what to
# wipe, and prompts for confirmation unless --yes was passed.
confirm_or_abort() {
	[ "$ASSUME_YES" = "1" ] && return 0
	local reply
	read -r -p "$1 [y/N] " reply
	case "$reply" in
		y|Y|yes|YES) return 0 ;;
		*) echo "Aborted." >&2; exit 1 ;;
	esac
}

# Give up: print likely causes and abort. $1 is an optional context line.
_db_reset_failed() {
	[ -n "${1:-}" ] && echo "  $1" >&2
	echo "  Database reset FAILED. Check that the server is running, the bundle" >&2
	echo "  is stopped, and the credentials in portal-ext.properties are correct." >&2
	exit 1
}

# Run the drop/create. Uses engine/host/port/db/user/pass from the caller's
# scope (bash dynamic scoping). $1 empty = host client against host:port;
# otherwise a Docker container name to run the client inside via docker exec.
_run_reset() {
	local container="${1:-}"

	if [ "$engine" = postgres ]; then
		local terminate="SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db' AND pid <> pg_backend_pid();"
		if [ -n "$container" ]; then
			docker exec -i -e PGPASSWORD="$pass" "$container" psql -U "$user" -d postgres -q -c "$terminate" >/dev/null 2>&1 || true
			docker exec -i -e PGPASSWORD="$pass" "$container" psql -U "$user" -d postgres -q -v ON_ERROR_STOP=1 \
				-c "DROP DATABASE IF EXISTS \"$db\";" -c "CREATE DATABASE \"$db\";"
		else
			PGPASSWORD="$pass" psql -h "$host" -p "$port" -U "$user" -d postgres -q -c "$terminate" >/dev/null 2>&1 || true
			PGPASSWORD="$pass" psql -h "$host" -p "$port" -U "$user" -d postgres -q -v ON_ERROR_STOP=1 \
				-c "DROP DATABASE IF EXISTS \"$db\";" -c "CREATE DATABASE \"$db\";"
		fi
	else
		local sql="DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
		if [ -n "$container" ]; then
			docker exec -i "$container" mysql -u "$user" ${pass:+-p"$pass"} -e "$sql"
		else
			mysql -h "$host" -P "$port" -u "$user" ${pass:+-p"$pass"} -e "$sql"
		fi
	fi
}

# Host reset failed: show what portal-ext.properties expects and the running
# containers with their ports, then let the user pick one to retry the reset
# inside via docker exec.
_recover_via_docker() {
	echo >&2
	echo "  Could not reach the database directly." >&2
	echo "  portal-ext.properties expects: $engine \"$db\" at $host:$port (user $user)." >&2

	if ! command -v docker >/dev/null 2>&1; then
		echo "  Docker is not available to try a container." >&2
		_db_reset_failed
	fi

	local lines=()
	mapfile -t lines < <(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null || true)
	if [ "${#lines[@]}" -eq 0 ]; then
		echo "  No running Docker containers to try." >&2
		_db_reset_failed
	fi

	echo "  Running Docker containers (the DB is usually the one publishing $port):" >&2
	local names=() i=1 line name ports
	for line in "${lines[@]}"; do
		name="${line%%$'\t'*}"
		ports="${line#*$'\t'}"
		names+=("$name")
		printf "    %2d) %-28s %s\n" "$i" "$name" "$ports" >&2
		i=$((i + 1))
	done

	if [ "$ASSUME_YES" = "1" ]; then
		echo "  (--yes given — not prompting. Re-run with --db-docker <container> to target one.)" >&2
		_db_reset_failed
	fi

	local choice
	read -r -p "  Reset the DB inside which container? (number, or Enter to abort): " choice
	if [ -z "$choice" ]; then
		echo "  Aborted — nothing was deleted." >&2
		exit 1
	fi
	if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#names[@]}" ]; then
		echo "  Invalid selection — aborting." >&2
		exit 1
	fi

	local chosen="${names[$((choice - 1))]}"
	echo "  Retrying via docker exec $chosen ..."
	_run_reset "$chosen" || _db_reset_failed "Reset inside container $chosen failed."
	echo "  Database reset succeeded via container $chosen."
}

reset_database() {
	local portal_ext="$1"

	if [ ! -f "$portal_ext" ]; then
		echo "  No portal-ext.properties at $portal_ext — skipping database reset." >&2
		return 0
	fi

	local url user pass
	url="$(sed -nE 's/^[[:space:]]*jdbc\.default\.url=//p' "$portal_ext" | tail -n 1)"
	user="$(sed -nE 's/^[[:space:]]*jdbc\.default\.username=//p' "$portal_ext" | tail -n 1)"
	pass="$(sed -nE 's/^[[:space:]]*jdbc\.default\.password=//p' "$portal_ext" | tail -n 1)"

	if [ -z "$url" ]; then
		echo "  No jdbc.default.url in portal-ext.properties — skipping (data/ removal clears embedded DBs)." >&2
		return 0
	fi

	local base="${url%%\?*}"
	local engine hostport host rest port db

	if [[ "$base" == jdbc:postgresql://* ]]; then
		engine=postgres
		hostport="${base#jdbc:postgresql://}"
		port=5432
	elif [[ "$base" == jdbc:mysql://* || "$base" == jdbc:mariadb://* ]]; then
		engine=mysql
		hostport="${base#jdbc:*://}"
		port=3306
	else
		echo "  Unrecognized JDBC URL ($base) — skipping DB reset; data/ removal handles embedded DBs." >&2
		return 0
	fi

	host="${hostport%%[:/]*}"
	rest="${hostport#"$host"}"
	[[ "$rest" == :* ]] && { port="${rest#:}"; port="${port%%/*}"; }
	db="${base##*/}"

	# --db-docker forces the reset inside the named container.
	if [ -n "$DB_DOCKER" ]; then
		echo "  $engine via docker exec $DB_DOCKER: dropping and recreating \"$db\" (user $user)"
		_run_reset "$DB_DOCKER" || _db_reset_failed "Reset inside container $DB_DOCKER failed."
		return 0
	fi

	# Otherwise try the host client (also reaches a Docker DB that publishes its
	# port); on failure, fall into the interactive container picker.
	echo "  $engine: dropping and recreating \"$db\" on $host:$port (user $user)"
	if ! _run_reset ""; then
		_recover_via_docker
	fi
}

clean_bundle() {
	local liferay_home
	liferay_home="$(dirname "$TOMCAT_DIR")"

	echo "About to CLEAN this bundle:"
	echo "  Liferay home : $liferay_home"
	echo "  Tomcat       : $TOMCAT_DIR"
	echo "  Removes      : data work elasticsearch logs osgi/state, tomcat logs/work/temp"
	echo "  Database     : reset from $liferay_home/portal-ext.properties"
	echo
	confirm_or_abort "This deletes data and DROPs the database. Proceed?"

	# Reset the database first: it is the step most likely to fail (bad
	# credentials, server down, Docker-only network), and it exits on failure.
	# Doing it before the folder wipe avoids leaving wiped folders next to an
	# un-reset database.
	echo "Resetting database:"
	reset_database "$liferay_home/portal-ext.properties"

	echo "Cleaning bundle state:"
	local target
	for target in \
		"$liferay_home/data" \
		"$liferay_home/work" \
		"$liferay_home/elasticsearch" \
		"$liferay_home/logs" \
		"$liferay_home/osgi/state" \
		"$TOMCAT_DIR/logs" \
		"$TOMCAT_DIR/work" \
		"$TOMCAT_DIR/temp"; do
		if [ -e "$target" ]; then
			rm -rf "$target"
			echo "  removed $target"
		fi
	done
	echo
}

if [ "$CLEAN" = "1" ]; then
	clean_bundle
fi

# Drop in the Elasticsearch configuration if the bundle's osgi/configs
# directory exists and doesn't already have one. The source file is expected
# to live next to this script; if it's missing we just skip silently.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ELASTIC_SOURCE="$SCRIPT_DIR/com.liferay.portal.search.elasticsearch7.configuration.ElasticsearchConfiguration.config"
ELASTIC_TARGET_DIR=""
for candidate in "$BUNDLE/osgi/configs" "$BUNDLE/liferay-dxp/osgi/configs"; do
	if [ -d "$candidate" ]; then
		ELASTIC_TARGET_DIR="$candidate"
		break
	fi
done

if [ -n "$ELASTIC_TARGET_DIR" ] && [ -f "$ELASTIC_SOURCE" ]; then
	ELASTIC_TARGET="$ELASTIC_TARGET_DIR/$(basename "$ELASTIC_SOURCE")"

	if [ ! -f "$ELASTIC_TARGET" ]; then
		cp "$ELASTIC_SOURCE" "$ELASTIC_TARGET"
		echo "Elasticsearch config installed: $ELASTIC_TARGET"
	else
		echo "Elasticsearch config already present at $ELASTIC_TARGET — leaving as-is."
	fi
	echo
fi

HTTP_DEFAULT=8080
SHUTDOWN_DEFAULT=8005
AJP_DEFAULT=8009
HTTPS_DEFAULT=8443
JPDA_DEFAULT=8000

is_port_free() {
	local port=$1
	if command -v ss >/dev/null 2>&1; then
		! ss -lnt "sport = :$port" 2>/dev/null | tail -n +2 | grep -q LISTEN
	elif command -v lsof >/dev/null 2>&1; then
		! lsof -i ":$port" -sTCP:LISTEN >/dev/null 2>&1
	else
		! netstat -lnt 2>/dev/null | awk '{print $4}' | grep -q ":$port$"
	fi
}

USED=()
already_chosen() {
	local port=$1
	local u
	for u in "${USED[@]:-}"; do
		[ "$u" = "$port" ] && return 0
	done
	return 1
}

choose_port() {
	local port=$1
	while already_chosen "$port" || ! is_port_free "$port"; do
		port=$((port + 1))
	done
	USED+=("$port")
	echo "$port"
}

HTTP_PORT=$(choose_port "$HTTP_DEFAULT")
SHUTDOWN_PORT=$(choose_port "$SHUTDOWN_DEFAULT")
AJP_PORT=$(choose_port "$AJP_DEFAULT")
HTTPS_PORT=$(choose_port "$HTTPS_DEFAULT")

JPDA_PORT=""
if [ "$DEBUG" = "1" ]; then
	JPDA_PORT=$(choose_port "$JPDA_DEFAULT")
fi

print_port() {
	local label=$1
	local resolved=$2
	local default=$3
	if [ "$resolved" = "$default" ]; then
		printf "  %-9s %s\n" "$label" "$resolved"
	else
		printf "  %-9s %s   (default %s was busy)\n" "$label" "$resolved" "$default"
	fi
}

echo "Selected ports:"
print_port "HTTP" "$HTTP_PORT" "$HTTP_DEFAULT"
print_port "SHUTDOWN" "$SHUTDOWN_PORT" "$SHUTDOWN_DEFAULT"
print_port "AJP" "$AJP_PORT" "$AJP_DEFAULT"
print_port "HTTPS" "$HTTPS_PORT" "$HTTPS_DEFAULT"
if [ -n "$JPDA_PORT" ]; then
	print_port "JPDA" "$JPDA_PORT" "$JPDA_DEFAULT"
fi
echo

# Read current ports out of server.xml so we know whether we need to write.
read_port() {
	local pattern=$1
	grep -oE "$pattern" "$SERVER_XML" | head -n 1 | grep -oE 'port="[0-9]+"' | grep -oE '[0-9]+' || true
}

CURRENT_SHUTDOWN=$(grep -oE '<Server port="[0-9]+"' "$SERVER_XML" | head -n 1 | grep -oE '[0-9]+' || true)
CURRENT_HTTP=$(read_port '<Connector[^>]*port="[0-9]+"[^>]*protocol="HTTP/1\.1"')
CURRENT_AJP=$(read_port '<Connector[^>]*port="[0-9]+"[^>]*protocol="AJP/1\.3"')
CURRENT_AJP_ALT=$(read_port 'protocol="AJP/1\.3"[^>]*port="[0-9]+"')
CURRENT_HTTPS=$(grep -oE 'redirectPort="[0-9]+"' "$SERVER_XML" | head -n 1 | grep -oE '[0-9]+' || true)

# AJP block in Liferay can have port="" before or after protocol="" — try both.
if [ -z "$CURRENT_AJP" ] && [ -n "$CURRENT_AJP_ALT" ]; then
	CURRENT_AJP="$CURRENT_AJP_ALT"
fi

needs_update=false
[ "$CURRENT_SHUTDOWN" != "$SHUTDOWN_PORT" ] && needs_update=true
[ "$CURRENT_HTTP" != "$HTTP_PORT" ] && needs_update=true
[ "$CURRENT_AJP" != "$AJP_PORT" ] && needs_update=true
[ "$CURRENT_HTTPS" != "$HTTPS_PORT" ] && needs_update=true

if $needs_update; then
	BACKUP="$SERVER_XML.bak.$(date +%Y%m%d-%H%M%S)"
	cp "$SERVER_XML" "$BACKUP"
	echo "server.xml backed up to $BACKUP"

	# Shutdown port — <Server port="..."
	if [ -n "$CURRENT_SHUTDOWN" ]; then
		sed -i -E "s|(<Server[[:space:]]+port=\")[0-9]+(\")|\1$SHUTDOWN_PORT\2|" "$SERVER_XML"
	fi

	# HTTP port — Connector with protocol="HTTP/1.1"
	if [ -n "$CURRENT_HTTP" ]; then
		# Replace every Connector that declares protocol="HTTP/1.1"
		# in case there are two (Liferay sometimes ships a commented-out
		# alternative with the same port).
		sed -i -E "/protocol=\"HTTP\/1\.1\"/{s|port=\"$CURRENT_HTTP\"|port=\"$HTTP_PORT\"|}" "$SERVER_XML"
	fi

	# AJP port — Connector with protocol="AJP/1.3"
	if [ -n "$CURRENT_AJP" ]; then
		sed -i -E "/protocol=\"AJP\/1\.3\"/{s|port=\"$CURRENT_AJP\"|port=\"$AJP_PORT\"|}" "$SERVER_XML"
	fi

	# HTTPS / redirectPort — referenced from HTTP and AJP connectors.
	if [ -n "$CURRENT_HTTPS" ]; then
		sed -i -E "s|redirectPort=\"$CURRENT_HTTPS\"|redirectPort=\"$HTTPS_PORT\"|g" "$SERVER_XML"
		# Also patch the HTTPS connector(s) themselves if their port differed.
		sed -i -E "/protocol=\"org\.apache\.coyote\.http11\.Http11(Nio|Apr)Protocol\"/{s|port=\"$CURRENT_HTTPS\"|port=\"$HTTPS_PORT\"|}" "$SERVER_XML"
	fi

	echo "server.xml updated."
fi

# Decide which JDK to run with — explicit --jdk wins, then JAVA_HOME from the
# shell, then a heuristic based on the bundle name.
choose_jdk() {
	local bundle_name
	bundle_name="$(basename "$BUNDLE")"

	# Strip a trailing /liferay-dxp on inner-folder calls.
	if [ "$bundle_name" = "liferay-dxp" ]; then
		bundle_name="$(basename "$(dirname "$BUNDLE")")"
	fi

	case "$bundle_name" in
		liferay-portal-6.*|liferay-dxp-digital-enterprise-7.0.*|liferay-dxp-7.0.*|liferay-dxp-7.1.*)
			echo "$JDK_8"
			;;
		liferay-dxp-7.2.*|liferay-dxp-7.3.*|liferay-dxp-tomcat-7.3.*)
			echo "$JDK_11"
			;;
		liferay-dxp-7.4.*|liferay-dxp-tomcat-7.4.*|liferay-dxp-tomcat-2023.*|liferay-dxp-tomcat-2024.*)
			echo "$JDK_11"
			;;
		liferay-dxp-tomcat-2025.*|liferay-dxp-tomcat-2026.*)
			echo "$JDK_17"
			;;
		*)
			# Unknown — fall back to JDK 17 (best for current LTS).
			echo "$JDK_17"
			;;
	esac
}

if [ -n "$JDK_OVERRIDE" ]; then
	JDK_PATH="$JDK_OVERRIDE"
	JDK_SOURCE="(--jdk override)"
elif [ -n "${JAVA_HOME:-}" ]; then
	JDK_PATH="$JAVA_HOME"
	JDK_SOURCE="(JAVA_HOME)"
else
	JDK_PATH="$(choose_jdk)"
	JDK_SOURCE="(auto-detected for $(basename "$BUNDLE"))"
fi

if [ ! -x "$JDK_PATH/bin/java" ]; then
	echo "Selected JDK has no bin/java: $JDK_PATH" >&2
	echo "Pass --jdk /path/to/jdk or export JAVA_HOME to choose another." >&2
	exit 1
fi

export JAVA_HOME="$JDK_PATH"
export JRE_HOME="$JDK_PATH"
export PATH="$JDK_PATH/bin:$PATH"

echo
echo "Starting Liferay (Ctrl+C to stop)."
echo "  Editor / portal: http://localhost:$HTTP_PORT/"
echo "  Logs           : $TOMCAT_DIR/logs/catalina.out"
echo "  JDK            : $JDK_PATH $JDK_SOURCE"

if [ "$DEBUG" = "1" ]; then
	# Bind the JPDA listener to all interfaces (the asterisk) so a remote
	# debugger can attach. Suspend=n means the JVM doesn't wait for a
	# debugger before continuing startup.
	export JPDA_ADDRESS="*:$JPDA_PORT"
	export JPDA_TRANSPORT="dt_socket"
	export JPDA_SUSPEND="n"

	echo "  Debug attach   : localhost:$JPDA_PORT (transport=dt_socket, suspend=n)"
	echo

	exec "$CATALINA" jpda run
fi

echo

exec "$CATALINA" run
