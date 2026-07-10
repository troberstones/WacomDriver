#!/bin/sh
# Build helper. The project's on-disk .build/build.db hits intermittent SQLite
# "disk I/O error"s on this filesystem, which silently skips the link step and
# leaves a stale (or missing) binary. Building to /tmp avoids it; we then copy
# the products back to .build/release so the usual run paths work.
set -e
SCRATCH=/tmp/wacomdbuild
CONFIG="${1:-release}"

swift build -c "$CONFIG" --scratch-path "$SCRATCH"

mkdir -p ".build/$CONFIG"
for prod in wacomd wacom-dump wacom-inject-test WacomTablet; do
    if [ -f "$SCRATCH/$CONFIG/$prod" ]; then
        cp "$SCRATCH/$CONFIG/$prod" ".build/$CONFIG/$prod"
    fi
done
echo "built ($CONFIG) -> .build/$CONFIG/"
