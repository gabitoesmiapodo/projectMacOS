#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEPS_DIR="$PROJECT_DIR/deps"
ARCHS=(x86_64 arm64)
ARCHS_CMAKE="x86_64;arm64"

echo "Building dependencies for ${ARCHS[*]}..."

has_all_arches() {
    local file="$1"
    local arch_list

    arch_list="$(lipo -archs "$file" 2>/dev/null || true)"
    for arch in "${ARCHS[@]}"; do
        [[ "$arch_list" == *"$arch"* ]] || return 1
    done
    return 0
}

# 1. Build foobar2000 SDK static libraries
echo ""
echo "=== Building foobar2000 SDK ==="
SDK="$DEPS_DIR/foobar2000-sdk"

for proj in \
    "$SDK/pfc/pfc.xcodeproj" \
    "$SDK/foobar2000/SDK/foobar2000_SDK.xcodeproj" \
    "$SDK/foobar2000/helpers/foobar2000_SDK_helpers.xcodeproj" \
    "$SDK/foobar2000/foobar2000_component_client/foobar2000_component_client.xcodeproj" \
    "$SDK/foobar2000/shared/shared.xcodeproj"; do
    echo "  Building $(basename "$proj" .xcodeproj)..."
    xcodebuild -project "$proj" -configuration Release -arch x86_64 -arch arm64 build -quiet
done

echo "SDK libraries built."

# 2. Build and install projectM 4 locally
echo ""
echo "=== Building projectM 4 ==="
PROJECTM_LIB="$DEPS_DIR/projectm/lib"
mkdir -p "$PROJECTM_LIB"

if [ -f "$PROJECTM_LIB/libprojectM-4.a" ] && [ -f "$PROJECTM_LIB/libprojectM-4-playlist.a" ] \
   && has_all_arches "$PROJECTM_LIB/libprojectM-4.a" \
   && has_all_arches "$PROJECTM_LIB/libprojectM-4-playlist.a"; then
    echo "projectM universal static libs already built, skipping."
else
    rm -f "$PROJECTM_LIB"/libprojectM-4*.a

    TMPDIR="$(mktemp -d)"
    echo "  Cloning projectM v4.1.6..."
    git clone --recurse-submodules --depth 1 --branch v4.1.6 \
        https://github.com/projectM-visualizer/projectm.git "$TMPDIR/projectm" 2>&1 | tail -1

    echo "  Configuring..."
    mkdir "$TMPDIR/projectm/cmake-build"
    cmake -S "$TMPDIR/projectm" -B "$TMPDIR/projectm/cmake-build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$TMPDIR/install" \
        -DENABLE_PLAYLIST=ON \
        -DCMAKE_OSX_ARCHITECTURES="$ARCHS_CMAKE" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
        -DENABLE_SDL_UI=OFF \
        -DENABLE_TESTING=OFF \
        -DENABLE_DOCS=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        > /dev/null 2>&1

    echo "  Building..."
    cmake --build "$TMPDIR/projectm/cmake-build" --parallel "$(sysctl -n hw.ncpu)" > /dev/null 2>&1

    echo "  Installing locally..."
    cmake --install "$TMPDIR/projectm/cmake-build" > /dev/null 2>&1

    # Copy headers if not already present
    if [ ! -d "$DEPS_DIR/projectm/include/projectM-4" ]; then
        mkdir -p "$DEPS_DIR/projectm/include"
        cp -R "$TMPDIR/install/include/projectM-4" "$DEPS_DIR/projectm/include/"
    fi

    # Copy static libraries
    cp "$TMPDIR/install/lib"/libprojectM-4*.a "$PROJECTM_LIB/"

    rm -rf "$TMPDIR"
    echo "projectM built and installed to deps/projectm/"
fi

echo ""
echo "All dependencies built for ${ARCHS[*]}."
echo ""
echo "SDK static libraries:"
ls "$SDK/pfc/build/Release/"*.a "$SDK/foobar2000/SDK/build/Release/"*.a \
   "$SDK/foobar2000/helpers/build/Release/"*.a \
   "$SDK/foobar2000/foobar2000_component_client/build/Release/"*.a \
   "$SDK/foobar2000/shared/build/Release/"*.a 2>/dev/null
echo ""
echo "projectM static libraries:"
ls "$PROJECTM_LIB"/*.a 2>/dev/null
