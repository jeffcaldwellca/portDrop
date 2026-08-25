#!/usr/bin/env bash
# Generates the Sparkle appcast for one release zip, signed with the EdDSA private key.
# Usage: Scripts/make-appcast.sh <dist/PortDrop-<version>.zip> <private-key-file> [out.xml] [release-notes.md]
#
# Uses Sparkle's own generate_appcast (same version as the framework pinned in project.yml),
# downloaded into build/sparkle-tools on first use. The zip's download URL points at the GitHub
# Release for that version; the app reads the feed via releases/latest/download/appcast.xml.
set -euo pipefail
cd "$(dirname "$0")/.."

ZIP=${1:?usage: make-appcast.sh <zip> <private-key-file> [out.xml] [notes.md]}
KEY=${2:?private key file}
OUT=${3:-dist/appcast.xml}
NOTES=${4:-}
[[ -f "$ZIP" ]] || { echo "zip not found: $ZIP" >&2; exit 1; }
[[ -f "$KEY" ]] || { echo "private key file not found: $KEY" >&2; exit 1; }

VERSION=$(basename "$ZIP" .zip); VERSION=${VERSION#PortDrop-}
SPARKLE_VERSION=$(sed -nE 's/^ *from: "([0-9.]+)"/\1/p' project.yml | head -1)
TOOLS="build/sparkle-tools/$SPARKLE_VERSION"
if [[ ! -x "$TOOLS/bin/generate_appcast" ]]; then
  echo "▸ Fetching Sparkle $SPARKLE_VERSION tools"
  mkdir -p "$TOOLS"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "$TOOLS"
fi

# generate_appcast works on a directory of archives; stage just this zip (and its notes) so the
# feed contains exactly one item.
STAGE=build/appcast
rm -rf "$STAGE"; mkdir -p "$STAGE" "$(dirname "$OUT")"
cp "$ZIP" "$STAGE/"
[[ -n "$NOTES" ]] && cp "$NOTES" "$STAGE/PortDrop-$VERSION.md"

echo "▸ Generating appcast for $VERSION"
"$TOOLS/bin/generate_appcast" \
  --ed-key-file "$KEY" \
  --download-url-prefix "https://github.com/jeffcaldwellca/portDrop/releases/download/v$VERSION/" \
  --link "https://github.com/jeffcaldwellca/portDrop" \
  --full-release-notes-url "https://github.com/jeffcaldwellca/portDrop/releases/tag/v$VERSION" \
  --embed-release-notes \
  -o "$OUT" "$STAGE"
grep -q "sparkle:edSignature" "$OUT" || { echo "appcast has no EdDSA signature" >&2; exit 1; }
echo "✓ $OUT"
