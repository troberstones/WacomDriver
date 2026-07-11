#!/bin/sh
# install.sh — build the driver, assemble a proper WacomTablet.app bundle, and
# install a LaunchAgent so it runs at login and restarts on crash.
#
# Personal-use install (no notarization). TCC permissions (Input Monitoring +
# Accessibility) attach to the signed bundle, so they persist as long as the
# code identity is stable:
#   - ad-hoc signature (default): stable until the next rebuild changes the hash;
#     you'll re-approve permissions after a rebuild.
#   - stable identity: create a self-signed "Code Signing" cert in Keychain once,
#     then run  SIGN_IDENTITY="Your Cert Name" ./install.sh  — permissions then
#     survive rebuilds.
set -e

APP_NAME="WacomTablet"
BUNDLE_ID="com.chwacom.WacomTablet"
INSTALL_DIR="/Applications"
APP="$INSTALL_DIR/$APP_NAME.app"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
LOG="$HOME/Library/Logs/$BUNDLE_ID.log"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # default: ad-hoc ("-")
VERSION="$(git rev-parse --short HEAD 2>/dev/null || echo 1.0)"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Building release binary"
"$HERE/build.sh" release >/dev/null
BIN="$HERE/.build/release/$APP_NAME"
[ -f "$BIN" ] || { echo "build failed: $BIN missing"; exit 1; }

echo "==> Assembling $APP_NAME.app (version $VERSION)"
# Stop a running instance so we can overwrite the bundle.
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
sed "s/__VERSION__/$VERSION/g" "$HERE/packaging/Info.plist" > "$APP/Contents/Info.plist"

echo "==> Signing ($SIGN_IDENTITY)"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP" >/dev/null 2>&1 \
    || codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "==> Installing LaunchAgent"
mkdir -p "$(dirname "$AGENT")" "$(dirname "$LOG")"
sed -e "s|__APP__|$APP|g" -e "s|__LOG__|$LOG|g" \
    "$HERE/packaging/com.chwacom.WacomTablet.plist" > "$AGENT"

# Reload the agent.
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT"
launchctl enable "gui/$(id -u)/$BUNDLE_ID"

cat <<EOF

Installed:
  App:         $APP
  LaunchAgent: $AGENT
  Log:         $LOG

The driver is now running and will start at login.

First run only: grant permissions in System Settings > Privacy & Security, then
the driver will restart itself and work:
  - Input Monitoring   -> enable "$APP_NAME"
  - Accessibility      -> enable "$APP_NAME"

Manage it:
  Stop:    launchctl bootout  gui/$(id -u)/$BUNDLE_ID
  Start:   launchctl bootstrap gui/$(id -u) "$AGENT"
  Logs:    tail -f "$LOG"
  Remove:  ./uninstall.sh
EOF
