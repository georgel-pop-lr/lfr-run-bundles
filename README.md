# Run bundles

Launcher for Liferay DXP bundles that picks free ports if the defaults are
busy and drops in a known-good Elasticsearch configuration on the first run.
Useful when you keep several bundles on the same machine and want to start
one without manually editing `server.xml` or hunting for a free port.

## Contents

| File | Purpose |
|---|---|
| `start-liferay.sh` | Launches a bundle with auto-port selection. Modifies `tomcat/conf/server.xml` in place if any default port is busy, after backing it up. |
| `com.liferay.portal.search.elasticsearch7.configuration.ElasticsearchConfiguration.config` | Embedded-Elasticsearch configuration. The launcher copies this into the bundle's `osgi/configs/` directory on first run, so search works out of the box without an external Elasticsearch server. |

Both files are referenced relative to the script, so as long as they sit
together you can move the folder freely.

## Setup

1. Clone this repo somewhere on your machine:

   ```bash
   git clone https://github.com/georgel-pop-lr/lfr-run-bundles.git
   cd lfr-run-bundles
   ```

2. Edit the config block at the top of `start-liferay.sh` for your machine:

   - `BUNDLES_DIRS` — the directories that hold your Liferay bundles (one or more).
   - `BUNDLE_DEFAULT` — the bundle used when you run the script with no argument.
   - `JDK_8` / `JDK_11` / `JDK_17` / `JDK_21` — point these at your JDK install roots.

3. (Optional) Add an alias so you can call it from anywhere:

   ```bash
   echo 'alias lfrRunBundle="$HOME/liferay/tools/lfr-run-bundles/start-liferay.sh"' >> ~/.bashrc
   source ~/.bashrc
   ```

4. (Only needed for `--clean`) Install a database client on the host — `psql`
   for PostgreSQL or `mysql` for MySQL/MariaDB — so the launcher can drop and
   recreate the database. `docker` is optional and only used as a fallback when
   the database runs inside a container.

## Usage

### Run the default bundle

The script has a default bundle path baked in:

```bash
${HOME}/liferay/tools/lfr-run-bundles/start-liferay.sh
```

The default points at:

```
${HOME}/liferay/bundles/liferay-dxp-tomcat-2025.q1.14-lts-1748919610
```

Edit `BUNDLE_DEFAULT` near the top of `start-liferay.sh` if you want a
different default.

### Pick a bundle interactively

Pass `--pick` to list every Liferay-looking bundle across the directories
configured in `BUNDLES_DIRS` at the top of `start-liferay.sh` and select one
by number:

```bash
lfrRunBundle --pick
lfrRunBundle --pick --debug          # combine with debug mode
```

Sample output:

```
Available bundles in ${HOME}/liferay/bundles:

 1) ${HOME}/liferay/bundles/liferay-dxp-7.3.10.u26
 2) ${HOME}/liferay/bundles/liferay-dxp-7.3.10.u27
 3) ${HOME}/liferay/bundles/liferay-dxp-tomcat-2025.q1.14-lts-1748919610
 ...

Pick a bundle (number, or Ctrl+C to abort):
```

The script only lists directories that actually contain a Tomcat folder
(top-level `tomcat/`/`tomcat-9.x.y/` or nested `liferay-dxp/tomcat/`), so
half-extracted or non-Liferay folders are skipped. Type the number, hit
Enter, and the selected bundle goes through the same port-resolution and
launch path as a manually-passed argument.

`--list` is accepted as an alias for `--pick`.

### Run a specific bundle

Pass the bundle path as the first argument:

```bash
./start-liferay.sh /path/to/another/liferay-bundle
```

The path can point at either the bundle root (`liferay-dxp-tomcat-...`) or
its inner `liferay-dxp/` directory — the script auto-detects the Tomcat
folder regardless. Both of the following are equivalent:

```bash
# Bundle root
./start-liferay.sh ${HOME}/liferay/bundles/liferay-dxp-tomcat-2025.q1.14-lts-1748919610

# Inner liferay-dxp/ directly
./start-liferay.sh ${HOME}/liferay/bundles/liferay-dxp-tomcat-2025.q1.14-lts-1748919610/liferay-dxp
```

### Run in debug mode (remote debugger)

