#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

XCODE_PROJECT="$PROJECT_DIR/mac/projectMacOS.xcodeproj"
BUILD_DIR="$PROJECT_DIR/mac/build/Release"
COMPONENT_NAME="foo_vis_projectMacOS.component"

SRC_COMPONENT="$BUILD_DIR/$COMPONENT_NAME"
SRC_BINARY="$SRC_COMPONENT/Contents/MacOS/foo_vis_projectMacOS"

FOOBAR_DIR="$HOME/Library/foobar2000-v2"
USER_COMPONENTS_DIR="$FOOBAR_DIR/user-components"
DEST_DIR="$USER_COMPONENTS_DIR/foo_vis_projectMacOS"
DEST_COMPONENT="$DEST_DIR/$COMPONENT_NAME"
DEST_BINARY="$DEST_COMPONENT/Contents/MacOS/foo_vis_projectMacOS"
LEGACY_DEST_DIR1="$USER_COMPONENTS_DIR/projectMacOS"
LEGACY_DEST_DIR2="$USER_COMPONENTS_DIR/foo_vis_projectM"

if pgrep -x "foobar2000" >/dev/null 2>&1; then
    echo "foobar2000 is running. I'll close it and rerun this script."
    exit 1
fi

if [ "${1:-}" = "--build" ]; then
    if [ "${SKIP_DEPS_BUILD:-0}" != "1" ]; then
        "$SCRIPT_DIR/build-deps.sh"
    fi
    xcodebuild -project "$XCODE_PROJECT" -configuration Release -arch x86_64 -arch arm64 clean build
fi

"$SCRIPT_DIR/run-tests.sh"

if [ ! -d "$SRC_COMPONENT" ]; then
    echo "Built component not found: $SRC_COMPONENT"
    echo "Run: $0 --build"
    exit 1
fi

mkdir -p "$DEST_DIR"
rm -rf "$LEGACY_DEST_DIR1" "$LEGACY_DEST_DIR2"
rm -rf "$DEST_COMPONENT"
cp -R "$SRC_COMPONENT" "$DEST_DIR/"

src_uuid_lines="$(dwarfdump --uuid "$SRC_BINARY" | awk '{print $2, $3}' | sort)"
dst_uuid_lines="$(dwarfdump --uuid "$DEST_BINARY" | awk '{print $2, $3}' | sort)"

echo "Source UUIDs:"
echo "$src_uuid_lines"
echo "Installed UUIDs:"
echo "$dst_uuid_lines"

if [ "$src_uuid_lines" != "$dst_uuid_lines" ]; then
    echo "Install verification failed: UUID mismatch"
    exit 1
fi

echo "Installed: $DEST_COMPONENT"

if [ -d "/Applications/foobar2000.app" ]; then
    open -a "foobar2000"
else
    echo "foobar2000.app not found in /Applications, skipping launch"
fi
