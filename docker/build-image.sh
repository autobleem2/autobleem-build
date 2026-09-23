#!/usr/bin/env bash
# Build the autobleem-build image (docker/Dockerfile) on a Docker host - the build server, in practice.
#
#   docker/build-image.sh                      -> autobleem-build:latest (and :<git sha>)
#   docker/build-image.sh --target pi          one of the stages: base, native, pi, mingw, db, psc, all
#   docker/build-image.sh --covers DIR         where coversJ.db/coversP.db/coversU.db are (see below)
#   docker/build-image.sh --no-cache           rebuild every layer
#   docker/build-image.sh --build-arg K=V ...  passed through (the versions in the Dockerfile)
#
# The cover databases are baked into the image (the db stage). They are not in git - this stages them into
# docker/db/ (git-ignored) from the first of --covers, $AB_COVERS_DIR, the checkout's db/ and the build
# server's old copy that holds the real files (not tools/make_usb.py's 5 KB stubs); with none of those, from
# the download repository's db/ ($AB_COVERS_URL), each file checked against its published .sha256.
set -euo pipefail
cd "$(dirname "$0")"

TAG="${AB_BUILD_IMAGE:-autobleem-build}"
TARGET=all
COVERS="${AB_COVERS_DIR:-}"
EXTRA=()
while [ $# -gt 0 ]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --covers) COVERS="$2"; shift 2 ;;
        --tag) TAG="$2"; shift 2 ;;
        --no-cache) EXTRA+=(--no-cache); shift ;;
        --build-arg) EXTRA+=(--build-arg "$2"); shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

real_covers() { # real_covers DIR - the three files, and not stubs
    local f
    [ -n "$1" ] || return 1
    for f in coversJ.db coversP.db coversU.db; do
        [ -f "$1/$f" ] && [ "$(stat -c %s "$1/$f")" -gt 1000000 ] || return 1
    done
}
# the download repository publishes the same three files with a .sha256 each - fetched into db/ (kept there
# between builds, re-fetched only when the published hash changes), so a build needs no local copy at all
fetch_covers() {
    local f want have
    mkdir -p db
    for f in coversJ.db coversP.db coversU.db; do
        want="$(curl -fsSL "$COVERS_URL/$f.sha256" | cut -c1-64)" || return 1
        have="$( [ -f "db/$f" ] && sha256sum "db/$f" | cut -c1-64 )"
        if [ "$have" != "$want" ]; then
            echo "    $COVERS_URL/$f"
            curl -fsSL -o "db/$f.part" "$COVERS_URL/$f" || return 1
            [ "$(sha256sum "db/$f.part" | cut -c1-64)" = "$want" ] || { echo "$f: sha256 mismatch" >&2; return 1; }
            mv "db/$f.part" "db/$f"
        fi
    done
}
COVERS_URL="${AB_COVERS_URL:-https://autobleem.retromenele.pl/db}"
FOUND=""
for dir in "$COVERS" ../db /AutoBleem/BUILD/data_that_gets_copied/cover_databases; do
    if real_covers "$dir"; then FOUND="$dir"; break; fi
done
if [ -n "$FOUND" ]; then
    mkdir -p db
    for f in coversJ.db coversP.db coversU.db; do
        if ! cmp -s "$FOUND/$f" "db/$f"; then cp "$FOUND/$f" "db/$f"; fi
    done
    echo "==> cover databases from $FOUND ($(du -sh db | cut -f1))"
else
    echo "==> cover databases from $COVERS_URL (no local copy)"
    fetch_covers || { echo "cover databases: none found locally and the download failed - give --covers DIR" >&2; exit 1; }
    echo "    $(du -sh db | cut -f1) in docker/db"
fi

SHA="$(git -C .. rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "==> docker build --target $TARGET -t $TAG:latest -t $TAG:$SHA"
DOCKER_BUILDKIT=1 docker build --target "$TARGET" -t "$TAG:latest" -t "$TAG:$SHA" "${EXTRA[@]}" .
docker image ls "$TAG"
