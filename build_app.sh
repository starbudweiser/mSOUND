#!/bin/bash
# Construit mSOUND.app (ou, avec DEV=1, « mSOUND dev.app », identifiant …dev, schéma msound-dev), avec son extension Finder,
# la signe (certificat stable, extension sandboxée) et installe la version normale dans Applications Personnelles.
set -euo pipefail
cd "$(dirname "$0")"
TOOLS="/Volumes/SKYRIM/TOOLS/MAC/_tools"
if [ -n "${DEV:-}" ]; then NAME="mSOUND dev"; ID="fr.stephan.msound.dev"; SCHEME="msound-dev"; DEST="$PWD"
else NAME="mSOUND"; ID="fr.stephan.msound"; SCHEME="msound"; DEST="$HOME/Applications/Applications Personnelles"; fi
VERSION="$(cat VERSION 2>/dev/null || echo 0.1.0)"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="$PWD/build/$NAME.app"; EXT="$APP/Contents/PlugIns/mSOUNDFinder.appex"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
cp "$BIN/mSOUND" "$APP/Contents/MacOS/mSOUND"
cp "$BIN/mSOUNDFinder" "$EXT/Contents/MacOS/mSOUNDFinder"
[ -f assets/mSOUND.icns ] && cp assets/mSOUND.icns "$APP/Contents/Resources/mSOUND.icns"

cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>mSOUND</string>
<key>CFBundleIdentifier</key><string>$ID</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleIconFile</key><string>mSOUND</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>$ID</string>
<key>CFBundleURLSchemes</key><array><string>$SCHEME</string></array></dict></array>
</dict></plist>
P
cat > "$EXT/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>mSOUNDFinder</string>
<key>CFBundleIdentifier</key><string>$ID.finder</string>
<key>CFBundleName</key><string>$NAME Finder</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSExtension</key><dict>
<key>NSExtensionPointIdentifier</key><string>com.apple.FinderSync</string>
<key>NSExtensionPrincipalClass</key><string>MSoundFinderSync</string>
</dict></dict></plist>
P
cat > build/ext.entitlements <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.temporary-exception.shared-preference.read-only</key>
<array><string>fr.stephan.msound</string><string>fr.stephan.msound.dev</string></array>
</dict></plist>
P
SIGN_ENTITLEMENTS="$PWD/build/ext.entitlements" SIGN_NO_DEEP=1 "$TOOLS/sign_app.sh" "$EXT"
SIGN_NO_DEEP=1 "$TOOLS/sign_app.sh" "$APP"

pkill -x mSOUND 2>/dev/null || true
rm -rf "$DEST/$NAME.app"; mkdir -p "$DEST"; cp -R "$APP" "$DEST/$NAME.app"
# L'extension Finder : activée pour la version installée, ignorée pour la version de développement (évite les doublons de menu).
EXTP="$DEST/$NAME.app/Contents/PlugIns/mSOUNDFinder.appex"
# L'enregistrement par pluginkit est asynchrone après la copie : on réessaie jusqu'à ce que l'extension soit connue.
for i in 1 2 3 4 5 6 7 8 9 10; do
  pluginkit -a "$EXTP" 2>/dev/null || true
  if [ -n "${DEV:-}" ]; then pluginkit -e ignore -i "$ID.finder" 2>/dev/null || true; else pluginkit -e use -i "$ID.finder" 2>/dev/null || true; fi
  pluginkit -m -i "$ID.finder" 2>/dev/null | grep -q "$ID.finder" && break
  sleep 1
done
[ -n "${DEV:-}" ] || killall Finder 2>/dev/null || true
echo "✓ $DEST/$NAME.app"
