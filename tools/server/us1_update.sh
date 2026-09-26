#!/bin/sh
# US1 auto-update: run by the game panel BEFORE srcds starts, on every restart.
#   sh ./us1_update.sh; <the normal srcds start command>
# Pulls the `release` branch (built by .github/workflows/release.yml from main), checks every file against its
# MANIFEST.txt, then swaps in the four managed addon folders. It never touches data/, cfg/, garrysmod/lua, other
# addons or the Workshop cache. ANY failure leaves the current files alone and lets the server start as it is.
#
# Panel variables (Startup tab):
#   US1_GIT_URL   https://x-access-token:<READ-ONLY token>@github.com/necrosisdev/us1-server-code.git  (secret)
#   US1_BRANCH    default: release
#   US1_PIN       optional release commit sha to stay on (rollback); empty = newest
#   US1_UPDATE    1 = update (default), 0 = skip
# Optional: US1_ROOT (default: the folder this script is in), US1_TIMEOUT seconds (default 60).
set -u
ROOT=${US1_ROOT:-$(cd "$(dirname "$0")" && pwd)}
GMOD="$ROOT/garrysmod"
CACHE="$ROOT/.us1"
BRANCH=${US1_BRANCH:-release}
TIMEOUT=${US1_TIMEOUT:-60}
ADDONS="zcity ulx ulib us1"

log() { echo "[US1 update] $*"; }
quit() { log "$1 - starting with the files already installed"; exit 0; }

[ "${US1_UPDATE:-1}" = "0" ] && quit "US1_UPDATE=0"
[ -n "${US1_GIT_URL:-}" ] || quit "US1_GIT_URL is not set"
[ -d "$GMOD" ] || quit "no garrysmod/ folder under $ROOT"
run() { if command -v timeout >/dev/null 2>&1; then timeout "$TIMEOUT" "$@"; else "$@"; fi; }
REPO="$CACHE/release"
mkdir -p "$CACHE"

# 1. fetch (the token never reaches the log)
if command -v git >/dev/null 2>&1; then
    # a shallow clone kept between restarts
    if [ ! -d "$REPO/.git" ]; then
        rm -rf "$REPO"
        run git clone -q --depth 1 --branch "$BRANCH" "$US1_GIT_URL" "$REPO" >/dev/null 2>&1 || quit "clone failed"
    else
        git -C "$REPO" remote set-url origin "$US1_GIT_URL"
        run git -C "$REPO" fetch -q --depth 1 origin "$BRANCH" >/dev/null 2>&1 || quit "fetch failed"
        git -C "$REPO" checkout -q -f FETCH_HEAD >/dev/null 2>&1 || quit "checkout failed"
    fi
    if [ -n "${US1_PIN:-}" ]; then
        run git -C "$REPO" fetch -q --depth 1 origin "$US1_PIN" >/dev/null 2>&1 && git -C "$REPO" checkout -q -f FETCH_HEAD >/dev/null 2>&1 \
            || quit "pinned release $US1_PIN not found"
    fi
    git -C "$REPO" remote set-url origin "https://github.com/necrosisdev/us1-server-code.git" # no token left in .git/config
elif command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    # no git in this image: the same branch as a tarball through the GitHub API (token taken from US1_GIT_URL)
    TOKEN=$(printf '%s' "$US1_GIT_URL" | sed -n 's#^https://[^:]*:\([^@]*\)@.*#\1#p')
    [ -n "$TOKEN" ] || quit "no token in US1_GIT_URL"
    REF=${US1_PIN:-$BRANCH}
    rm -rf "$REPO" "$CACHE/release.tgz"; mkdir -p "$REPO"
    run curl -fsSL -H "Authorization: Bearer $TOKEN" -o "$CACHE/release.tgz" \
        "https://api.github.com/repos/necrosisdev/us1-server-code/tarball/$REF" >/dev/null 2>&1 || quit "download failed"
    tar -xzf "$CACHE/release.tgz" -C "$REPO" --strip-components=1 >/dev/null 2>&1 || quit "unpack failed"
    rm -f "$CACHE/release.tgz"
else
    quit "neither git nor curl+tar is installed in this container"
fi
# the release is named by the main commit it was built from (RELEASE.json "main")
SHA=$(sed -n 's/.*"main": *"\([0-9a-f]*\)".*/\1/p' "$REPO/RELEASE.json" 2>/dev/null | cut -c1-7)
[ -n "$SHA" ] || quit "release has no RELEASE.json"

# 2. already on this release? nothing to do
[ -f "$CACHE/installed" ] && [ "$(cat "$CACHE/installed")" = "$SHA" ] && { log "up to date ($SHA)"; exit 0; }

# 3. verify every file against the manifest ("<sha256>  <path>" lines, sha256sum format)
[ -f "$REPO/MANIFEST.txt" ] || quit "release $SHA has no MANIFEST.txt"
( cd "$REPO" && sha256sum -c --quiet --strict MANIFEST.txt ) >/dev/null 2>&1 || quit "release $SHA failed its checksum check"
for a in $ADDONS; do [ -d "$REPO/addons/$a" ] || quit "release $SHA is missing addons/$a"; done

# 4. stage all four, then swap (old copy kept as <name>.prev for a manual rollback)
for a in $ADDONS; do
    rm -rf "$GMOD/addons/$a.new"
    cp -R "$REPO/addons/$a" "$GMOD/addons/$a.new" || { for b in $ADDONS; do rm -rf "$GMOD/addons/$b.new"; done; quit "copy of $a failed"; }
done
for a in $ADDONS; do
    rm -rf "$GMOD/addons/$a.prev"
    [ -d "$GMOD/addons/$a" ] && mv "$GMOD/addons/$a" "$GMOD/addons/$a.prev"
    mv "$GMOD/addons/$a.new" "$GMOD/addons/$a"
done
mkdir -p "$GMOD/data"
cp "$REPO/RELEASE.json" "$GMOD/data/us1_version.txt" 2>/dev/null
echo "$SHA" > "$CACHE/installed"
# the next restart runs the release's own copy of this script (read by sh from a new file, so this run is unaffected)
[ -f "$REPO/us1_update.sh" ] && cp "$REPO/us1_update.sh" "$ROOT/us1_update.sh.new" && mv "$ROOT/us1_update.sh.new" "$ROOT/us1_update.sh"
log "installed release $SHA"
exit 0
