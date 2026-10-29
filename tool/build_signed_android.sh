#!/usr/bin/env bash
set -euo pipefail

# The signing password is captured in memory and never printed.
export RADAR_RELEASE_STORE_FILE="${RADAR_RELEASE_STORE_FILE:-$HOME/.local/share/radar-local/android-release.p12}"
export RADAR_RELEASE_STORE_PASSWORD="$(pass show radar-local/android-release)"
export RADAR_RELEASE_KEY_ALIAS="radar-local"
export RADAR_RELEASE_KEY_PASSWORD="$RADAR_RELEASE_STORE_PASSWORD"
trap 'unset RADAR_RELEASE_STORE_PASSWORD RADAR_RELEASE_KEY_PASSWORD' EXIT

"${FLUTTER_BIN:-flutter}" build apk --release