Pass `--debug` to start Tomcat with the JVM's JPDA debug agent enabled, so
IntelliJ / Eclipse / VS Code can attach to it:

```bash
./start-liferay.sh --debug
./start-liferay.sh --debug /path/to/another/liferay-bundle
```

JPDA listens on port `8000` by default. If `8000` is already taken, the
script bumps to the next free port — same behaviour as the other Tomcat
ports — and prints the resolved value:

```
Selected ports:
  HTTP      8080
  SHUTDOWN  8005
  AJP       8009
  HTTPS     8443
  JPDA      8000

Starting Liferay (Ctrl+C to stop).
  Editor / portal: http://localhost:8080/
  Logs           : .../tomcat/logs/catalina.out
  Debug attach   : localhost:8000 (transport=dt_socket, suspend=n)
```

The JVM does **not** suspend on startup (`suspend=n`), so the portal will
boot whether a debugger is attached or not. Attach from your IDE using:

- Host: `localhost`
- Port: whatever the script reports next to `Debug attach`
- Transport: `dt_socket`

### Running from anywhere

Call the script with its full path:

```bash
${HOME}/liferay/tools/lfr-run-bundles/start-liferay.sh
${HOME}/liferay/tools/lfr-run-bundles/start-liferay.sh --debug
```

To avoid typing it, add an alias to `~/.bashrc` (or `~/.zshrc`):

```bash
alias lfrRunBundle="${HOME}/liferay/tools/lfr-run-bundles/start-liferay.sh"
```

Then `lfrRunBundle`, `lfrRunBundle --debug`, `lfrRunBundle /path/to/bundle`
all work from any directory. The script resolves its own location
internally so the bundled Elasticsearch config is still found through
aliases or symlinks.

### JDK selection (older bundles need older JDKs)

Liferay needs the right JDK for its version. If the wrong one is used the
portal crashes on startup with a `NoSuchFieldException: modifiers` (under
JDK 12+) or similar reflection error.

The launcher picks a JDK automatically based on the bundle's name:

| Bundle name pattern | JDK chosen |
|---|---|
| `liferay-portal-6.*`, `liferay-dxp-7.0.*`, `liferay-dxp-7.1.*` | JDK 8 |
| `liferay-dxp-7.2.*`, `liferay-dxp-7.3.*` | JDK 11 |
| `liferay-dxp-7.4.*`, `liferay-dxp-tomcat-2023.*`, `liferay-dxp-tomcat-2024.*` | JDK 11 |
| `liferay-dxp-tomcat-2025.*`, `liferay-dxp-tomcat-2026.*` | JDK 17 |

The actual JDK paths are constants near the top of `start-liferay.sh`
(`JDK_8`, `JDK_11`, `JDK_17`, `JDK_21`). Edit them if your machine keeps
JDKs in different locations.

To override the detection per-run, use `--jdk`:

```bash
lfrRunBundle --pick --jdk ${HOME}/liferay/tools/jvm/jdk-11
lfrRunBundle --jdk=/path/to/jdk /path/to/bundle
```

Or export `JAVA_HOME` before invoking:

```bash
JAVA_HOME=${HOME}/liferay/tools/jvm/jdk-11 lfrRunBundle --pick
```

The launcher logs the chosen JDK and where it came from:

```
Starting Liferay (Ctrl+C to stop).
  Editor / portal: http://localhost:8081/
  Logs           : .../tomcat/logs/catalina.out
  JDK            : /home/.../jdk-11.0.22 (auto-detected for liferay-dxp-7.3.10.u27)
```

### Clean start (reset the database and runtime state)

Pass `--clean` (or `-c`) to wipe the bundle's runtime state and reset its
database before starting — handy when you want a fresh install:

```bash
lfrRunBundle --pick --clean
lfrRunBundle --clean --yes        # skip the confirmation prompt
```

After a confirmation prompt it:

- **resets the database** read from the bundle's `portal-ext.properties`
  (`jdbc.default.url` / `username` / `password`) — drops and recreates it, for
  PostgreSQL and MySQL/MariaDB; and
- **deletes** `data`, `work`, `elasticsearch`, `logs`, `osgi/state`, and the
  Tomcat `logs` / `work` / `temp` directories.

