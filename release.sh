#!/bin/sh
# release.sh — build, package, and publish a GitHub release of WacomTablet.app.
#
# Usage:  ./release.sh <tag>        e.g.  ./release.sh v1.1.0
#
# Builds the arm64 release (Apple Silicon only), assembles a signed
# WacomTablet.app, zips it, and uploads it to a GitHub release for <tag>:
#   - if the release/tag already exists, the asset is replaced (--clobber);
#   - otherwise a new release is created with auto-generated notes.
#
# Signing: ad-hoc by default (stable until the next rebuild). For a signature
# that survives rebuilds, pass SIGN_IDENTITY="Your Code Signing Cert".
set -e

TAG="$1"
[ -n "$TAG" ] || { echo "usage: ./release.sh <tag>   (e.g. v1.1.0)"; exit 1; }

APP_NAME="WacomTablet"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(git rev-parse --short HEAD 2>/dev/null || echo "$TAG")"
STAGE="$(mktemp -d)"
APP="$STAGE/$APP_NAME.app"
ZIP="$STAGE/$APP_NAME.app.zip"
trap 'rm -rf "$STAGE"' EXIT

command -v gh >/dev/null || { echo "error: gh (GitHub CLI) not found"; exit 1; }

echo "==> Building release binary (arm64)"
"$HERE/build.sh" release >/dev/null
BIN="$HERE/.build/release/$APP_NAME"
[ -f "$BIN" ] || { echo "build failed: $BIN missing"; exit 1; }
case "$(file -b "$BIN")" in
    *arm64*) ;;
    *) echo "warning: $BIN is not arm64 — $(file -b "$BIN")" ;;
esac

echo "==> Assembling $APP_NAME.app ($VERSION)"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
sed "s/__VERSION__/$VERSION/g" "$HERE/packaging/Info.plist" > "$APP/Contents/Info.plist"

echo "==> Signing ($SIGN_IDENTITY)"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify "$APP"

echo "==> Zipping"
( cd "$STAGE" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.app.zip" )

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "==> Release $TAG exists — replacing asset"
    gh release upload "$TAG" "$ZIP" --clobber
else
    echo "==> Creating release $TAG"
    gh release create "$TAG" "$ZIP" \
        --title "$TAG — Cintiq 21UX userspace driver" \
        --generate-notes
fi

echo
echo "Published: $(gh release view "$TAG" --json url --jq .url)"
