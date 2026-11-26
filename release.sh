#!/bin/bash
# Publie mSOUND : compilation locale, copie signée Developer ID, notarisation, agrafage, zip, release GitHub.
# Usage : ./release.sh [--notes "texte"] [--replace]   — version lue dans VERSION.
set -euo pipefail
cd "$(dirname "$0")"
TOOLS="/Volumes/SKYRIM/TOOLS/MAC/_tools"
OWNER="starbudweiser"; REPO="mSOUND"
NOTES=""; REPLACE=0
while [ $# -gt 0 ]; do case "$1" in --notes) NOTES="${2:-}"; shift ;; --replace) REPLACE=1 ;; *) echo "option inconnue : $1" >&2; exit 1 ;; esac; shift; done

[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "release : modifications non commitées" >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "release : pas synchronisé avec origin/main" >&2; exit 1; }

./build_app.sh
APP="$HOME/Applications/Applications Personnelles/mSOUND.app"
version="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"; tag="v$version"
if gh release view "$tag" -R "$OWNER/$REPO" >/dev/null 2>&1 && [ "$REPLACE" != 1 ]; then echo "release : $tag existe déjà (--replace)" >&2; exit 1; fi

DIST="$PWD/build/notarized" "$TOOLS/notarize_app.sh" "$APP"
stage="$(mktemp -d)"; asset="$REPO-$version-macOS-arm64.zip"
cp "$PWD/build/notarized/mSOUND.zip" "$stage/$asset"; (cd "$stage" && shasum -a 256 "$asset" > "$asset.sha256")
if gh release view "$tag" -R "$OWNER/$REPO" >/dev/null 2>&1; then
    gh release upload "$tag" -R "$OWNER/$REPO" --clobber "$stage/$asset" "$stage/$asset.sha256"
else
    if [ -n "$NOTES" ]; then n=(--notes "$NOTES"); else n=(--generate-notes); fi
    gh release create "$tag" -R "$OWNER/$REPO" --target main --title "mSOUND $version" "${n[@]}" "$stage/$asset" "$stage/$asset.sha256"
fi
echo "✓ https://github.com/$OWNER/$REPO/releases/tag/$tag"