The database is reset **before** any folder is deleted, so a failed reset
aborts with nothing removed. Stop the bundle first, or the drop fails on active
connections.

**Docker databases.** A containerized database that publishes its port to the
host is reset through the normal path. If the database is only reachable inside
a container's network, the launcher prints what `portal-ext.properties` expects
plus the running containers and their ports, and lets you pick one to reset
inside via `docker exec`. To target a container directly (and skip the prompt),
pass `--db-docker <container>`:

```bash
lfrRunBundle --clean --db-docker pg-db
```

### Stopping the server

The script runs `catalina.sh run` (or `catalina.sh jpda run` in debug mode)
in the foreground, so `Ctrl+C` shuts the server down cleanly. No background
processes are left behind.

## What happens on launch

1. **Locates the Tomcat directory** inside the bundle. Handles all common
   layouts (`<bundle>/tomcat/`, `<bundle>/tomcat-9.x.y/`,
   `<bundle>/liferay-dxp/tomcat/`, …).
2. **Copies the Elasticsearch config** into `<bundle>/.../osgi/configs/`,
   but only if a file with the same name doesn't already exist there. So
   you can edit the deployed config and re-run without losing your changes.
3. **Probes 4 Tomcat ports** — `8080` (HTTP), `8005` (shutdown), `8009`
   (AJP), `8443` (HTTPS) — using `ss`, `lsof` or `netstat` (whichever is
   available on the system). Picks the next free port if any default is
   busy. Avoids self-collisions when bumping (e.g. won't pick `8081`
   for HTTP and again for shutdown).
4. **Backs up `tomcat/conf/server.xml`** to
   `server.xml.bak.<yyyymmdd-hhmmss>` and rewrites the connector ports —
   only when at least one port differs from what's already in the file.
   Re-running on the same setup leaves `server.xml` untouched.
5. **Starts Tomcat** in the foreground, prints the resolved HTTP URL and
   the path to `catalina.out`.

### Sample output (defaults free)

```
Bundle : ${HOME}/liferay/bundles/liferay-dxp-tomcat-2025.q1.14-lts-1748919610
Tomcat : .../liferay-dxp/tomcat

Elasticsearch config installed: .../osgi/configs/com.liferay.portal.search.elasticsearch7.configuration.ElasticsearchConfiguration.config

Selected ports:
  HTTP      8080
  SHUTDOWN  8005
  AJP       8009
  HTTPS     8443

Starting Liferay (Ctrl+C to stop).
  Editor / portal: http://localhost:8080/
  Logs           : .../tomcat/logs/catalina.out
```

### Sample output (8080 + 8005 already taken)

```
Selected ports:
  HTTP      8081   (default 8080 was busy)
  SHUTDOWN  8006   (default 8005 was busy)
  AJP       8009
  HTTPS     8443

server.xml backed up to .../server.xml.bak.20260505-113412
server.xml updated.

Starting Liferay (Ctrl+C to stop).
  Editor / portal: http://localhost:8081/
  ...
```

## Restoring original ports

If you want to roll a bundle back to its original ports, the most recent
backup file is in the same directory:

```bash
cp .../tomcat/conf/server.xml.bak.<latest> .../tomcat/conf/server.xml
```

The Elasticsearch config can be reset by deleting the deployed copy and
re-running the launcher:

```bash
rm <bundle>/.../osgi/configs/com.liferay.portal.search.elasticsearch7.configuration.ElasticsearchConfiguration.config
./start-liferay.sh
```

## Notes

- The script only modifies `server.xml` and writes one file into
  `osgi/configs/` on first run. It never touches the database, deploy
  folder, or anything else inside the bundle.
- It does **not** rewrite `portal-ext.properties` or `portal.properties`.
  If you need URL generation to use the resolved HTTP port (for example
  when running behind a reverse proxy), set `web.server.http.port`
  separately.
- Multiple bundles can be launched in parallel by calling the script with
  different bundle paths. Each call picks its own non-conflicting port
  set; the per-bundle `server.xml` keeps its own assigned ports between
  runs.
- `set -euo pipefail` is enabled in the script — it will exit non-zero
  on any unexpected failure (missing bundle, missing `catalina.sh`,
  etc.) before reaching the start phase.
