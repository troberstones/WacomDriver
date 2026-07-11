#!/bin/sh
# uninstall.sh — stop and remove the driver's LaunchAgent and app bundle.
# Leaves your config (~/.config/wacomd) in place.
set -e

BUNDLE_ID="com.chwacom.WacomTablet"
APP="/Applications/WacomTablet.app"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

echo "==> Stopping and removing LaunchAgent"
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
rm -f "$AGENT"

echo "==> Removing app bundle"
rm -rf "$APP"

echo "Done. Config kept at ~/.config/wacomd (delete it manually to fully reset)."
