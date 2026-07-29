#!/bin/bash
# Generates the PC manifest (BattleScrolls.txt) from the console manifest
# (BattleScrolls.addon).
#
# The two platforms use structurally identical manifests -- same directives,
# same load order, same $(language) substitution -- and differ only in:
#
#   * file extension  : consoles read .addon, PC reads .txt
#   * ## APIVersion   : console API lags PC by roughly one update
#   * ## Description  : the console text names consoles specifically
#
# So .addon stays the single source of truth for load order and dependencies,
# and this script derives the PC copy. Both are committed so the repo can be
# symlinked straight into a PC AddOns folder.
#
# Usage:
#   ./scripts/sync-manifest.sh                          # regenerate the .txt
#   ./scripts/sync-manifest.sh --check                  # fail if .txt is stale
#   ./scripts/sync-manifest.sh --version 5.4.0 --addon-version 42
#
# Version placeholders default to dev values so a freshly cloned repo is
# directly playable; the release workflow substitutes real values first and
# they then pass through untouched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE="$PROJECT_ROOT/BattleScrolls/BattleScrolls.addon"
TARGET="$PROJECT_ROOT/BattleScrolls/BattleScrolls.txt"

# PC live + PTS. Bump when ESO ships a new update.
PC_API_VERSION="${PC_API_VERSION:-101050 101051}"
PC_DESCRIPTION="Combat metrics tracking with native gamepad UI. The journal requires Gamepad Mode."

VERSION="dev"
ADDON_VERSION="0"
CHECK_ONLY=false

while [ $# -gt 0 ]; do
    case "$1" in
        --check)         CHECK_ONLY=true; shift ;;
        --version)       VERSION="$2"; shift 2 ;;
        --addon-version) ADDON_VERSION="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ ! -f "$SOURCE" ]; then
    echo "Error: source manifest not found: $SOURCE" >&2
    exit 1
fi

generate() {
    sed \
        -e "s|^## APIVersion:.*|## APIVersion: ${PC_API_VERSION}|" \
        -e "s|^## Description:.*|## Description: ${PC_DESCRIPTION}|" \
        -e "s|{{addon_version}}|${ADDON_VERSION}|g" \
        -e "s|{{version}}|${VERSION}|g" \
        "$SOURCE"
}

if [ "$CHECK_ONLY" = true ]; then
    if [ ! -f "$TARGET" ]; then
        echo "Error: $TARGET is missing. Run ./scripts/sync-manifest.sh" >&2
        exit 1
    fi
    if ! diff -u "$TARGET" <(generate) > /dev/null; then
        echo "Error: BattleScrolls.txt is out of sync with BattleScrolls.addon." >&2
        echo "Diff (committed vs regenerated):" >&2
        diff -u "$TARGET" <(generate) >&2 || true
        echo "" >&2
        echo "Run ./scripts/sync-manifest.sh and commit the result." >&2
        exit 1
    fi
    echo "BattleScrolls.txt is in sync with BattleScrolls.addon."
    exit 0
fi

generate > "$TARGET"
echo "Wrote $TARGET"
echo "  APIVersion:   $PC_API_VERSION"
echo "  Version:      $VERSION"
echo "  AddOnVersion: $ADDON_VERSION"
